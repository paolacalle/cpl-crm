@IsTest(SeeAllData=true)
private class ApplicationEmailComposerControllerTest {
    private static Id getEligibleApplicantAccountId() {
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

    private static Prospect_Scholar_Application__c makeApplication() {
        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(
            Applicant_Account__c = getEligibleApplicantAccountId(),
            Application_Status__c = 'Invite Sent'
        );
        insert application;
        return application;
    }

    @IsTest
    static void markSentUpdatesInviteFields() {
        Prospect_Scholar_Application__c application = makeApplication();

        Test.startTest();
        ApplicationEmailComposerController.markSent(
            application.Id,
            'Invite',
            'https://example.com/finalist-materials'
        );
        Test.stopTest();

        Prospect_Scholar_Application__c updated = [
            SELECT Scholarship_Invite_Sent__c,
                   Scholarship_Invite_Sent_Date__c,
                   Scholarship_Invite_Status__c,
                   Application_Status__c,
                   Materials_Form_URL__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :application.Id
        ];

        System.assertEquals(true, updated.Scholarship_Invite_Sent__c);
        System.assertNotEquals(null, updated.Scholarship_Invite_Sent_Date__c);
        System.assertEquals('Sent', updated.Scholarship_Invite_Status__c);
        System.assertEquals('Invite Sent', updated.Application_Status__c);
        System.assertEquals('https://example.com/finalist-materials', updated.Materials_Form_URL__c);
    }

    @IsTest
    static void markSentSavesMaterialsUrl() {
        Prospect_Scholar_Application__c application = makeApplication();

        Test.startTest();
        ApplicationEmailComposerController.markSent(
            application.Id,
            'Materials',
            'https://example.com/materials'
        );
        Test.stopTest();

        Prospect_Scholar_Application__c updated = [
            SELECT Materials_Form_URL__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :application.Id
        ];

        System.assertEquals('https://example.com/materials', updated.Materials_Form_URL__c);
    }

    @IsTest
    static void sendEmailRequiresSubjectAndBody() {
        Id applicationId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000001'
        );

        try {
            ApplicationEmailComposerController.sendEmail(applicationId, 'Invite', '', 'Body', null);
            System.assert(false, 'Expected a handled exception.');
        } catch (AuraHandledException ex) {
            System.assert(true, 'Expected a handled exception.');
        }

        try {
            ApplicationEmailComposerController.sendEmail(applicationId, 'Invite', 'Subject', '', null);
            System.assert(false, 'Expected a handled exception.');
        } catch (AuraHandledException ex) {
            System.assert(true, 'Expected a handled exception.');
        }
    }
}
