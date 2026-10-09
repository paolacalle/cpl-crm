import argparse
import csv
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_MEMBER_EXCEPTIONS = (
    BASE_DIR / "debug" / "cpl-member-resume-contentversion-exceptions.csv"
)
DEFAULT_OUTPUT = BASE_DIR / "clean" / "cpl-lead-resume-contentversion-import.csv"
DEFAULT_EXCEPTIONS = BASE_DIR / "debug" / "cpl-lead-resume-contentversion-exceptions.csv"
LEAD_SCHOLAR_RECORD_TYPE_ID = "012Kd00000163evIAA"


def normalize_name(value):
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def run_sf_query(query, target_org):
    result = subprocess.run(
        [
            "sf",
            "data",
            "query",
            "--target-org",
            target_org,
            "--json",
            "--query",
            query,
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "Salesforce query failed:\n"
            + result.stdout.strip()
            + "\n"
            + result.stderr.strip()
        )

    payload = json.loads(result.stdout)
    return payload.get("result", {}).get("records", [])


def load_cpl_scholar_leads(target_org):
    query = (
        "SELECT Id, Name, FirstName, LastName, Email, IsConverted "
        "FROM Lead "
        f"WHERE RecordTypeId = '{LEAD_SCHOLAR_RECORD_TYPE_ID}' "
        "AND IsConverted = false"
    )
    records = run_sf_query(query, target_org)
    return group_by_name(records)


def load_cpl_scholar_leads_from_json(path):
    with path.open(encoding="utf-8") as json_file:
        payload = json.load(json_file)

    records = payload.get("records") or payload.get("result", {}).get("records", [])
    return group_by_name(records)


def group_by_name(records):
    by_name = defaultdict(list)
    for record in records:
        if not record.get("IsConverted", False):
            by_name[normalize_name(record["Name"])].append(record)
    return by_name


def load_resume_candidates(member_exceptions_path):
    with member_exceptions_path.open(encoding="utf-8", newline="") as csv_file:
        reader = csv.DictReader(csv_file)
        for row in reader:
            yield {
                "resume_file": row["Resume_File"],
                "derived_name": row["Derived_Member_Name"],
                "version_data": row["VersionData"],
            }


def build_rows(candidates, leads_by_name):
    import_rows = []
    exception_rows = []
    match_counts = defaultdict(int)

    for candidate in candidates:
        matches = leads_by_name.get(normalize_name(candidate["derived_name"]), [])

        if len(matches) != 1:
            exception_rows.append(
                {
                    "Resume_File": candidate["resume_file"],
                    "Derived_Lead_Name": candidate["derived_name"],
                    "Issue": "no matching CPL Scholar Lead"
                    if not matches
                    else "multiple matching CPL Scholar Leads",
                    "Match_Count": len(matches),
                    "Matched_Lead_Ids": ";".join(record["Id"] for record in matches),
                    "VersionData": candidate["version_data"],
                }
            )
            continue

        lead = matches[0]
        match_counts[lead["Id"]] += 1
        title = Path(candidate["resume_file"]).stem
        import_rows.append(
            {
                "Title": title,
                "PathOnClient": candidate["resume_file"],
                "VersionData": candidate["version_data"],
                "FirstPublishLocationId": lead["Id"],
                "OwnerId": "",
                "Description": "Scholar resume imported from cleaned CPL resume folder",
                "Matched_Lead_Name": lead["Name"],
                "Matched_Lead_Email": lead.get("Email") or "",
                "Duplicate_File_Number_For_Lead": match_counts[lead["Id"]],
            }
        )

    return import_rows, exception_rows


def write_csv(path, rows, fieldnames):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(
        description="Build a ContentVersion CSV for importing resumes to CPL Scholar Leads."
    )
    parser.add_argument("--target-org", default="cpl-sandbox")
    parser.add_argument(
        "--leads-json",
        type=Path,
        help="Optional JSON output from sf data query for CPL Scholar Leads.",
    )
    parser.add_argument(
        "--member-exceptions",
        type=Path,
        default=DEFAULT_MEMBER_EXCEPTIONS,
        help="Member resume exception CSV to retry against Lead records.",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--exceptions", type=Path, default=DEFAULT_EXCEPTIONS)
    args = parser.parse_args()

    if args.leads_json:
        leads_by_name = load_cpl_scholar_leads_from_json(args.leads_json)
    else:
        leads_by_name = load_cpl_scholar_leads(args.target_org)

    import_rows, exception_rows = build_rows(
        load_resume_candidates(args.member_exceptions),
        leads_by_name,
    )

    write_csv(
        args.output,
        import_rows,
        [
            "Title",
            "PathOnClient",
            "VersionData",
            "FirstPublishLocationId",
            "OwnerId",
            "Description",
            "Matched_Lead_Name",
            "Matched_Lead_Email",
            "Duplicate_File_Number_For_Lead",
        ],
    )
    write_csv(
        args.exceptions,
        exception_rows,
        [
            "Resume_File",
            "Derived_Lead_Name",
            "Issue",
            "Match_Count",
            "Matched_Lead_Ids",
            "VersionData",
        ],
    )

    print(f"Wrote {len(import_rows)} ContentVersion rows to {args.output}")
    print(f"Wrote {len(exception_rows)} exception rows to {args.exceptions}")


if __name__ == "__main__":
    main()
