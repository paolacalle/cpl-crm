public with sharing class ScholarApplicationStageBackfill implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([SELECT Id FROM Prospect_Scholar_Application__c
            WHERE Application_Stage__c = null OR Application_Decision__c = null]);
    }
    public void execute(Database.BatchableContext context, List<SObject> scope) {
        List<Prospect_Scholar_Application__c> updates = new List<Prospect_Scholar_Application__c>();
        for (SObject app : scope) updates.add(new Prospect_Scholar_Application__c(Id = (Id)app.get('Id')));
        // Normal update invokes synchronization; legacy outcomes are not changed.
        // Fail the batch scope on validation errors so Apex Jobs exposes migration failures.
        update updates;
    }
    public void finish(Database.BatchableContext context) {}
}
