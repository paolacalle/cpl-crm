@IsTest
private class EmailActivityHealActionTest {
    private static Id personRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'cpl_applicant_account'
            LIMIT 1
        ].Id;
    }

    @IsTest
    static void healsScholarEmailsWhenActionRuns() {
        Account scholar = new Account(
            FirstName = 'Nora', LastName = 'Scholar', PersonEmail = 'nora@example.com', RecordTypeId = personRtId()
        );
        insert scholar;
        scholar = [SELECT Id, PersonContactId FROM Account WHERE Id = :scholar.Id];

        EmailMessage em = new EmailMessage(
            Subject = 'Welcome aboard', TextBody = 'hi', Status = '2', Incoming = true, MessageDate = System.now()
        );
        insert em;
        insert new EmailMessageRelation(
            EmailMessageId = em.Id, RelationType = 'FromAddress', RelationAddress = 'nora@example.com'
        );

        EmailActivityHealAction.Request req = new EmailActivityHealAction.Request();
        req.scholarContactId = scholar.PersonContactId;

        Test.startTest();
        EmailActivityHealAction.run(new List<EmailActivityHealAction.Request>{ req });
        Test.stopTest(); // flushes the enqueued job

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :scholar.PersonContactId],
            'The scholar email should be attached as a Task after the action runs');
    }

    @IsTest
    static void emptyOrNullRequestsAreSafe() {
        Test.startTest();
        EmailActivityHealAction.run(null);
        EmailActivityHealAction.run(new List<EmailActivityHealAction.Request>());
        EmailActivityHealAction.run(new List<EmailActivityHealAction.Request>{ new EmailActivityHealAction.Request() });
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE Subject LIKE 'Email:%'], 'No Tasks for empty input');
    }
}
