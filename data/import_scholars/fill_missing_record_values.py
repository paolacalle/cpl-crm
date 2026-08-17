import json
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
    LEAD_SCHOLAR_RECORD_TYPE_ID,
    TARGET_ORG,
    REST_API_VERSION
)

set_target_org("CPLProduction")
TARGET_ORG = "CPLProduction"

member_column_mapper = {
    "Primary_Sport": "Primary_Sport__pc",
    "Commits_to_CPL_mantra": "Commits_to_CPL_mantra__pc",
    "Tell_us_a_little_about_yourself!": "Why_CPL__pc",
    "Predicted_Current_College_Year": "College_Year__pc",
    
    # "CPL Student Lifecycle": "CPL_Student_Lifecycle__c",
    
    "School_Id": "School__pc",
    # "University_or_College_Enrolled_At": "School_Name_From_Form__pc",
    
    "Submission_Date": "Submission_Date__pc",
}

lead_column_mapper = {
    "Primary_Sport": "Primary_Sport__c",
    "Commits_to_CPL_mantra": "Commits_to_CPL_mantra__c",
    "Tell_us_a_little_about_yourself!": "Why_CPL_Scholar__c",
    
    "Predicted_Current_College_Year": "College_Year__c",
    "School_Id": "School__c",
    "University_or_College_Enrolled_At": "School_Name_From_Form__c",
    
    "Status": "Status",
    "Submission_Date": "Submission_Date__c",
}

# columns 
RECORD_TYPE_ID_FIELD = "RecordTypeId"

boolean_fields = {
    "Commits_to_CPL_mantra__pc",
    "Commits_to_CPL_mantra__c",
}


def normalize_value(value, sf_field=None):
    if value is None or pd.isna(value):
        return None

    if isinstance(value, str):
        value = value.strip()
        if not value:
            return None

    if sf_field:
        return normalize_mapped_value(sf_field, value, boolean_fields)

    return value


def get_existing_records(df, sfobject, record_type_id, mapper):
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

    email_field = "PersonEmail" if sfobject == "Account" else "Email"
    name_fields = "FirstName, LastName"
    sf_fields = ", ".join(sorted(set(mapper.values())))

    email_values = ", ".join(
        f"'{escape_soql_string(email)}'"
        for email in emails
    )

    query = (
        f"SELECT Id, {name_fields}, {email_field}, {sf_fields} "
        f"FROM {sfobject} "
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
        TARGET_ORG,
    ])

    if not result:
        raise RuntimeError(f"Failed to query existing {sfobject} records")

    return {
        record[email_field].strip().lower(): record
        for record in result["result"]["records"]
        if record.get(email_field)
    }
    
def process_row(row, existing_records, mapper):
    email = normalize_value(row.get("Email"))

    if not email:
        return None

    existing = existing_records.get(email.lower())

    if not existing:
        print(f"Record not found: {email}")
        return None

    update = {
        "Id": existing["Id"]
    }

    for csv_field, sf_field in mapper.items():
        csv_value = normalize_value(row.get(csv_field), sf_field)
        sf_value = normalize_value(existing.get(sf_field), sf_field)

        # CSV has a value and Salesforce is missing one
        if csv_value is not None and sf_value is None:
            update[sf_field] = csv_value

    # Nothing needs updating
    if len(update) == 1:
        return None

    return update

def push_updates(updates, sfobject):
    if not updates:
        print(f"No {sfobject} updates to push.")
        return None

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".csv",
        delete=False,
        newline="",
    ) as temp_file:

        update_df = pd.DataFrame(updates)

        # Make sure Id is the first column
        columns = ["Id"] + [
            col for col in update_df.columns
            if col != "Id"
        ]

        update_df = update_df[columns]

        update_df.to_csv(
            temp_file.name,
            index=False,
        )

        temp_path = temp_file.name

    print(f"Pushing {len(updates)} {sfobject} updates...")

    result = run_sf_command([
        "sf",
        "data",
        "update",
        "bulk",
        "--sobject",
        sfobject,
        "--file",
        temp_path,
        "--target-org",
        TARGET_ORG,
        "--wait",
        "10",
        "--json",
    ])

    Path(temp_path).unlink(missing_ok=True)

    if not result:
        raise RuntimeError(
            f"Failed to bulk update {sfobject}"
        )

    return result

def main():
    # Load the scholars data from the CSV file
    input_file = Path("clean/cpl-members-cleaned.csv")
    df = pd.read_csv(input_file)
    
    # clean the column names by stripping whitespace
    df.columns = df.columns.str.strip().str.replace(' ', '_')
    
    # leads
    leads_df = df[
        df[RECORD_TYPE_ID_FIELD] == LEAD_SCHOLAR_RECORD_TYPE_ID
    ]
    
    leads_existing = get_existing_records(
        leads_df, 
        "Lead", 
        LEAD_SCHOLAR_RECORD_TYPE_ID,
        lead_column_mapper
    )
    
    lead_updates = leads_df.apply(
        lambda row : process_row (
            row, 
            leads_existing,
            lead_column_mapper
        ),
        axis=1,      
    ).dropna().tolist()
    
    # members
    member_df = df[
        df[RECORD_TYPE_ID_FIELD] == CPL_MEMBER_RECORD_TYPE_ID
    ]
    
    member_existing = get_existing_records(
        member_df, 
        "Account", 
        CPL_MEMBER_RECORD_TYPE_ID,
        member_column_mapper
    )
    
    member_updates = member_df.apply(
        lambda row : process_row (
            row, 
            member_existing,
            member_column_mapper
        ),
        axis=1,      
    ).dropna().tolist()
    
    print(f"Lead updates: {len(lead_updates)}")
    print(f"Member updates: {len(member_updates)}")

    lead_result = push_updates(
        lead_updates,
        "Lead",
    )

    member_result = push_updates(
        member_updates,
        "Account",
    )

    print("Updates complete.")

    
if __name__ == "__main__":
    main()
    
