import json
from pathlib import Path
from sf_command import (
    run_sf_command,
    normalize_sf_value,
    is_sandbox_org,
    create_sf_record, 
    escape_soql_string,
    is_boolean_deserialize_error,
    get_sobject_from_id,
    set_target_org,
    CPL_MEMBER_RECORD_TYPE_ID,
    LEAD_SCHOLAR_RECORD_TYPE_ID,
    TARGET_ORG,
)
import pandas as pd

member_column_mapper = {
    "First_Name": "FirstName",
    "Last_Name": "LastName",
    "Email": "PersonEmail",
    "Primary_Sport": "Primary_Sport__pc",
    "Commits_to_CPL_mantra": "Commits_to_CPL_mantra__pc",
    "Tell_us_a_little_about_yourself!": "Why_CPL__pc",
    "Predicted_Current_College_Year": "College_Year__pc",
    "CPL Student Lifecycle": "CPL_Student_Lifecycle__c",
    "School_Id": "School__pc",
    "Submission_Date": "Submission_Date__pc",
}

lead_column_mapper = {
    "First_Name": "FirstName",
    "Last_Name": "LastName",
    "Email": "Email",
    "Primary_Sport": "Primary_Sport__c",
    "Commits_to_CPL_mantra": "Commits_to_CPL_mantra__c",
    "Tell_us_a_little_about_yourself!": "Why_CPL_Scholar__c",
    "Predicted_Current_College_Year": "College_Year__c",
    "School_Id": "School__c",
    "University_or_College_Enrolled_At": "School_Name_From_Form__c",
    "Status": "Status",
    "Submission_Date": "Submission_Date__c",
}
    
boolean_fields = {
    "Commits_to_CPL_mantra__pc",
    "Commits_to_CPL_mantra__c",
}

sport_fields = {
    "Primary_Sport__pc",
    "Primary_Sport__c",
}

set_target_org("CPLProduction")  # Change this to your target Salesforce org alias
TARGET_ORG = "CPLProduction"
BASE_DIR = Path(__file__).resolve().parent

def get_account_summary(account_id):
    if not account_id:
        return None

    query = (
        "SELECT Id, Name, IsPersonAccount, PersonContactId, PersonEmail, RecordTypeId "
        f"FROM Account WHERE Id = '{account_id}' "
        "LIMIT 1"
    )

    result = run_sf_command(
        [
            "sf",
            "data",
            "query",
            "--query",
            query,
            "--json",
            "--target-org",
            TARGET_ORG,
        ]
    )

    if not result:
        return None

    records = result.get("result", {}).get("records", [])

    if not records:
        return None

    return records[0]

def get_lead_summary(lead_id):
    if not lead_id:
        return None

    query = (
        "SELECT Id, Name, Email, RecordTypeId, Status "
        f"FROM Lead WHERE Id = '{lead_id}' "
        "LIMIT 1"
    )

    result = run_sf_command(
        [
            "sf",
            "data",
            "query",
            "--query",
            query,
            "--json",
            "--target-org",
            TARGET_ORG,
        ]
    )

    if not result:
        return None

    records = result.get("result", {}).get("records", [])

    if not records:
        return None

    return records[0]

def get_duplicate_record(result, preferred_sobject):
    if not isinstance(result, list):
        return None

    fallback_duplicate = None

    for error in result:
        if error.get("errorCode") != "DUPLICATES_DETECTED":
            continue

        # if the error is a duplicate detection, check for the duplicate account ID in the match results
        # the duplicate err means that the record was not created, but we can still get the existing record ID
        # from the match results
        duplicate_result = error.get("duplicateResult") or {}

        for match_result in duplicate_result.get("matchResults", []):
            entity_type = match_result.get("entityType")

            if entity_type not in {"Account", "Lead"}:
                continue

            for match_record in match_result.get("matchRecords", []):
                record = match_record.get("record") or {}
                record_id = record.get("Id")

                if not record_id:
                    continue

                duplicate = {
                    "id": record_id,
                    "sobject": entity_type,
                }

                if entity_type == preferred_sobject:
                    return duplicate

                if fallback_duplicate is None:
                    fallback_duplicate = duplicate

    return fallback_duplicate

def validate_duplicate_record(record_id, sobject, email):
    if sobject == "Account":
        account = get_account_summary(record_id)

        if not account:
            print(
                f"Duplicate Account {record_id} for {email} "
                "was not found or is not visible"
            )
            return False

        if not account.get("IsPersonAccount") or not account.get("PersonContactId"):
            print(
                f"Duplicate Account {record_id} for {email} "
                "is not a usable Person Account"
            )
            return False

        return True

    if sobject == "Lead":
        lead = get_lead_summary(record_id)

        if not lead:
            print(
                f"Duplicate Lead {record_id} for {email} "
                "was not found or is not visible"
            )
            return False

        return True

    return False

def create_cpl_member_record(scholar):
    """
    Create a CPL Member Person Account and return its Account Id.
    """
    
    lifecycle = scholar.get("CPL Student Lifecycle")
    is_lead = is_lead_scholar(scholar)

    sobject = "Lead" if is_lead else "Account"
    record_type_id = (
        LEAD_SCHOLAR_RECORD_TYPE_ID if is_lead else CPL_MEMBER_RECORD_TYPE_ID
    )

    values = {
        "RecordTypeId": record_type_id,
    }
    
    column_mapper = lead_column_mapper if is_lead else member_column_mapper

    for csv_column, sf_field in column_mapper.items():
        
        if csv_column == "Status":
            value = "Unqualified" if lifecycle == "Unqualified" else "Contacted"
        else:
            value = scholar.get(csv_column)

        if sf_field is None or pd.isna(value):
            continue

        values[sf_field] = normalize_sf_value(sf_field, value, boolean_fields)

    if is_lead:
        school_name = scholar.get("University_or_College_Enrolled_At")
        values["Company"] = (
            school_name
            if not pd.isna(school_name) and str(school_name).strip()
            else "Unknown"
        )
        
    # Sandbox data may not have matching school Account IDs.
    if is_sandbox_org(TARGET_ORG):
        values.pop("School__pc", None)
        values.pop("School__c", None)

    result = create_sf_record(
        sobject,
        values,
        return_errors=True,
        log_errors=False,
    )

    if is_boolean_deserialize_error(result):
        retry_values = {
            field: value
            for field, value in values.items()
            if field not in sport_fields
        }

        if retry_values != values:
            print(
                f"Retrying {sobject} for {scholar.get('Email')} "
                "without sport because the target field is boolean"
            )
            result = create_sf_record(
                sobject,
                retry_values,
                return_errors=True,
                log_errors=False,
            )

    if not result:
        return None

    duplicate_record = get_duplicate_record(result, sobject)

    if duplicate_record:
        duplicate_record_id = duplicate_record["id"]
        duplicate_sobject = duplicate_record["sobject"]

        if not validate_duplicate_record(
            duplicate_record_id,
            duplicate_sobject,
            scholar.get("Email"),
        ):
            return None

        print(
            f"Using existing duplicate {duplicate_sobject} "
            f"{duplicate_record_id} for {scholar.get('Email')}"
        )
        return duplicate_record_id

    try:
        return result["id"]
    except (KeyError, TypeError):
        print(f"Failed to create scholar: {scholar.get('Email')}")
        print(json.dumps(result, indent=2))
        return None

def is_lead_scholar(scholar):
    return scholar.get("CPL Student Lifecycle") in {"Lead", "Unqualified"}

def get_person_contact_id(account_id):
    """
    Retrieve the PersonContactId created behind the Person Account.
    """
    account = get_account_summary(account_id)

    if not account:
        print(f"Account {account_id} was not found or is not visible in {TARGET_ORG}")
        return None

    if not account.get("IsPersonAccount"):
        print(f"Account {account_id} is not a Person Account")
        return None

    return account.get("PersonContactId")

def find_or_create_topic(name):
    escaped_name = escape_soql_string(name)
    query = (
        "SELECT Id "
        f"FROM Topic__c WHERE Name = '{escaped_name}' "
        "LIMIT 1"
    )

    existing_topic = run_sf_command(
        [
            "sf",
            "data",
            "query",
            "--query",
            query,
            "--json",
            "--target-org",
            TARGET_ORG,
        ]
    )

    if existing_topic:
        records = existing_topic.get("result", {}).get("records", [])

        if records:
            return records[0]["Id"]

    result = create_sf_record(
        "Topic__c",
        {
            "Name": name,
            "Active__c": True,
        },
    )

    if not result:
        return None

    return result.get("id")

def add_structured_note(scholar, lookup_field, lookup_id):
    note = scholar.get("Notes_On_Scholar")

    if pd.isna(note) or not str(note).strip():
        return

    if not lookup_id:
        print(f"Could not determine interaction target for {scholar.get('Email')}")
        return

    interaction_date = pd.to_datetime(
        scholar["Submission_Date"]
    ).strftime("%Y-%m-%d")

    values = {
        "Title__c": "Initial Note",
        "Note__c": str(note),
        lookup_field: lookup_id,
        "Interaction_Date__c": interaction_date,
    }
    
    # verify the user does not have a Initial Note interaction already
    query = (
        "SELECT Id "
        "FROM Interaction__c "
        f"WHERE {lookup_field} = '{lookup_id}' "
        "AND Title__c = 'Initial Note' "
        "LIMIT 1"
    )

    existing_interaction = run_sf_command(
        [
            "sf",
            "data",
            "query",
            "--query",
            query,
            "--json",
            "--target-org",
            TARGET_ORG,
        ]
    )

    existing_records = []

    if existing_interaction:
        existing_records = existing_interaction.get("result", {}).get("records", [])

    if existing_records:
        interaction_id = existing_records[0]["Id"]
    else:
        created_interaction = create_sf_record("Interaction__c", values)

        if not created_interaction:
            print(
                f"Failed to create interaction for "
                f"{scholar.get('Email')}"
            )
            return

        interaction_id = created_interaction.get("id")

    if not interaction_id:
        print(f"Could not determine interaction Id for {scholar.get('Email')}")
        return

    topic_id = find_or_create_topic("Summary of Scholar (Claude + Lisa)")

    if not topic_id:
        print(f"Failed to find or create interaction topic for {scholar.get('Email')}")
        return
    
    # link the interaction to the topic if not already linked
    query = (
        "SELECT Id "
        "FROM InteractionTopic__c "
        f"WHERE Interaction__c = '{interaction_id}' "
        f"AND Topic__c = '{topic_id}' "
        "LIMIT 1"
    )   
    
    result = run_sf_command(
        [
            "sf",
            "data",
            "query",
            "--query",
            query,
            "--json",
            "--target-org",
            TARGET_ORG,
        ]
    )
    
    if result and result.get("result", {}).get("records"):
        return  # already linked

    result = create_sf_record(
        "InteractionTopic__c",
        {
            "Interaction__c": interaction_id,
            "Topic__c": topic_id,
        },
    )

    if not result:
        print(f"Failed to link interaction topic for {scholar.get('Email')}")

def add_structured_note_to_scholar(scholar):
    account_id = scholar["cpl_account_id"]
    contact_id = get_person_contact_id(account_id)

    if not contact_id:
        print(f"Could not find PersonContactId for {account_id}")
        return

    add_structured_note(scholar, "Contact__c", contact_id)

def add_structured_note_to_scholar_or_lead(scholar):
    sobject = scholar.get("cpl_sobject")
    record_id = scholar.get("cpl_account_id")

    if sobject == "Account":
        add_structured_note_to_scholar(scholar)
        return

    if sobject == "Lead":
        add_structured_note(scholar, "Lead__c", record_id)
        return

    print(
        f"Could not determine whether {record_id} is an Account or Lead "
        f"for {scholar.get('Email')}"
    )

def main():
    # input_file = BASE_DIR / "clean/cpl-members-cleaned.csv"
    input_file = BASE_DIR / "debug/failed_scholars.csv"

    df = pd.read_csv(input_file)
    df["requested_cpl_sobject"] = df.apply(
        lambda scholar: "Lead" if is_lead_scholar(scholar) else "Account",
        axis=1,
    )

    # Create CPL Person Accounts and Leads
    df["cpl_account_id"] = df.apply(
        create_cpl_member_record,
        axis=1,
    )
    df["cpl_sobject"] = df["cpl_account_id"].apply(get_sobject_from_id)

    # Save failed scholars
    failed_scholars = df[df["cpl_account_id"].isnull()]
    failed_scholars.to_csv(
        BASE_DIR / "debug/failed_scholars.csv",
        index=False,
    )

    # Only continue with successfully-created scholars
    df = df[df["cpl_account_id"].notnull()].copy()

    # Add structured notes
    df.apply(
        add_structured_note_to_scholar_or_lead,
        axis=1,
    )

    # Save successful mappings for reference
    df.to_csv(
        BASE_DIR / "debug/created_cpl_members.csv",
        index=False,
    )


if __name__ == "__main__":
    main()
