import json
import shlex
import subprocess
import tempfile
from pathlib import Path
import pandas as pd

lifecycle_value_mapper = {
    "Unqualified": "Inactive",
}

REST_API_VERSION = "v60.0"
CPL_MEMBER_RECORD_TYPE_ID = "012Vx000003FTsnIAG"
LEAD_SCHOLAR_RECORD_TYPE_ID = "012Kd00000163evIAA"
TARGET_ORG = "cpl-sandbox"  # Change this to your target Salesforce org alias

def set_target_org(org_alias):
    global TARGET_ORG
    TARGET_ORG = org_alias

def run_sf_command(args, return_errors=False, log_errors=True):
    result = subprocess.run(
        args,
        capture_output=True,
        text=True
    )

    stdout = result.stdout.strip()
    stderr = result.stderr.strip()

    try:
        parsed_stdout = json.loads(stdout) if stdout else None
    except json.JSONDecodeError:
        parsed_stdout = None

    if result.returncode != 0:
        if log_errors:
            print(f"Salesforce command failed with exit code {result.returncode}:")
            print(" ".join(shlex.quote(arg) for arg in args))
            if parsed_stdout is not None:
                print(json.dumps(compact_sf_error(parsed_stdout), indent=2))
            elif stdout:
                print(stdout)
            if stderr:
                print(stderr)
        if return_errors:
            return parsed_stdout
        return None

    if parsed_stdout is None:
        print("Salesforce command did not return valid JSON:")
        print(stdout)
        return None

    return parsed_stdout


def compact_sf_error(error):
    if isinstance(error, list):
        return error

    if not isinstance(error, dict):
        return error

    summary_keys = [
        "name",
        "message",
        "exitCode",
        "context",
        "data",
        "warnings",
        "code",
        "status",
        "commandName",
    ]

    return {
        key: error[key]
        for key in summary_keys
        if key in error
    }


def create_sf_record(sobject, values, return_errors=False, log_errors=True):
    clean_values = {
        field: value
        for field, value in values.items()
        if value is not None and not pd.isna(value)
    }

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".json",
        encoding="utf-8",
        delete=True,
    ) as body_file:
        json.dump(clean_values, body_file)
        body_file.flush()

        return run_sf_command(
            [
                "sf",
                "api",
                "request",
                "rest",
                f"/services/data/{REST_API_VERSION}/sobjects/{sobject}",
                "--body",
                f"@{body_file.name}",
                "--method",
                "POST",
                "--target-org",
                TARGET_ORG,
            ],
            return_errors=return_errors,
            log_errors=log_errors,
        )


def parse_bool(value):
    if isinstance(value, bool):
        return value

    normalized = str(value).strip().lower()

    if normalized in {"true", "yes", "yes!", "y", "1"}:
        return True

    if normalized in {"false", "no", "no!", "n", "0"}:
        return False

    raise ValueError(f"Cannot convert {value!r} to a Salesforce boolean")


def normalize_sf_value(field, value, boolean_fields):
    if field in boolean_fields:
        return parse_bool(value)

    if field == "CPL_Student_Lifecycle__c":
        return lifecycle_value_mapper.get(value, value)

    return value


def is_boolean_deserialize_error(result):
    if not isinstance(result, list):
        return False

    for error in result:
        message = error.get("message", "")

        if (
            error.get("errorCode") == "JSON_PARSER_ERROR"
            and "Cannot deserialize instance of boolean" in message
        ):
            return True

    return False


def escape_soql_string(value):
    return str(value).replace("\\", "\\\\").replace("'", "\\'")

def is_sandbox_org(TARGET_ORG):
    return TARGET_ORG.lower() in {"sandbox", "cpl-sandbox"}

def get_sobject_from_id(record_id):
    if not isinstance(record_id, str):
        return None

    if record_id.startswith("001"):
        return "Account"

    if record_id.startswith("00Q"):
        return "Lead"

    return None
