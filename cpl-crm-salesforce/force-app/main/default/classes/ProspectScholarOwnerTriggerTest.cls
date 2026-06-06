@IsTest(SeeAllData=true)
private class ProspectScholarOwnerTriggerTest {
    private static Id getApplicantAccountId() {
        Account applicant = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            AND RecordType.DeveloperName = 'cpl_applicant_account'
            AND Qualifying_Internship_Count__c >= 1
            LIMIT 1
        ];
        return applicant.Id;
    }

    @IsTest
    static void defaultsCaseOwnerToCreatorWhenBlank() {
        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(
            Applicant_Account__c = getApplicantAccountId(),
            Application_Status__c = 'Invite Sent'
        );

        insert application;

        Prospect_Scholar_Application__c insertedApplication = [
            SELECT Case_Owner__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :application.Id
        ];

        System.assertEquals(UserInfo.getUserId(), insertedApplication.Case_Owner__c);
    }

    @IsTest
    static void preservesExplicitCaseOwnerOnInsert() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User explicitOwner = new User(
            Alias = 'tbo',
            Email = 'tbo@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Other',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            UserName = 'tbo+' + System.now().getTime() + '@example.com'
        );
        insert explicitOwner;

        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(
            Applicant_Account__c = getApplicantAccountId(),
            Application_Status__c = 'Invite Sent',
            Case_Owner__c = explicitOwner.Id
        );

        insert application;

        Prospect_Scholar_Application__c insertedApplication = [
            SELECT Case_Owner__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :application.Id
        ];

        System.assertEquals(explicitOwner.Id, insertedApplication.Case_Owner__c);
    }
}
