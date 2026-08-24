public with sharing class LeadConvertAction {
    private static final String CPL_SCHOLAR_LEAD_RECORD_TYPE = 'CPL_Scholar_Lead';

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;
    }

    @InvocableMethod(
        label='Convert CPL Lead'
        description='Converts a CPL Scholar lead into a member without creating an opportunity.'
    )
    public static void convertLeads(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> leadIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.leadId != null) {
                leadIds.add(req.leadId);
            }
        }
        if (leadIds.isEmpty()) {
            return;
        }

        prepareScholarLeadsForPersonAccountConversion(leadIds);

        String convertedStatus;
        for (LeadStatus status : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1]) {
            convertedStatus = status.MasterLabel;
        }
        if (String.isBlank(convertedStatus)) {
            throw new ConvertException('No converted Lead Status is configured. Mark one Lead Status value as converted before running this action.');
        }

        // Intake leads are owned by a queue, but converted records can only be owned
        // by a user. Assign the converted records to whoever is running the conversion.
        Id runningUserId = UserInfo.getUserId();

        // Duplicate rules otherwise block conversion (DUPLICATES_DETECTED) for users
        // who are not exempt from the rule. Allow the convert to save through the
        // detected match so any intake user can convert, not just exempt users.
        Database.DMLOptions dmlOptions = new Database.DMLOptions();
        dmlOptions.DuplicateRuleHeader.AllowSave = true;
        dmlOptions.DuplicateRuleHeader.RunAsCurrentUser = true;

        for (Request req : requests) {
            if (req == null || req.leadId == null) {
                continue;
            }

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(req.leadId);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(true);
            lc.setOwnerId(runningUserId);

            // convertLead's DMLOptions overload only accepts a single record, so
            // convert one at a time and surface a clean error on failure.
            Database.LeadConvertResult result = Database.convertLead(lc, dmlOptions);
            if (!result.isSuccess()) {
                Database.Error err = result.getErrors()[0];
                throw new ConvertException(
                    formatError(err.getMessage(), String.valueOf(err.getStatusCode()), err.getFields())
                );
            }
        }
    }

    @TestVisible
    private static void prepareScholarLeadsForPersonAccountConversion(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        List<Lead> leadsToClearCompany = new List<Lead>();
        for (Lead leadRecord : [
            SELECT Id, Company, RecordType.DeveloperName
            FROM Lead
            WHERE Id IN :leadIds
        ]) {
            if (
                leadRecord.RecordType != null &&
                leadRecord.RecordType.DeveloperName == CPL_SCHOLAR_LEAD_RECORD_TYPE &&
                !String.isBlank(leadRecord.Company)
            ) {
                leadsToClearCompany.add(new Lead(
                    Id = leadRecord.Id,
                    Company = null
                ));
            }
        }

        if (!leadsToClearCompany.isEmpty()) {
            update leadsToClearCompany;
        }
    }

    // Surfaces the failing status code and field name(s) so a restricted-picklist /
    // field-mapping failure points the admin straight at the offending field.
    @TestVisible
    private static String formatError(String message, String statusCode, List<String> fieldNames) {
        String fieldDetail = (fieldNames == null || fieldNames.isEmpty())
            ? ''
            : ' [fields: ' + String.join(fieldNames, ', ') + ']';
        return message + ' (' + statusCode + ')' + fieldDetail;
    }

    public class ConvertException extends Exception {}
}
