public with sharing class ApplicationEmailComposerController {
    private static final String TYPE_INVITE = 'Invite';
    private static final String TYPE_MATERIALS = 'Materials';
    private static final String TYPE_MISSING_MATERIALS = 'MissingMaterials';

    @AuraEnabled
    public static void sendEmail(Id applicationId, String emailType, String subject, String body, String materialsUrl) {
        if (applicationId == null) {
            throw new AuraHandledException('Application is required.');
        }
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Email subject is required.');
        }
        if (String.isBlank(body)) {
            throw new AuraHandledException('Email message is required.');
        }

        Prospect_Scholar_Application__c app = [
            SELECT Id,
                   Applicant_Account__r.PersonContactId,
                   Applicant_Account__r.PersonEmail
            FROM Prospect_Scholar_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        Id contactId = app.Applicant_Account__r == null
            ? null
            : app.Applicant_Account__r.PersonContactId;
        String recipientEmail = app.Applicant_Account__r == null
            ? null
            : app.Applicant_Account__r.PersonEmail;
        if (contactId == null || String.isBlank(recipientEmail)) {
            throw new AuraHandledException('The applicant account needs a Person Contact and Person Email.');
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(contactId);
        email.setWhatId(applicationId);
        email.setSaveAsActivity(true);
        email.setSubject(subject.trim());
        email.setPlainTextBody(body);

        Id intakeOrgWideEmailId = OrgWideEmailUtil.getIntakeOrgWideEmailId();
        if (intakeOrgWideEmailId != null) {
            email.setOrgWideEmailAddressId(intakeOrgWideEmailId);
        }

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        updateApplicationAfterEmail(applicationId, emailType, materialsUrl);
    }

    @AuraEnabled
    public static void markSent(Id applicationId, String emailType, String materialsUrl) {
        if (applicationId == null) {
            throw new AuraHandledException('Application is required.');
        }

        updateApplicationAfterEmail(applicationId, emailType, materialsUrl);
    }

    private static void updateApplicationAfterEmail(Id applicationId, String emailType, String materialsUrl) {
        Prospect_Scholar_Application__c updateRecord =
            new Prospect_Scholar_Application__c(Id = applicationId);

        if (emailType == TYPE_INVITE) {
            updateRecord.Scholarship_Invite_Sent__c = true;
            updateRecord.Scholarship_Invite_Sent_Date__c = System.now();
            updateRecord.Scholarship_Invite_Status__c = 'Sent';
            updateRecord.Application_Status__c = 'Invite Sent';
            if (!String.isBlank(materialsUrl)) {
                updateRecord.Materials_Form_URL__c = materialsUrl.trim();
            }
        } else if (emailType == TYPE_MATERIALS || emailType == TYPE_MISSING_MATERIALS) {
            if (!String.isBlank(materialsUrl)) {
                updateRecord.Materials_Form_URL__c = materialsUrl.trim();
            }
        } else {
            throw new AuraHandledException('Unsupported email type.');
        }

        update updateRecord;
    }
}
