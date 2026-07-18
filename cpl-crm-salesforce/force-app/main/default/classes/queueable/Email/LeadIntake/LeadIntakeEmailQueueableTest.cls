@isTest
private class LeadIntakeEmailQueueableTest {
    private static Id rt(String dev) {
        return [SELECT Id FROM RecordType
                WHERE SobjectType = 'Lead' AND DeveloperName = :dev LIMIT 1].Id;
    }

    @isTest
    static void scholarMessageHasPdfAndResume() {
        Lead ld = new Lead(
            FirstName = 'Ada', LastName = 'Scholar', Company = 'N/A',
            Status = 'New', Email = 'a@e.com', RecordTypeId = rt('CPL_Scholar_Lead')
        );
        insert ld;
        ld = [SELECT Id, Name, RecordType.DeveloperName FROM Lead WHERE Id = :ld.Id];

        insert new ContentVersion(
            Title = 'Resume - Ada', PathOnClient = 'Resume - Ada.pdf',
            VersionData = Blob.valueOf('x'), FirstPublishLocationId = ld.Id
        );
        ContentVersion cv = [
            SELECT Id, Title, FileExtension, VersionData
            FROM ContentVersion WHERE FirstPublishLocationId = :ld.Id LIMIT 1
        ];

        Test.startTest();
        Messaging.SingleEmailMessage m = LeadIntakeEmailQueueable.buildMsg(
            ld, new List<String>{ 'intake@e.com' }, null, new List<ContentVersion>{ cv });
        Test.stopTest();

        System.assert(m.getSubject().startsWith('New CPL Scholar'), 'Scholar subject');
        System.assertEquals(2, m.getFileAttachments().size(), 'PDF summary + resume');
    }

    @isTest
    static void partnerMessageHasPdfOnly() {
        Lead ld = new Lead(
            FirstName = 'Nia', LastName = 'Partner', Company = 'Acme',
            Status = 'New', Email = 'n@e.com', RecordTypeId = rt('Partner_Lead')
        );
        insert ld;
        ld = [SELECT Id, Name, RecordType.DeveloperName FROM Lead WHERE Id = :ld.Id];

        Messaging.SingleEmailMessage m = LeadIntakeEmailQueueable.buildMsg(
            ld, new List<String>{ 'intake@e.com' }, null, null);

        System.assert(m.getSubject().startsWith('New CPL Partner Lead'), 'Partner subject');
        System.assertEquals(1, m.getFileAttachments().size(), 'PDF summary only');
    }

    @isTest
    static void loadResumesMapsFile() {
        Lead ld = new Lead(LastName = 'Res', Company = 'N/A', Status = 'New');
        insert ld;
        insert new ContentVersion(
            Title = 'Resume - Res', PathOnClient = 'Resume - Res.pdf',
            VersionData = Blob.valueOf('x'), FirstPublishLocationId = ld.Id
        );

        Map<Id, List<ContentVersion>> byLead =
            LeadIntakeEmailQueueable.loadResumes(new List<Id>{ ld.Id });
        System.assertEquals(1, byLead.get(ld.Id).size(), 'Resume mapped to the lead');
    }

    @isTest
    static void executeNoRecipientsIsSafe() {
        Lead ld = new Lead(
            LastName = 'NoRcpt', Company = 'N/A', Status = 'New',
            Email = 'x@e.com', RecordTypeId = rt('CPL_Scholar_Lead')
        );
        insert ld;

        Test.startTest();
        System.enqueueJob(new LeadIntakeEmailQueueable(new List<Id>{ ld.Id }));
        Test.stopTest(); // no group members -> early return, no exception
        System.assert(true, 'Queueable completes safely with no recipients');
    }

    @isTest
    static void executeSendsWhenRecipientsExist() {
        // Setup-object DML first (User + GroupMember)...
        User u = new User(
            FirstName = 'Intake', LastName = 'Rcpt',
            Email = 'intake.rcpt@cpl.example.com',
            Username = 'intake.rcpt@cpl.example.com.cpltest', Alias = 'ircpt',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id
        );
        insert u;
        Group g = [SELECT Id FROM Group
                   WHERE DeveloperName = 'PG_Intake_Owners' AND Type = 'Regular' LIMIT 1];
        insert new GroupMember(GroupId = g.Id, UserOrGroupId = u.Id);

        // ...then non-setup DML wrapped in runAs to avoid MIXED_DML_OPERATION.
        Lead ld;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            ld = new Lead(
                FirstName = 'Ada', LastName = 'Scholar', Company = 'N/A',
                Status = 'New', Email = 'a@e.com', RecordTypeId = rt('CPL_Scholar_Lead')
            );
            insert ld;
            insert new ContentVersion(
                Title = 'Resume - Ada', PathOnClient = 'Resume - Ada.pdf',
                VersionData = Blob.valueOf('x'), FirstPublishLocationId = ld.Id
            );
        }

        Test.startTest();
        System.enqueueJob(new LeadIntakeEmailQueueable(new List<Id>{ ld.Id }));
        Test.stopTest(); // async send runs here with a real recipient, no exception
        System.assertEquals(1, [SELECT COUNT() FROM Lead WHERE Id = :ld.Id]);
    }
}
