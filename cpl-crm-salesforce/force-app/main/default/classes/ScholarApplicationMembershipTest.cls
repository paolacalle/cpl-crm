@IsTest
private class ScholarApplicationMembershipTest {
    @TestSetup
    static void setup() {
        Id personType = [SELECT Id FROM RecordType WHERE SObjectType = 'Account'
            AND DeveloperName = 'cpl_applicant_account' LIMIT 1].Id;
        List<Account> members = new List<Account>();
        for (Integer i = 0; i < 2; i++) {
            members.add(new Account(RecordTypeId = personType, LastName = 'Membership Test ' + i,
                PersonEmail = 'membership' + i + '@example.com', College_Year__pc = 'Junior',
                CPL_Student_Lifecycle__c = 'Athlete'));
        }
        insert members;
        Id internshipType = [SELECT Id FROM RecordType WHERE SObjectType = 'Employment__c'
            AND DeveloperName = 'Internship' LIMIT 1].Id;
        List<Employment__c> internships = new List<Employment__c>();
        for (Account member : members) {
            internships.add(new Employment__c(CPL_Member__c = member.Id, RecordTypeId = internshipType,
                Employment_Type__c = 'Internship',
                Start_Date__c = Date.today().addDays(-90), End_Date__c = Date.today().addDays(-1),
                Is_qualifying__c = true));
        }
        insert internships;
        // Dev counts Employment Type; older metadata counts the record type.
        // Set both, and verify the fixture before testing membership automation.
        for (Account member : [SELECT Qualifying_Internship_Count__c FROM Account WHERE Id IN :members]) {
            System.assertEquals(1, member.Qualifying_Internship_Count__c,
                'Test member must have one qualifying internship before application creation');
        }
    }
    private static void expectFlag(Id memberId, Boolean expected) {
        Account member = [SELECT Has_Active_Scholarship_Application__c FROM Account WHERE Id = :memberId];
        System.assertEquals(expected, member.Has_Active_Scholarship_Application__c);
    }
    private static Prospect_Scholar_Application__c application(Id memberId) {
        return new Prospect_Scholar_Application__c(Applicant_Account__c = memberId,
            College_Year__c = 'Junior', Application_Status__c = 'Invite Sent',
            Scholarship_Invite_Sent__c = true, Scholarship_Invite_Confirmed__c = true,
            Scholarship_Invite_Status__c = 'Confirmed', Eligibility_Confirmed__c = true);
    }
    @IsTest
    static void tracksMultipleApplicationsReparentDeleteAndUndelete() {
        List<Account> members = [SELECT Id FROM Account ORDER BY LastName];
        Prospect_Scholar_Application__c first = application(members[0].Id);
        Prospect_Scholar_Application__c second = application(members[0].Id);
        Test.startTest();
        insert new List<Prospect_Scholar_Application__c>{first, second};
        expectFlag(members[0].Id, true);
        delete first;
        expectFlag(members[0].Id, true);
        second.Applicant_Account__c = members[1].Id;
        update second;
        expectFlag(members[0].Id, false);
        expectFlag(members[1].Id, true);
        delete second;
        expectFlag(members[1].Id, false);
        undelete first;
        expectFlag(members[0].Id, true);
        Test.stopTest();
    }
    @IsTest
    static void waitlistedIsActiveAcceptedIsClosed() {
        Account member = [SELECT Id FROM Account LIMIT 1];
        Prospect_Scholar_Application__c app = application(member.Id);
        insert app;
        Test.startTest();
        app.Application_Status__c = 'Waitlisted';
        update app;
        expectFlag(member.Id, true);
        List<ScholarApplicationPipelineController.Tile> tiles = ScholarApplicationPipelineController.getPipeline();
        System.assertEquals(1, tiles[2].count, 'Waitlisted stays ready for decision');
        System.assertEquals(1, tiles[3].count, 'Waitlisted is also a recorded decision');
        new ScholarApplicationStageBackfill().execute(null, new List<SObject>{app});
        app.Application_Status__c = 'Accepted';
        update app;
        expectFlag(member.Id, false);
        Test.stopTest();
        System.assertEquals('Closed', [SELECT Application_Stage__c FROM Prospect_Scholar_Application__c WHERE Id = :app.Id].Application_Stage__c);
    }
    @IsTest
    static void rejectedAndWithdrawnAreClosed() {
        Account member = [SELECT Id FROM Account LIMIT 1];
        List<Prospect_Scholar_Application__c> apps = new List<Prospect_Scholar_Application__c>{
            application(member.Id), application(member.Id)};
        insert apps;
        String reason;
        for (Schema.PicklistEntry entry : Prospect_Scholar_Application__c.Rejection_Filter__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) { reason = entry.getValue(); break; }
        }
        apps[0].Application_Status__c = 'Rejected';
        apps[1].Application_Status__c = 'Withdrawn';
        for (Prospect_Scholar_Application__c app : apps) {
            app.Rejection_Filter__c = reason;
            app.Rejection_Reason__c = 'Application closed for membership automation testing.';
        }
        Test.startTest();
        update apps;
        expectFlag(member.Id, false);
        Test.stopTest();
    }
    @IsTest
    static void backfillRepairsStaleFlagsWithoutChangingLifecycle() {
        List<Account> members = [SELECT Id FROM Account ORDER BY LastName];
        insert application(members[0].Id);
        update new List<Account>{
            new Account(Id = members[0].Id, Has_Active_Scholarship_Application__c = false),
            new Account(Id = members[1].Id, Has_Active_Scholarship_Application__c = true)};
        Test.startTest();
        Database.executeBatch(new ScholarApplicationMembershipBackfill(), 100);
        Test.stopTest();
        expectFlag(members[0].Id, true);
        expectFlag(members[1].Id, false);
        System.assertEquals('Athlete', [SELECT CPL_Student_Lifecycle__c FROM Account WHERE Id = :members[1].Id].CPL_Student_Lifecycle__c);
    }
}
