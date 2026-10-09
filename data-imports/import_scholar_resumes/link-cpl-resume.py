
import csv
import os
import shutil
import urllib.parse
from pathlib import Path

old_form_path = "raw-data/CPL-old-interest-form.csv"
all_resume_url_dir = Path("all-scholar-resumes/")
output_dir = Path("all-scholar-resumes-cleaned/")

output_dir.mkdir(parents=True, exist_ok=True)

url_not_found = 0
url_found = 0
no_url = 0
copied = 0

with open(old_form_path, "r", encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)

    for row in reader:
        resume_url = (row.get("Upload Your Resumé") or "").strip()
        applicant_name = (row.get("Name") or "").strip()

        if not resume_url:
            print(f"No resume URL found for {applicant_name}")
            no_url += 1
            continue

        url_found += 1

        # extract original filename from Wix URL
        decoded_url = urllib.parse.unquote(resume_url)
        file_name = decoded_url.split("/")[-1].split("?")[0].split("#")[0]

        source_path = all_resume_url_dir / file_name

        if not source_path.is_file():
            print(f"File does not exist: {file_name}")
            url_not_found += 1
            continue

        print(f"File exists: {file_name}")

        # normalize applicant name
        name_clean = " ".join(
            word.capitalize()
            for word in applicant_name.split()
        )

        # remove characters invalid in filenames
        name_clean = "".join(
            char for char in name_clean
            if char not in r'\/:*?"<>|'
        )

        # preserve original file extension
        extension = source_path.suffix.lower() or ".pdf"

        clean_file_name = f"Resume - {name_clean}{extension}"
        destination_path = output_dir / clean_file_name

        # prevent overwriting another applicant's résumé
        if destination_path.exists():
            applicant_id = (row.get("ID") or "").strip()

            if applicant_id:
                clean_file_name = (
                    f"Resume - {name_clean} - "
                    f"{applicant_id[:8]}{extension}"
                )
                destination_path = output_dir / clean_file_name

            # handle any remaining filename collisions
            counter = 2
            while destination_path.exists():
                clean_file_name = (
                    f"Resume - {name_clean} - "
                    f"{applicant_id[:8] or 'duplicate'} - "
                    f"{counter}{extension}"
                )
                destination_path = output_dir / clean_file_name
                counter += 1

        # Copy file without changing original
        shutil.copy2(source_path, destination_path)
        copied += 1

        print(f"Copied: {clean_file_name}")

print("\n========== SUMMARY ==========")
print(f"URLs found: {url_found}")
print(f"URLs not found: {url_not_found}")
print(f"Rows with no URL: {no_url}")
print(f"Successfully copied: {copied}")
