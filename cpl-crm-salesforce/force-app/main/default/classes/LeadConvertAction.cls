public with sharing class LeadConvertAction {
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

        String convertedStatus;
        for (LeadStatus status : [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1]) {
            convertedStatus = status.MasterLabel;
        }

        // Intake leads are owned by a queue, but converted records can only be owned
        // by a user. Assign the converted records to whoever is running the conversion.
        Id runningUserId = UserInfo.getUserId();

        List<Database.LeadConvert> converts = new List<Database.LeadConvert>();
        for (Request req : requests) {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(req.leadId);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(true);
            lc.setOwnerId(runningUserId);
            converts.add(lc);
        }

        Database.convertLead(converts, true);
    }
}
