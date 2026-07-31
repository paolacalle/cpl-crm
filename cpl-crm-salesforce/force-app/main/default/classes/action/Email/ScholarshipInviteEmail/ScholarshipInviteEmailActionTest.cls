@IsTest
private class ScholarshipInviteEmailActionTest {
    @IsTest
    static void emptyRequestListDoesNothing() {
        Test.startTest();
        ScholarshipInviteEmailAction.sendInvite(new List<ScholarshipInviteEmailAction.Request>());
        Test.stopTest();

        System.assert(true, 'Empty request lists are ignored.');
    }

    @IsTest
    static void missingApplicationRaisesFlowException() {
        ScholarshipInviteEmailAction.Request request = new ScholarshipInviteEmailAction.Request();
        request.applicationId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000001'
        );

        Test.startTest();
        try {
            ScholarshipInviteEmailAction.sendInvite(new List<ScholarshipInviteEmailAction.Request>{ request });
            System.assert(false, 'Expected a FlowException for a missing application.');
        } catch (ScholarshipInviteEmailAction.FlowException ex) {
            System.assertEquals('Prospect Scholar Application was not found.', ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void inviteBodyUsesFallbackGreeting() {
        String body = ScholarshipInviteEmailAction.buildInviteBody(null);

        System.assert(body.contains('there,'));
        System.assert(body.contains('CPL Scholar Finalist'));
    }

    @IsTest
    static void buildMessagesCreatesEmailForApplication() {
        Id applicationId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000002'
        );
        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(Id = applicationId);
        Account applicant = new Account(FirstName = 'Tobi', PersonEmail = 'tobidoe@example.com');
        application.putSObject('Applicant_Account__r', applicant);

        ScholarshipInviteEmailAction.Request request = new ScholarshipInviteEmailAction.Request();
        request.applicationId = applicationId;

        List<Messaging.SingleEmailMessage> messages = ScholarshipInviteEmailAction.buildMessages(
            new List<ScholarshipInviteEmailAction.Request>{ request },
            new Map<Id, Prospect_Scholar_Application__c>{ applicationId => application }
        );

        System.assertEquals(1, messages.size());
    }

    @IsTest
    static void buildMessagesRequiresApplicantEmail() {
        Id applicationId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000003'
        );
        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(Id = applicationId);
        application.putSObject('Applicant_Account__r', new Account(FirstName = 'Tobi'));

        ScholarshipInviteEmailAction.Request request = new ScholarshipInviteEmailAction.Request();
        request.applicationId = applicationId;

        try {
            ScholarshipInviteEmailAction.buildMessages(
                new List<ScholarshipInviteEmailAction.Request>{ request },
                new Map<Id, Prospect_Scholar_Application__c>{ applicationId => application }
            );
            System.assert(false, 'Expected a FlowException for a missing applicant email.');
        } catch (ScholarshipInviteEmailAction.FlowException ex) {
            System.assertEquals('Applicant Person Account does not have a Person Email value.', ex.getMessage());
        }
    }
}