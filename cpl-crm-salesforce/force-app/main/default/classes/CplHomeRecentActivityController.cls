public with sharing class CplHomeRecentActivityController {
    private static final Integer RECENT_LIMIT = 8;

    @AuraEnabled(cacheable=true)
    public static List<ActivityItem> getActivity() {
        List<ActivityItem> items = new List<ActivityItem>();

        Id leadRtId;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Lead' AND DeveloperName = 'CPL_Scholar_Lead' LIMIT 1
        ]) {
            leadRtId = rt.Id;
        }

        if (leadRtId != null) {
            for (Lead l : [
                SELECT Id, Name, Status, IsConverted, CreatedDate
                FROM Lead
                WHERE RecordTypeId = :leadRtId
                ORDER BY CreatedDate DESC
                LIMIT :RECENT_LIMIT
            ]) {
                ActivityItem item = new ActivityItem();
                item.id = l.Id;
                item.title = l.Name;
                item.subtitle = 'CPL Scholar Lead';
                item.status = l.Status;
                item.objectApiName = 'Lead';
                item.iconName = 'standard:lead';
                item.activityType = l.IsConverted ? 'Lead converted' : 'New lead';
                item.timestamp = l.CreatedDate;
                items.add(item);
            }
        }

        for (Prospect_Scholar_Application__c app : [
            SELECT Id, Name, Application_Status__c, Applicant_Account__r.Name, CreatedDate
            FROM Prospect_Scholar_Application__c
            ORDER BY CreatedDate DESC
            LIMIT :RECENT_LIMIT
        ]) {
            ActivityItem item = new ActivityItem();
            item.id = app.Id;
            item.title = app.Name;
            item.subtitle = app.Applicant_Account__r != null ? app.Applicant_Account__r.Name : 'Scholar Application';
            item.status = app.Application_Status__c;
            item.objectApiName = 'Prospect_Scholar_Application__c';
            item.iconName = 'standard:scholar';
            item.activityType = 'Scholar application';
            item.timestamp = app.CreatedDate;
            items.add(item);
        }

        items.sort(new ActivityComparator());
        if (items.size() > RECENT_LIMIT) {
            List<ActivityItem> trimmed = new List<ActivityItem>();
            for (Integer i = 0; i < RECENT_LIMIT; i++) {
                trimmed.add(items[i]);
            }
            items = trimmed;
        }
        return items;
    }

    public class ActivityItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String status;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String iconName;
        @AuraEnabled public String activityType;
        @AuraEnabled public Datetime timestamp;
    }

    public class ActivityComparator implements System.Comparator<ActivityItem> {
        public Integer compare(ActivityItem a, ActivityItem b) {
            if (a.timestamp == null && b.timestamp == null) return 0;
            if (a.timestamp == null) return 1;
            if (b.timestamp == null) return -1;
            if (a.timestamp > b.timestamp) return -1;
            if (a.timestamp < b.timestamp) return 1;
            return 0;
        }
    }
}