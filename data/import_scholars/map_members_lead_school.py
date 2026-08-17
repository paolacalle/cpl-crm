import json
import shlex
import subprocess
import tempfile
from pathlib import Path
import pandas as pd

fields_to_map = {
    "Submission_Date": "Submission_Date",
    "School_Id" : "School"
}

CPL_MEMBER_RECORD_TYPE_ID = "012Vx000003FTsnIAG"
LEAD_SCHOLAR_RECORD_TYPE_ID = "012Kd00000163evIAA"
TARGET_ORG = "CPLProduction" 
REST_API_VERSION = "v60.0"


