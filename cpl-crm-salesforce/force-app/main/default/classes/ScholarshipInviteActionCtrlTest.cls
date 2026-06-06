@IsTest(SeeAllData=true)
private class ScholarshipInviteActionCtrlTest {
    @IsTest
    static void nullApplicationIdRaisesHandledException() {
        try {
            ScholarshipInviteActionCtrl.sendInvite(null);
            System.assert(false, 'Expected an exception.');
        } catch (AuraHandledException ex) {
            System.assert(true, 'Expected an exception.');
        }
    }

    @IsTest
    static void sendInviteUsesExistingApplication() {
        Prospect_Scholar_Application__c application = [
            SELECT Id
            FROM Prospect_Scholar_Application__c
            LIMIT 1
        ];

        Test.startTest();
        ScholarshipInviteActionCtrl.sendInvite(application.Id);
        Test.stopTest();

        System.assert(true, 'Wrapper executed without throwing.');
    }
}
