public with sharing class EmailActivityHealBatch implements Database.Batchable<SObject>, Schedulable {
    // Nightly safety net + one-time backfill. Re-scans EmailMessages and heals any
    // whose participant addresses match a scholar but that are not yet on the
    // timeline. EmailActivityHealer is idempotent (keyed on Task.Source_Email_Message__c),
    // so re-processing already-healed emails is a no-op. Catches the races the
    // creation-time Flow can miss: an email that lands seconds after the account is
    // created, or a PersonEmail set/changed after the fact.

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Subject, TextBody, MessageDate, ActivityId, CreatedById
            FROM EmailMessage
        ]);
    }

    public void execute(Database.BatchableContext context, List<EmailMessage> scope) {
        EmailActivityHealer.healRecords(scope);
    }

    public void finish(Database.BatchableContext context) {
        // no-op
    }

    // Schedulable entry point so it can be run nightly via System.schedule.
    public void execute(SchedulableContext context) {
        Database.executeBatch(new EmailActivityHealBatch(), 100);
    }
}
