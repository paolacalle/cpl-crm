@isTest
private class GetGroupTeamEmailsUtilTest {
    @isTest
    static void emptyArgsReturnEmpty() {
        System.assert(GetGroupTeamEmailsUtil.getTeamEmails(null, 'Regular').isEmpty());
        System.assert(GetGroupTeamEmailsUtil.getTeamEmails(new Set<String>(), 'Regular').isEmpty());
        System.assert(GetGroupTeamEmailsUtil.getTeamEmails(
            new Set<String>{ 'PG_Intake_Owners' }, '').isEmpty());
    }

    @isTest
    static void resolvesActiveMemberEmail() {
        User u = new User(
            FirstName = 'Intake', LastName = 'Tester',
            Email = 'intake.tester@cpl.example.com',
            Username = 'intake.tester@cpl.example.com.cpltest', Alias = 'intk',
            TimeZoneSidKey = 'America/New_York', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id
        );
        insert u;

        Group g = [SELECT Id FROM Group
                   WHERE DeveloperName = 'PG_Intake_Owners' AND Type = 'Regular' LIMIT 1];
        insert new GroupMember(GroupId = g.Id, UserOrGroupId = u.Id);

        Test.startTest();
        Set<String> emails = GetGroupTeamEmailsUtil.getTeamEmails(
            new Set<String>{ 'PG_Intake_Owners' }, 'Regular');
        Test.stopTest();

        System.assert(emails.contains('intake.tester@cpl.example.com'),
            'Active group member email should resolve');
    }
}
