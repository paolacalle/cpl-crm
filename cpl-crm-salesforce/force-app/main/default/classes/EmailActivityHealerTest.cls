@IsTest
private class EmailActivityHealerTest {
    // Scholars are PersonAccounts in this org, so the tests create person accounts
    // (record type cpl_applicant_account) and match on PersonEmail -- the same path
    // the healer takes in production.

    private static Id personRtId {
        get {
            if (personRtId == null) {
                personRtId = [
                    SELECT Id FROM RecordType
                    WHERE SObjectType = 'Account' AND DeveloperName = 'cpl_applicant_account'
                    LIMIT 1
                ].Id;
            }
            return personRtId;
        }
        set;
    }

    // A regular business Contact (not a PersonAccount). Used where the test must
    // avoid firing the PersonAccount-create heal Flow, so it can assert on the
    // healer's behavior in isolation.
    private static Contact makeBusinessContact(String email) {
        // Donor Household: a non-person business account with no required-field
        // validation rules, so it inserts cleanly and does not fire the
        // PersonAccount-create heal Flow.
        Id bizRt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Donor_Household'
            LIMIT 1
        ].Id;
        Account biz = new Account(Name = 'Household ' + email, RecordTypeId = bizRt);
        insert biz;
        Contact c = new Contact(FirstName = 'Kath', LastName = 'B', Email = email, AccountId = biz.Id);
        insert c;
        return [SELECT Id, AccountId FROM Contact WHERE Id = :c.Id];
    }

    // Returns the Account with its PersonContactId (the scholar's Contact).
    private static Account makeScholar(String email) {
        Account acct = new Account(
            FirstName = 'Ada',
            LastName = 'Scholar ' + email,
            PersonEmail = email,
            RecordTypeId = personRtId
        );
        insert acct;
        return [SELECT Id, PersonContactId FROM Account WHERE Id = :acct.Id];
    }

    private static EmailMessage makeEmail(String subject, Id activityId) {
        EmailMessage em = new EmailMessage(
            Subject = subject,
            TextBody = 'Body of ' + subject,
            Status = '3',
            Incoming = true,
            MessageDate = System.now(),
            ActivityId = activityId
        );
        insert em;
        return em;
    }

    private static void addRelation(Id emId, String relType, String addr) {
        insert new EmailMessageRelation(EmailMessageId = emId, RelationType = relType, RelationAddress = addr);
    }

    @IsTest
    static void createsTaskForOrphanMatchingScholar() {
        Account scholar = makeScholar('ada@example.com');
        EmailMessage em = makeEmail('Welcome', null);
        addRelation(em.Id, 'FromAddress', 'ada@example.com');
        addRelation(em.Id, 'ToAddress', 'lisa@climbpauselift.org'); // internal -> ignored

        Test.startTest();
        Integer healed = EmailActivityHealer.healEmailMessages(new Set<Id>{ em.Id });
        // Second run must be a no-op (RelatedToId now set) -> no duplicate Task.
        EmailActivityHealer.healEmailMessages(new Set<Id>{ em.Id });
        Test.stopTest();

        System.assertEquals(1, healed, 'The orphan email should be healed once');
        List<Task> tasks = [SELECT WhoId, Status, Subject FROM Task WHERE WhoId = :scholar.PersonContactId];
        System.assertEquals(1, tasks.size(), 'Exactly one Email Task should exist for the scholar');
        System.assertEquals('Completed', tasks[0].Status, 'Task should be logged as completed');
        System.assertEquals('Email: Welcome', tasks[0].Subject, 'Task subject should carry the email subject');
        Task healedTask = [SELECT Source_Email_Message__c FROM Task WHERE WhoId = :scholar.PersonContactId LIMIT 1];
        System.assertEquals(em.Id, (Id) healedTask.Source_Email_Message__c, 'Task should record its source email for idempotency/provenance');
    }

    @IsTest
    static void repointsLeadOnlyTaskToScholar() {
        // Business Contact (not a PersonAccount) so the create-heal Flow does not
        // fire and add an async heal pass that would confound this assertion.
        Contact scholar = makeBusinessContact('bkath@example.com');
        Lead lead = new Lead(FirstName = 'Kath', LastName = 'B', Company = 'CPL', Status = 'New');
        insert lead;
        Task leadTask = new Task(WhoId = lead.Id, Subject = 'Email: Prior', Status = 'Completed');
        insert leadTask;

        // ActivityId is read-only on EmailMessage in this org, so we cannot insert
        // the email pre-linked to the Task. In production the platform sets that
        // link; here we simulate it with an in-memory record carrying the same Id.
        EmailMessage em = makeEmail('Prior', null);
        addRelation(em.Id, 'FromAddress', 'bkath@example.com');
        EmailMessage linked = new EmailMessage(
            Id = em.Id, ActivityId = leadTask.Id, Subject = 'Prior', MessageDate = System.now()
        );

        Test.startTest();
        Integer healed = EmailActivityHealer.healRecords(new List<EmailMessage>{ linked });
        Test.stopTest();

        System.assertEquals(1, healed, 'The lead-only email should be healed');
        Task after = [SELECT WhoId FROM Task WHERE Id = :leadTask.Id];
        System.assertEquals(scholar.Id, after.WhoId, 'Existing Task should be re-pointed to the scholar contact');
        // The healer must re-point the existing Task, not spawn a new one for this email.
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE Source_Email_Message__c = :em.Id],
            'No new healer Task should be created when a Task already exists for the email');
    }

    @IsTest
    static void skipsAmbiguousAndUnknownAddresses() {
        Account a = makeScholar('one@example.com');
        Account b = makeScholar('two@example.com');

        EmailMessage ambiguous = makeEmail('Group note', null);
        addRelation(ambiguous.Id, 'ToAddress', 'one@example.com');
        addRelation(ambiguous.Id, 'CcAddress', 'two@example.com');

        EmailMessage unknown = makeEmail('Cold email', null);
        addRelation(unknown.Id, 'FromAddress', 'stranger@nowhere.com');

        Test.startTest();
        Integer healed = EmailActivityHealer.healEmailMessages(new Set<Id>{ ambiguous.Id, unknown.Id });
        Test.stopTest();

        System.assertEquals(0, healed, 'Ambiguous and unknown-address emails must be left untouched');
        System.assertEquals(0, [SELECT COUNT() FROM Task], 'No Tasks should be created');
    }

    @IsTest
    static void healForScholarsFindsMatchingEmails() {
        Account scholar = makeScholar('ln@example.com');
        EmailMessage em = makeEmail('Internship update', null);
        addRelation(em.Id, 'FromAddress', 'ln@example.com');

        Test.startTest();
        Integer healed = EmailActivityHealer.healForScholars(new Set<Id>{ scholar.PersonContactId });
        Test.stopTest();

        System.assertEquals(1, healed, 'Emails matching the scholar address should be healed');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhoId = :scholar.PersonContactId], 'One Task for the scholar');
    }

    @IsTest
    static void emptyInputsAreSafe() {
        Test.startTest();
        System.assertEquals(0, EmailActivityHealer.healEmailMessages(null));
        System.assertEquals(0, EmailActivityHealer.healEmailMessages(new Set<Id>()));
        System.assertEquals(0, EmailActivityHealer.healForScholars(new Set<Id>()));
        System.assertEquals(0, EmailActivityHealer.healRecords(new List<EmailMessage>()));
        Test.stopTest();
    }
}
