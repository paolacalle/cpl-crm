#!/bin/bash

# extract first column, remove the header row, sort, and isolate unique IDs
schoolcard_ids=$(cut -d',' -f1 raw/cpl-collegecard-id.csv | tail -n +2 | sort | uniq)

# loop through each unique ID and perform the Salesforce query
DATA=("Scorecard,Id,Name")
for id in $schoolcard_ids; do
    res=$(sfdx force:data:soql:query \
        -q "SELECT Id, Name FROM Account WHERE College_Scorecard_ID__c = '$id'" \
        -r csv --target-org CPLProduction | tail -n +2 | tr -d '"') 
    DATA+=("${id},${res}")
done

# write the results to a CSV file
printf "%s\n" "${DATA[@]}" > clean/cpl-collegecard-id-mapped.csv