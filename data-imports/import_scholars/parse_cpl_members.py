import csv
from functools import lru_cache 
import pandas as pd

# raw : sf column 
column_mapper = {
    "Submission Date" : "Submission Date",
    "First Name" : "First Name",
    "Last Name" : "Last Name",
    "Primary Email" : "Email",
    "Sport" : "Primary Sport",
    "Commit to CPL mantra?": "Commits to CPL mantra",
    "Why CPL": "Why CPL",
    "College Year": "College Year"
}

sf_cpl_student_lifecycle_stage_column = "CPL Student Lifecycle"
sf_school_column = "Collegecard_ID"
sf_member_person_account_record_type = "012Vx000003FTsnIAG"
sf_lead_person_account_record_type = "012Kd00000163evIAA"

# cache the mapping of scorecard id to collegecard id
@lru_cache(maxsize=None)
def load_cpl_collegecard_id_mapping(file_path):
    mapping = {} # scorecard id to collegecard id mapping
    with open(file_path, mode='r') as csv_file:
        csv_reader = csv.DictReader(csv_file)
        for row in csv_reader:
            mapping[str(row["Scorecard"])] = (str(row["Id"]))
            
    print(f"Loaded {len(mapping)} mappings from {file_path}", mapping)
    return mapping


def map_cpl_lifescycle_stage(scholar):
    status = scholar.get("Student_Current_Status", "").lower()
    if "scholar alumni" in status:
        return "Scholar Alumni"
    
    elif "has recieved scholarship" in status:
        return "Scholar"
    
    elif "althele alumni" in status:
        return "Alumni"
    
    elif "we mentoring" in status:
        return "Athlete"
        
    elif "lead" in status:
        return "Lead"
    
    return "Unqualified"

def map_cpl_school_id_name(scholar):
    match = load_cpl_collegecard_id_mapping("clean/cpl-collegecard-id-mapped.csv").get(str(scholar[sf_school_column]))
    if match:
        return match
    return None

def add_cpl_member_record_type(scholar):
    if scholar.get("CPL Student Lifecycle") == "Lead":
        scholar["RecordTypeId"] = sf_lead_person_account_record_type
    else:
        scholar["RecordTypeId"] = sf_member_person_account_record_type
    return scholar

def clean_college_year(scholar):
    if scholar["Predicted_Current_College_Year"] in ["Freshman", "Sophomore", "Junior", "Senior", "Other"]:
        return scholar["Predicted_Current_College_Year"]
    
    if scholar["Predicted_Current_College_Year"] in ["Graduated"]:
        return "Graduate"
    
    return None

def main():
    # read the input CSV file
    input_file = "raw/cpl-interest-submissions.csv"
    output_file = "clean/cpl-members-cleaned.csv"

    df = pd.read_csv(input_file)

    # map the columns based on the column_mapper
    df = df.rename(columns=column_mapper)
    
    # clean the column names by stripping whitespace and replacing spaces with underscores
    df.columns = df.columns.str.strip().str.replace(' ', '_')
    
    print(f"Columns after renaming: {df.columns.tolist()}")

    # map the lifecycle stage and school id/name
    df[sf_cpl_student_lifecycle_stage_column] = df.apply(map_cpl_lifescycle_stage, axis=1)
    df["School_Id"] = df.apply(map_cpl_school_id_name, axis=1)
    
    print(df[["School_Id"]].head())
    # add the record type to each scholar
    df = df.apply(add_cpl_member_record_type, axis=1)
    
    # clean the college year column
    df["Predicted_Current_College_Year"] = df.apply(clean_college_year, axis=1)
    
    # write the cleaned data to a new CSV file
    df.to_csv(output_file, index=False)
    
if __name__ == "__main__":
    main()
