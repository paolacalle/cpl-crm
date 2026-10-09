# Scholar Resume Imports

Build CSVs for uploading cleaned resume files to Salesforce `ContentVersion`.

## 1. Clean Resume Filenames

`link-cpl-resume.py` uses the old Wix interest form CSV as the source of truth.
It reads each applicant's resume URL, finds the matching downloaded Wix file,
and copies it into `all-scholar-resumes-cleaned/` with a consistent name:

```text
Resume - First Last.pdf
```

Run it from this folder:

```bash
cd /Users/paolacalle/Desktop/CPL/cpl-crm/data-imports/import_scholar_resumes
python3 link-cpl-resume.py
```

Expected input folders/files:

```text
raw-data/CPL-old-interest-form.csv
all-scholar-resumes/
```

Output:

```text
all-scholar-resumes-cleaned/
```

## 2. Build CPL Member Resume Import

From the repo root:

```bash
cd /Users/paolacalle/Desktop/CPL

sf data query \
  --target-org cpl-sandbox \
  --result-format json \
  --output-file cpl-crm/data-imports/import_scholar_resumes/debug/cpl-member-accounts-query.json \
  --query "SELECT Id, Name, FirstName, LastName, PersonEmail FROM Account WHERE RecordTypeId = '012Vx000003FTsnIAG'"

python3 cpl-crm/data-imports/import_scholar_resumes/build_resume_contentversion_import.py \
  --accounts-json cpl-crm/data-imports/import_scholar_resumes/debug/cpl-member-accounts-query.json
```

Output:

```text
clean/cpl-member-resume-contentversion-import.csv
debug/cpl-member-resume-contentversion-exceptions.csv
```

## 3. Build Lead Resume Import

This retries the member exceptions against open CPL Scholar Leads.

```bash
sf data query \
  --target-org cpl-sandbox \
  --result-format json \
  --output-file cpl-crm/data-imports/import_scholar_resumes/debug/cpl-scholar-leads-query.json \
  --query "SELECT Id, Name, FirstName, LastName, Email, IsConverted FROM Lead WHERE RecordTypeId = '012Kd00000163evIAA' AND IsConverted = false"

python3 cpl-crm/data-imports/import_scholar_resumes/build_lead_resume_contentversion_import.py \
  --leads-json cpl-crm/data-imports/import_scholar_resumes/debug/cpl-scholar-leads-query.json
```

Output:

```text
clean/cpl-lead-resume-contentversion-import.csv
debug/cpl-lead-resume-contentversion-exceptions.csv
```

## 4. Import With Data Loader

Use **Insert** on `ContentVersion`.

Map:

```text
Title -> Title
PathOnClient -> PathOnClient
VersionData -> VersionData
FirstPublishLocationId -> FirstPublishLocationId
Description -> Description
```

Leave helper columns unmapped.

Use the same target org for the queries and the Data Loader import. For production, replace `cpl-sandbox` with `CPLProduction`.
