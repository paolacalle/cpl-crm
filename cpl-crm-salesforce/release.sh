#!/bin/bash
set -euo pipefail

ENV="${1:-}"

if [[ "$ENV" == "dev" ]]; then 
    BRANCH='sandbox'
    ALIAS_ORG='cpl-sandbox'
elif [[ "$ENV" == "prod" ]]; then
    BRANCH='main'
    ALIAS_ORG='CPLProduction'
else
    echo 'ENV must be dev / prod'
    exit 1
fi

git checkout "$BRANCH"
git pull origin "$BRANCH"

echo "Files updated in this pull: " 
MERGE_SHA=$(git rev-list --min-parents=2 --max-count=1 HEAD)
FILES=$(git diff --name-status "${MERGE_SHA}^1" "$MERGE_SHA")
echo "$FILES"

echo ""
read -r -p "Enter files to remove (separated by spaces, or leave blank to skip): " RMV_FILES

if [[ -n "${RMV_FILES}" ]]; then 
    echo "Removing requested files ..."

    for FILE in $RMV_FILES; do 
        if [[  -f "$FILE"  ]]; then 
            FILES=$(echo "$FILES" | grep -v "$FILE" || true)
        else 
            echo "Warning: File '$FILE' does not exist. Skipping."
        fi 
    done
else 
    echo "No files specified for removal. Done."
fi 

echo ""
echo "Updated file list:"
echo "$FILES"

SF_FILES=$(echo "$FILES" \
    | awk '$1 != "D" {print $NF}' \
    | sed 's#^cpl-crm-salesforce/##' \
    | tr '\n' ' ' | xargs)

if [[ -n "$SF_FILES" ]]; then
    echo "Starting Salesforce Deployment to target org: $ALIAS_ORG..."
    sf project deploy start --target-org "$ALIAS_ORG" --source-dir $SF_FILES
else
    echo "No remaining files to deploy. Exiting."
fi