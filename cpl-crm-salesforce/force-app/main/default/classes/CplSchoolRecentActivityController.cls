public with sharing class CplSchoolRecentActivityController {
    private static final Integer RECENT_LIMIT = 5;

    @AuraEnabled(cacheable=true)
    public static SchoolActivity getActivity(Id schoolId) {
        SchoolActivity activity = new SchoolActivity();
        activity.recentLeads = new List<LeadRow>();
        activity.recentApps = new List<AppRow>();

        if (schoolId == null) {
            return activity;
        }

        for (Lead l : [
            SELECT Id, Name, Status, CreatedDate
            FROM Lead
            WHERE School__c = :schoolId
            ORDER BY CreatedDate DESC
            LIMIT :RECENT_LIMIT
        ]) {
            LeadRow r = new LeadRow();
            r.id = l.Id;
            r.name = l.Name;
            r.status = l.Status;
            r.createdDate = l.CreatedDate;
            activity.recentLeads.add(r);
        }

        Set<Id> applicantIds = new Set<Id>();
        for (Account a : [
            SELECT Id FROM Account
            WHERE School__pc = :schoolId AND IsPersonAccount = TRUE
        ]) {
            applicantIds.add(a.Id);
        }

        if (!applicantIds.isEmpty()) {
            for (Prospect_Scholar_Application__c app : [
                SELECT Id, Name, Applicant_Account__r.Name, Application_Status__c, CreatedDate
                FROM Prospect_Scholar_Application__c
                WHERE Applicant_Account__c IN :applicantIds
                ORDER BY CreatedDate DESC
                LIMIT :RECENT_LIMIT
            ]) {
                AppRow r = new AppRow();
                r.id = app.Id;
                r.name = app.Name;
                r.applicantName = app.Applicant_Account__r != null ? app.Applicant_Account__r.Name : '';
                r.status = app.Application_Status__c;
                r.createdDate = app.CreatedDate;
                activity.recentApps.add(r);
            }
        }

        return activity;
    }

    public class SchoolActivity {
        @AuraEnabled public List<LeadRow> recentLeads;
        @AuraEnabled public List<AppRow> recentApps;
    }

    public class LeadRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
    }

    public class AppRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
    }
}
