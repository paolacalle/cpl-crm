@IsTest
private class EmailActivityHealBatchTest {
    private static Id personRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'cpl_applicant_account'
            LIMIT 1
        ].Id;
    }

    private static void makeScholarWithOrphanEmail(String email, String subject) {
        Account scholar = new Account(
            FirstName = 'Sweep', LastName = 'Scholar ' + email, PersonEmail = email, RecordTypeId = personRtId()
        );
        insert scholar;
        EmailMessage em = new EmailMessage(
            Subject = subject, TextBody = 'body', Status = '2', Incoming = true, MessageDate = System.now()
        );
        insert em;
        insert new EmailMessageRelation(
            EmailMessageId = em.Id, RelationType = 'FromAddress', RelationAddress = email
        );
    }

    @IsTest
    static void batchHealsAllMatchingOrphans() {
        makeScholarWithOrphanEmail('sweep1@example.com', 'Re: A');
        makeScholarWithOrphanEmail('sweep2@example.com', 'Re: B');

        Test.startTest();
        Database.executeBatch(new EmailActivityHealBatch(), 100);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Email:%'],
            'The nightly sweep should heal every address-matched orphan email');
    }

    @IsTest
    static void scheduleEnqueuesBatch() {
        Test.startTest();
        String jobId = System.schedule('Email Heal Test', '0 0 2 * * ?', new EmailActivityHealBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'The schedulable should register a cron job');
    }
}
