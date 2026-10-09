#!/usr/bin/env python3
"""
Build a Salesforce-ready Account import CSV for U.S. colleges/universities
using the current School Account fields shown on the Salesforce page layout.

Source: U.S. Department of Education College Scorecard institution-level data.
Output: salesforce_school_import_schools.csv

This script imports schools as Account records. It does NOT require a custom
External ID field. The federal UNITID is written into your normal field:
"College Scorecard ID".

Usage:
  python build_salesforce_school_import_current_fields.py

Common options:
  python build_salesforce_school_import_current_fields.py \
      --record-type-id 012XXXXXXXXXXXXXXX \
      --default-sports-focus Soccer \
      --default-priority High \
      --default-importance High

If you only want 4-year / graduate schools:
  python build_salesforce_school_import_current_fields.py --bachelors-and-above-only
"""

import argparse
import csv
import io
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen


SOURCE_URLS = [
    "https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Institution_03232026.zip",
    "https://ed-public-download.scorecard.network/downloads/Most-Recent-Cohorts-Institution_05192025.zip",
]


OUTPUT_COLUMNS = [
    "Account Name",
    "Record Type",
    "RecordTypeId",
    "Institution Type",
    "Highest Degree Offered",
    "College Scorecard ID",
    "Parent Account",
    "Website",
    "Athletic Division / League",
    "Sports Focus",
    "Recruiting Priority",
    "Strategic Importance",
    "Primary Contact",
    "Location",
    "Billing City",
    "Billing State/Province",
    "Billing Zip/Postal Code",
    "Billing Country",
    "Billing Latitude",
    "Billing Longitude",
    "Description",
]


INSTITUTION_TYPE_MAP = {
    "1": "Public",
    "2": "Private nonprofit",
    "3": "Private for-profit",
    1: "Public",
    2: "Private nonprofit",
    3: "Private for-profit",
}


HIGHEST_DEGREE_MAP = {
    "0": "",
    "1": "Certificate",
    "2": "Associate",
    "3": "Bachelor’s",
    "4": "Master’s",
    0: "",
    1: "Certificate",
    2: "Associate",
    3: "Bachelor’s",
    4: "Master’s",
}

PREDOMINANT_DEGREE_MAP = {
    "0": "Not classified",
    "1": "Predominantly certificate-degree granting",
    "2": "Predominantly associate's-degree granting",
    "3": "Predominantly bachelor's-degree granting",
    "4": "Entirely graduate-degree granting",
    0: "Not classified",
    1: "Predominantly certificate-degree granting",
    2: "Predominantly associate's-degree granting",
    3: "Predominantly bachelor's-degree granting",
    4: "Entirely graduate-degree granting",
}


def download_zip() -> tuple[bytes, str]:
    last_error = None

    for url in SOURCE_URLS:
        try:
            req = Request(
                url,
                headers={"User-Agent": "Mozilla/5.0 Salesforce import builder"},
            )

            with urlopen(req, timeout=180) as response:
                return response.read(), url

        except Exception as exc:
            last_error = exc

    raise RuntimeError(f"Could not download College Scorecard ZIP. Last error: {last_error}")


def find_csv_in_zip(zip_bytes: bytes) -> tuple[str, bytes]:
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        csv_names = [
            name for name in zf.namelist()
            if name.lower().endswith(".csv")
        ]

        if not csv_names:
            raise RuntimeError("No CSV file found inside the downloaded ZIP.")

        preferred = [
            name for name in csv_names
            if "institution" in name.lower() or "cohorts" in name.lower()
        ]

        csv_name = (preferred or csv_names)[0]
        return csv_name, zf.read(csv_name)


def clean_text(value: object) -> str:
    return str(value or "").strip()


def clean_url(url: object) -> str:
    url = clean_text(url)

    if not url:
        return ""

    if url.lower().startswith(("http://", "https://")):
        return url

    return "https://" + url


def lookup(mapping: dict, value: object) -> str:
    value = clean_text(value)
    return mapping.get(value, value)


def build_location(row: dict) -> str:
    city = clean_text(row.get("CITY"))
    state = clean_text(row.get("STABBR"))
    zip_code = clean_text(row.get("ZIP"))

    city_state = ", ".join(x for x in [city, state] if x)

    if zip_code:
        return f"{city_state} {zip_code}".strip()

    return city_state


def build_description(row: dict, source_dataset: str, source_url: str) -> str:
    accreditor = clean_text(row.get("ACCREDAGENCY"))
    preddeg = lookup(PREDOMINANT_DEGREE_MAP, row.get("PREDDEG"))
    location = build_location(row)

    parts = []

    if location:
        parts.append(f"Location: {location}")

    if preddeg:
        parts.append(f"Predominant degree: {preddeg}")

    if accreditor:
        parts.append(f"Accreditor: {accreditor}")

    parts.append(f"Source: College Scorecard ({source_dataset})")
    parts.append(f"Source URL: {source_url}")

    return " | ".join(parts)


def should_keep_row(
    row: dict,
    include_non_operating: bool,
    bachelors_and_above_only: bool,
) -> bool:
    name = clean_text(row.get("INSTNM"))

    if not name:
        return False

    if not include_non_operating and "CURROPER" in row:
        curroper = clean_text(row.get("CURROPER"))

        if curroper and curroper != "1":
            return False

    if bachelors_and_above_only:
        preddeg = clean_text(row.get("PREDDEG"))

        if preddeg not in {"3", "4"}:
            return False

    return True


def main() -> int:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--output",
        default="salesforce_school_import_schools.csv",
    )

    parser.add_argument(
        "--record-type",
        default="School",
        help="Text value for the Record Type mapping column",
    )

    parser.add_argument(
        "--record-type-id",
        default="",
        help="Optional Salesforce Account RecordTypeId for the School record type",
    )

    parser.add_argument(
        "--default-sports-focus",
        default="Soccer",
        help="Required Salesforce Sports Focus value. Default: Soccer",
    )

    parser.add_argument(
        "--default-priority",
        default="",
        help="Optional default Recruiting Priority, e.g. High/Medium/Low",
    )

    parser.add_argument(
        "--default-importance",
        default="",
        help="Optional default Strategic Importance, e.g. High/Medium/Low",
    )

    parser.add_argument(
        "--include-non-operating",
        action="store_true",
        help="Include rows where CURROPER is not 1",
    )

    parser.add_argument(
        "--bachelors-and-above-only",
        action="store_true",
        help="Only keep PREDDEG 3 or 4",
    )

    args = parser.parse_args()

    if not clean_text(args.default_sports_focus):
        raise ValueError(
            "Sports Focus is required. Pass --default-sports-focus Soccer "
            "or another valid Salesforce picklist value."
        )

    zip_bytes, source_url = download_zip()
    source_dataset, csv_bytes = find_csv_in_zip(zip_bytes)

    text = csv_bytes.decode("utf-8-sig", errors="replace")
    reader = csv.DictReader(io.StringIO(text))

    output_path = Path(args.output)

    created_count = 0
    skipped_count = 0

    with output_path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=OUTPUT_COLUMNS,
            extrasaction="ignore",
        )

        writer.writeheader()

        for row in reader:
            if not should_keep_row(
                row,
                args.include_non_operating,
                args.bachelors_and_above_only,
            ):
                skipped_count += 1
                continue

            writer.writerow({
                "Account Name": clean_text(row.get("INSTNM")),
                "Record Type": args.record_type,
                "RecordTypeId": args.record_type_id,
                "Institution Type": lookup(INSTITUTION_TYPE_MAP, row.get("CONTROL")),
                "Highest Degree Offered": lookup(HIGHEST_DEGREE_MAP, row.get("HIGHDEG")),
                "College Scorecard ID": clean_text(row.get("UNITID")),
                "Parent Account": "",
                "Website": clean_url(row.get("INSTURL")),
                "Athletic Division / League": "",
                "Sports Focus": clean_text(args.default_sports_focus),
                "Recruiting Priority": clean_text(args.default_priority),
                "Strategic Importance": clean_text(args.default_importance),
                "Primary Contact": "",
                "Location": build_location(row),
                "Billing City": clean_text(row.get("CITY")),
                "Billing State/Province": clean_text(row.get("STABBR")),
                "Billing Zip/Postal Code": clean_text(row.get("ZIP")),
                "Billing Country": "United States",
                "Billing Latitude": clean_text(row.get("LATITUDE")),
                "Billing Longitude": clean_text(row.get("LONGITUDE")),
                "Description": build_description(row, source_dataset, source_url),
            })

            created_count += 1

    print(f"Created {output_path} with {created_count:,} school Account rows.")
    print(f"Skipped {skipped_count:,} rows.")
    print("Map these columns to your School Account fields in Salesforce Import Wizard/Data Loader.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())