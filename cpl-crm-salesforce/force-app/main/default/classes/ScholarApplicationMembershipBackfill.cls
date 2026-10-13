public without sharing class ScholarApplicationMembershipBackfill implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id FROM Account
            WHERE IsPersonAccount = true OR Has_Active_Scholarship_Application__c = true
        ]);
    }
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Set<Id> memberIds = new Set<Id>();
        for (SObject member : scope) memberIds.add((Id) member.get('Id'));
        ScholarApplicationMembership.refresh(memberIds);
    }
    public void finish(Database.BatchableContext context) {}
}
