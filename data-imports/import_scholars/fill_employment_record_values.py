import argparse
import json
import os
from pathlib import Path
import pandas as pd
import tempfile
from sf_command import (
    run_sf_command,
    normalize_sf_value as normalize_mapped_value,
    is_sandbox_org,
    create_sf_record, 
    escape_soql_string,
    is_boolean_deserialize_error,
    get_sobject_from_id,
    set_target_org,
    CPL_MEMBER_RECORD_TYPE_ID,
    REST_API_VERSION
)

DEFAULT_TARGET_ORG = "CPLProduction"
TARGET_ORG_ALIASES = {
    "dev": "cpl-sandbox",
    "sandbox": "cpl-sandbox",
    "prod": "CPLProduction",
    "production": "CPLProduction",
}
RECORD_TYPE_ID_FIELD = "RecordTypeId"
INTERNSHIP_FIELD = "internship_json"
FULLTIME_FIELD = "fulltime_json"
BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DRY_RUN_OUTPUT = BASE_DIR / "debug" / "employment_records_dry_run.csv"

FULLTIME_RECORD_TYPE_DEVELOPER_NAME = "Full_time"
INTERNSHIP_RECORD_TYPE_DEVELOPER_NAME = "Internship"

EMPLOYMENT_MAPPER = {
    "Start Date" : "Start_Date__c",
    "Role" : "Job_Title__c",
    "Internship Season" : "Internship_Season__c",
    "Country" : "Country__c",
    "State" : "State__c", 
    "Note" : "Notes__c",
    "Record Type" : "Employment_Type__c",
    "RecordTypeId" : "RecordTypeId"
}

EMPLOYMENT_TYPE_MAPPER = {
    "Full-Time Role": "Full-time",
    "Fulltime": "Full-time",
    "Full Time": "Full-time",
}


def normalize_value(value, sf_field=None):
    if value is None or pd.isna(value):
        return None

    if isinstance(value, str):
        value = value.strip()
        if not value:
            return None

    if sf_field == "Employment_Type__c":
        return EMPLOYMENT_TYPE_MAPPER.get(value, value)

    return value


def parse_employment_json(value):
    value = normalize_value(value)

    if not value:
        return {}

    return json.loads(value)


def has_employment_data(employment):
    meaningful_fields = [
        "Role",
        "Company Name",
        "Note",
        "Record Type",
        "Internship Season",
        "State",
    ]

    if any(normalize_value(employment.get(field)) for field in meaningful_fields):
        return True

    start_date = normalize_value(employment.get("Start Date"))
    return start_date is not None and start_date != "1900-01-01"


def resolve_target_org(target_org):
    return TARGET_ORG_ALIASES.get(target_org.lower(), target_org)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create Employment__c records from cpl-members-cleaned.csv."
    )
    parser.add_argument(
        "--target-org",
        default=os.environ.get("SF_TARGET_ORG", DEFAULT_TARGET_ORG),
        help=(
            "Salesforce org alias. Short aliases: dev/sandbox => cpl-sandbox, "
            "prod/production => CPLProduction. Defaults to CPLProduction or "
            "SF_TARGET_ORG."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Build the Employment__c rows and write them to CSV without importing.",
    )
    parser.add_argument(
        "--dry-run-output",
        default=str(DEFAULT_DRY_RUN_OUTPUT),
        help="CSV path to write when --dry-run is used.",
    )

    return parser.parse_args()


def get_record_type_id(sobject, developer_name, target_org):
    query = (
        "SELECT Id "
        "FROM RecordType "
        f"WHERE SobjectType = '{sobject}' "
        f"AND DeveloperName = '{developer_name}' "
        "LIMIT 1"
    )

    result = run_sf_command([
        "sf",
        "data",
        "query",
        "--query",
        query,
        "--json",
        "--target-org",
        target_org,
    ])

    if not result:
        raise RuntimeError(
            f"Failed to query {sobject}.{developer_name} record type"
        )

    records = result.get("result", {}).get("records", [])

    if not records:
        raise RuntimeError(
            f"No {sobject}.{developer_name} record type found in {target_org}"
        )

    return records[0]["Id"]


def get_existing_records(df, record_type_id, target_org):
    if df.empty:
        return {}

    emails = (
        df["Email"]
        .dropna()
        .astype(str)
        .str.strip()
        .unique()
        .tolist()
    )

    if not emails:
        return {}

    email_field = "PersonEmail"
    name_fields = "FirstName, LastName"

    email_values = ", ".join(
        f"'{escape_soql_string(email)}'"
        for email in emails
    )

    query = (
        f"SELECT Id, {name_fields}, {email_field} "
        f"FROM Account "
        f"WHERE RecordTypeId = '{record_type_id}' "
        f"AND {email_field} IN ({email_values})"
    )

    result = run_sf_command([
        "sf",
        "data",
        "query",
        "--query",
        query,
        "--json",
        "--target-org",
        target_org,
    ])

    if not result:
        raise RuntimeError(f"Failed to query existing Account records")

    return {
        record[email_field].strip().lower(): record
        for record in result["result"]["records"]
        if record.get(email_field)
    }


def get_members_with_employments(existing_records, target_org):
    member_ids = sorted(
        {
            record["Id"]
            for record in existing_records.values()
            if record.get("Id")
        }
    )

    if not member_ids:
        return set()

    member_values = ", ".join(
        f"'{escape_soql_string(member_id)}'"
        for member_id in member_ids
    )

    query = (
        "SELECT Id, CPL_Member__c "
        "FROM Employment__c "
        f"WHERE CPL_Member__c IN ({member_values})"
    )

    result = run_sf_command([
        "sf",
        "data",
        "query",
        "--query",
        query,
        "--json",
        "--target-org",
        target_org,
    ])

    if not result:
        raise RuntimeError("Failed to query existing Employment records")

    return {
        record["CPL_Member__c"]
        for record in result["result"]["records"]
        if record.get("CPL_Member__c")
    }


def process_row(
    row,
    existing_records,
    members_with_employments,
    internship_record_type_id,
    fulltime_record_type_id,
):
    email = normalize_value(row.get("Email"))

    if not email:
        return None
    
    existing = existing_records.get(email.lower())
    
    if not existing:
        print(f"Record not found: {email}")
        return None

    if existing.get("Id") in members_with_employments:
        return None
    
    internship = parse_employment_json(row.get(INTERNSHIP_FIELD))
    fulltime = parse_employment_json(row.get(FULLTIME_FIELD))
    
    if not has_employment_data(internship) and not has_employment_data(fulltime):
        return None
    
    employment_records = []
    
    def process(json_obj):
        res = {
            "CPL_Member__c" : existing.get("Id")
        }

        company_name = normalize_value(json_obj.get("Company Name"))

        for csv_field, sf_field in EMPLOYMENT_MAPPER.items():
            csv_value = normalize_value(json_obj.get(csv_field), sf_field)
            
            if csv_value is not None:
                res[sf_field] = csv_value

        if company_name:
            note = normalize_value(res.get("Notes__c"))
            company_note = f"Company Name: {company_name}"
            res["Notes__c"] = (
                f"{company_note}\n{note}"
                if note
                else company_note
            )

        employment_records.append(res)
    
    if has_employment_data(internship):
        internship["RecordTypeId"] = internship_record_type_id
        process(internship)
        
    if has_employment_data(fulltime): 
        fulltime["RecordTypeId"] = fulltime_record_type_id
        process(fulltime)
        
    return employment_records


def write_dry_run(employments, output_file):
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    employment_df = pd.DataFrame(employments)
    employment_df.to_csv(output_path, index=False)

    print(f"Dry run only. Wrote {len(employments)} Employment rows to {output_path}")

    if not employment_df.empty:
        print("\nPreview:")
        print(employment_df.head(10).to_string(index=False))

    return output_path


def create_employments(employments, target_org):
    if not employments:
        print("No employment records to create.")
        return None

    employment_df = pd.DataFrame(employments)

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".csv",
        delete=False,
        newline="",
    ) as temp_file:

        employment_df.to_csv(
            temp_file.name,
            index=False,
        )

        temp_path = temp_file.name

    print(f"Creating {len(employments)} Employment records...")

    try:
        result = run_sf_command([
            "sf",
            "data",
            "import",
            "bulk",
            "--sobject",
            "Employment__c",
            "--file",
            temp_path,
            "--target-org",
            target_org,
            "--wait",
            "10",
            "--json",
        ])

        print(result)

        return result

    finally:
        Path(temp_path).unlink(missing_ok=True)

def main():
    args = parse_args()
    target_org = resolve_target_org(args.target_org)
    set_target_org(target_org)

    internship_record_type_id = get_record_type_id(
        "Employment__c",
        INTERNSHIP_RECORD_TYPE_DEVELOPER_NAME,
        target_org,
    )
    fulltime_record_type_id = get_record_type_id(
        "Employment__c",
        FULLTIME_RECORD_TYPE_DEVELOPER_NAME,
        target_org,
    )

    print(f"Target org: {target_org}")
    print(f"Internship record type: {internship_record_type_id}")
    print(f"Full-time record type: {fulltime_record_type_id}")

    # Load the scholars data from the CSV file
    input_file = Path("clean/cpl-members-cleaned.csv")
    df = pd.read_csv(
        input_file, 
        usecols=[
            "First_Name",
            "Last_Name",
            "Email",
            RECORD_TYPE_ID_FIELD, 
            INTERNSHIP_FIELD,
            FULLTIME_FIELD
        ]
    )
    
    member_df = df[
            df[RECORD_TYPE_ID_FIELD] == CPL_MEMBER_RECORD_TYPE_ID
        ]
        
    member_existing = get_existing_records(
        member_df, 
        CPL_MEMBER_RECORD_TYPE_ID,
        target_org,
    )

    members_with_employments = get_members_with_employments(
        member_existing,
        target_org,
    )

    print(f"Members with existing Employment records: {len(members_with_employments)}")
    
    employment_groups = (
        member_df.apply(
            lambda row: process_row(
                row,
                member_existing,
                members_with_employments,
                internship_record_type_id,
                fulltime_record_type_id,
            ),
            axis=1,
        )
        .dropna()
        .tolist()
    )
    
    member_employments = [
        employment
        for group in employment_groups
        for employment in group
    ]

    print(f"Employment records to create: {len(member_employments)}")

    if args.dry_run:
        write_dry_run(member_employments, args.dry_run_output)
        return

    create_employments(member_employments, target_org)

if __name__ == "__main__":
    main()
