import argparse
import csv
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = BASE_DIR.parents[2]
DEFAULT_RESUME_DIR = WORKSPACE_ROOT / "scholar_resumes" / "all-scholar-resumes-cleaned"
DEFAULT_OUTPUT = BASE_DIR / "clean" / "cpl-member-resume-contentversion-import.csv"
DEFAULT_EXCEPTIONS = BASE_DIR / "debug" / "cpl-member-resume-contentversion-exceptions.csv"
CPL_MEMBER_RECORD_TYPE_ID = "012Vx000003FTsnIAG"


def normalize_name(value):
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def name_from_resume_file(path):
    stem = path.stem

    if stem.lower().startswith("resume - "):
        stem = stem[len("Resume - ") :]

    # Collision suffixes created by link-cpl-resume.py look like " - 9e3500ae".
    stem = re.sub(r"\s+-\s+[0-9a-f]{8}$", "", stem, flags=re.IGNORECASE)
    return " ".join(stem.split())


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


def load_cpl_member_accounts(target_org):
    query = (
        "SELECT Id, Name, FirstName, LastName, PersonEmail "
        "FROM Account "
        f"WHERE RecordTypeId = '{CPL_MEMBER_RECORD_TYPE_ID}'"
    )
    records = run_sf_query(query, target_org)

    by_name = defaultdict(list)
    for record in records:
        by_name[normalize_name(record["Name"])].append(record)

    return by_name


def load_cpl_member_accounts_from_json(path):
    with path.open(encoding="utf-8") as json_file:
        payload = json.load(json_file)

    records = payload.get("result", {}).get("records", [])

    by_name = defaultdict(list)
    for record in records:
        by_name[normalize_name(record["Name"])].append(record)

    return by_name


def build_rows(resume_dir, accounts_by_name):
    import_rows = []
    exception_rows = []
    match_counts = defaultdict(int)

    for path in sorted(resume_dir.iterdir(), key=lambda item: item.name.lower()):
        if not path.is_file() or path.name.startswith("."):
            continue

        member_name = name_from_resume_file(path)
        matches = accounts_by_name.get(normalize_name(member_name), [])

        if len(matches) != 1:
            exception_rows.append(
                {
                    "Resume_File": path.name,
                    "Derived_Member_Name": member_name,
                    "Issue": "no matching CPL Member Account"
                    if not matches
                    else "multiple matching CPL Member Accounts",
                    "Match_Count": len(matches),
                    "Matched_Account_Ids": ";".join(record["Id"] for record in matches),
                    "VersionData": str(path.resolve()),
                }
            )
            continue

        account = matches[0]
        match_counts[account["Id"]] += 1
        import_rows.append(
            {
                "Title": path.stem,
                "PathOnClient": path.name,
                "VersionData": str(path.resolve()),
                "FirstPublishLocationId": account["Id"],
                "OwnerId": "",
                "Description": "Scholar resume imported from cleaned CPL resume folder",
                "Matched_Account_Name": account["Name"],
                "Matched_Account_Email": account.get("PersonEmail") or "",
                "Duplicate_File_Number_For_Account": match_counts[account["Id"]],
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
        description="Build a ContentVersion CSV for importing scholar resumes."
    )
    parser.add_argument("--target-org", default="cpl-sandbox")
    parser.add_argument(
        "--accounts-json",
        type=Path,
        help="Optional JSON output from sf data query for CPL Member Accounts.",
    )
    parser.add_argument("--resume-dir", type=Path, default=DEFAULT_RESUME_DIR)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--exceptions", type=Path, default=DEFAULT_EXCEPTIONS)
    args = parser.parse_args()

    if args.accounts_json:
        accounts_by_name = load_cpl_member_accounts_from_json(args.accounts_json)
    else:
        accounts_by_name = load_cpl_member_accounts(args.target_org)
    import_rows, exception_rows = build_rows(args.resume_dir, accounts_by_name)

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
            "Matched_Account_Name",
            "Matched_Account_Email",
            "Duplicate_File_Number_For_Account",
        ],
    )
    write_csv(
        args.exceptions,
        exception_rows,
        [
            "Resume_File",
            "Derived_Member_Name",
            "Issue",
            "Match_Count",
            "Matched_Account_Ids",
            "VersionData",
        ],
    )

    print(f"Wrote {len(import_rows)} ContentVersion rows to {args.output}")
    print(f"Wrote {len(exception_rows)} exception rows to {args.exceptions}")


if __name__ == "__main__":
    main()
