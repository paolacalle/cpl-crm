#!/bin/bash
set -euo pipefail

ENV="${1:-}"
BASE="force-app/main/default"

DIRS=(
    "${BASE}/classes"
    "${BASE}/actions"
    # "${BASE}/email"
    # "${BASE}/flexipages"
    # "${BASE}/labels"
    "${BASE}/flows"
    # "${BASE}/flowDefinitions"
    # "${BASE}/flowtests"
    # "${BASE}/objects"
    # "${BASE}/layouts"
    "${BASE}/lwc"
    # "${BASE}/pages"
    # "${BASE}/triggers"
    # "${BASE}/tabs"
    # "${BASE}/quickActions"
)

if [[ "$ENV" == "dev" ]]; then
    BRANCH="sandbox"
    ALIAS_ORG="cpl-sandbox"
elif [[ "$ENV" == "prod" ]]; then
    BRANCH="main"
    ALIAS_ORG="CPLProduction"
else
    echo "ENV must be dev or prod"
    exit 1
fi

git checkout "$BRANCH"
git pull origin "$BRANCH"

echo "Starting Salesforce deployment to target org: $ALIAS_ORG..."
SOURCE_ARGS=()
for DIR in "${DIRS[@]}"; do
    if [[ -d "$DIR" ]]; then
        echo "Including: $DIR"
        SOURCE_ARGS+=(--source-dir "$DIR")
    fi
done

if [[ ${#SOURCE_ARGS[@]} -eq 0 ]]; then
    echo "No Salesforce source directories found."
    exit 0
fi

sf project deploy start \
    --target-org "$ALIAS_ORG" \
    "${SOURCE_ARGS[@]}"
