public with sharing class ScholarFinalistMaterialsService {
    public static final String RECORD_TYPE_DEVELOPER_NAME = 'Scholar_Finalist_Materials';
    public static final String TYPE_APPLICANT = 'Applicant Materials';
    public static final String TYPE_COACH_PROFESSOR = 'Coach/Professor Recommendation';
    public static final String TYPE_INTERNSHIP_SUPERVISOR = 'Internship Supervisor Recommendation';

    private static Boolean isHandlingSubmissions = false;
    private static Boolean isHandlingFiles = false;

    // CRM intake org-wide email address used as the sender for all automated emails.
    @TestVisible
    private static final String INTAKE_EMAIL_ADDRESS = 'crm-intake@climbpauselift.org';
    
    public static Id getIntakeOrgWideEmailId() {
        return OrgWideEmailUtil.getIntakeOrgWideEmailId();
    }

    @TestVisible
    private class SubmissionProcessingResult {
        public List<Form_Submission__c> submissionUpdates = new List<Form_Submission__c>();
        public List<Prospect_Scholar_Application__c> applicationUpdates =
            new List<Prospect_Scholar_Application__c>();
        public List<Messaging.SingleEmailMessage> recommendationEmails =
            new List<Messaging.SingleEmailMessage>();
    }

    public static String generateToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }

    public static String buildMaterialsFormUrl(Id applicationId, String token) {
        return buildMaterialsFormUrl(applicationId, token, TYPE_APPLICANT, null);
    }

    public static String buildMaterialsFormUrl(
        Id applicationId,
        String token,
        String materialType,
        String recommenderEmail
    ) {
        String baseUrl = String.isBlank(System.Label.Scholar_Finalist_Materials_Form_Base_URL)
            ? 'https://www.climbpauselift.org/scholar-finalist-materials'
            : System.Label.Scholar_Finalist_Materials_Form_Base_URL.trim();

        List<String> params = new List<String>{
            'applicationId=' + EncodingUtil.urlEncode(String.valueOf(applicationId), 'UTF-8'),
            'token=' + EncodingUtil.urlEncode(token, 'UTF-8'),
            'materialType=' + EncodingUtil.urlEncode(materialType, 'UTF-8')
        };
        if (!String.isBlank(recommenderEmail)) {
            params.add('recommenderEmail=' + EncodingUtil.urlEncode(recommenderEmail, 'UTF-8'));
        }

        return baseUrl + (baseUrl.contains('?') ? '&' : '?') + String.join(params, '&');
    }

    public static void handleSubmissions(
        List<Form_Submission__c> submissions,
        Map<Id, Form_Submission__c> oldMap
    ) {
        if (isHandlingSubmissions || submissions == null || submissions.isEmpty()) {
            return;
        }

        Map<Id, Schema.RecordTypeInfo> recordTypesById = Schema.SObjectType.Form_Submission__c
            .getRecordTypeInfosById();
        List<Form_Submission__c> materialSubmissions = new List<Form_Submission__c>();
        Set<Id> applicationIds = new Set<Id>();
        Set<String> materialTypes = new Set<String>();
        Set<Id> submissionIds = new Set<Id>();

        for (Form_Submission__c submission : submissions) {
            Schema.RecordTypeInfo recordTypeInfo = recordTypesById.get(submission.RecordTypeId);
            if (
                recordTypeInfo == null ||
                recordTypeInfo.getDeveloperName() != RECORD_TYPE_DEVELOPER_NAME
            ) {
                continue;
            }

            materialSubmissions.add(submission);
            submissionIds.add(submission.Id);
            if (submission.Prospect_Scholar_Application__c != null) {
                applicationIds.add(submission.Prospect_Scholar_Application__c);
            }
            if (!String.isBlank(submission.Material_Submission_Type__c)) {
                materialTypes.add(submission.Material_Submission_Type__c);
            }
        }

        if (materialSubmissions.isEmpty()) {
            return;
        }

        Map<Id, Prospect_Scholar_Application__c> applicationsById =
            new Map<Id, Prospect_Scholar_Application__c>([
                SELECT Id, Materials_Form_Token__c
                FROM Prospect_Scholar_Application__c
                WHERE Id IN :applicationIds
            ]);

        SubmissionProcessingResult result = evaluateSubmissions(
            materialSubmissions,
            applicationsById
        );

        List<Form_Submission__c> priorCurrentSubmissions = [
            SELECT Id
            FROM Form_Submission__c
            WHERE Prospect_Scholar_Application__c IN :applicationIds
            AND Material_Submission_Type__c IN :materialTypes
            AND Materials_Submission_Current__c = true
            AND Id NOT IN :submissionIds
        ];
        for (Form_Submission__c priorSubmission : priorCurrentSubmissions) {
            result.submissionUpdates.add(new Form_Submission__c(
                Id = priorSubmission.Id,
                Materials_Submission_Current__c = false
            ));
        }

        isHandlingSubmissions = true;
        try {
            if (!result.submissionUpdates.isEmpty()) {
                update result.submissionUpdates;
            }
            if (!result.applicationUpdates.isEmpty()) {
                update result.applicationUpdates;
            }
            if (!result.recommendationEmails.isEmpty()) {
                Messaging.sendEmail(result.recommendationEmails);
            }
        } finally {
            isHandlingSubmissions = false;
        }
    }

    @TestVisible
    private static SubmissionProcessingResult evaluateSubmissions(
        List<Form_Submission__c> materialSubmissions,
        Map<Id, Prospect_Scholar_Application__c> applicationsById
    ) {
        SubmissionProcessingResult result = new SubmissionProcessingResult();

        for (Form_Submission__c submission : materialSubmissions) {
            Prospect_Scholar_Application__c application = applicationsById.get(
                submission.Prospect_Scholar_Application__c
            );
            Boolean validToken = application != null &&
                !String.isBlank(application.Materials_Form_Token__c) &&
                application.Materials_Form_Token__c == submission.Submission_Token__c;

            if (!validToken) {
                result.submissionUpdates.add(new Form_Submission__c(
                    Id = submission.Id,
                    Needs_Review__c = true,
                    Processing_Status__c = 'Needs Review',
                    Materials_Submission_Current__c = false
                ));
                continue;
            }

            result.submissionUpdates.add(new Form_Submission__c(
                Id = submission.Id,
                Needs_Review__c = false,
                Processing_Status__c = 'Processed',
                Materials_Submission_Current__c = true
            ));

            Prospect_Scholar_Application__c applicationUpdate =
                new Prospect_Scholar_Application__c(Id = application.Id);
            Boolean hasApplicationUpdate = false;

            if (submission.Material_Submission_Type__c == TYPE_APPLICANT) {
                if (!String.isBlank(submission.Finalist_Essay__c)) {
                    applicationUpdate.Essay_Received__c = true;
                    hasApplicationUpdate = true;
                }
                if (!String.isBlank(submission.Financial_Aid_Scholarship_Grant_Details__c)) {
                    applicationUpdate.Financial_Aid_Info_Received__c = true;
                    hasApplicationUpdate = true;
                }
                if (!String.isBlank(submission.Resume_URL__c)) {
                    applicationUpdate.Resume_Received__c = true;
                    hasApplicationUpdate = true;
                }

                result.recommendationEmails.addAll(buildRecommendationEmails(submission, application));
            }

            if (hasApplicationUpdate) {
                result.applicationUpdates.add(applicationUpdate);
            }
        }

        return result;
    }

    public static void handleFileLinks(List<ContentDocumentLink> links) {
        if (isHandlingFiles || links == null || links.isEmpty()) {
            return;
        }

        Set<Id> formSubmissionIds = new Set<Id>();
        Map<Id, Set<Id>> documentIdsBySubmissionId = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : links) {
            if (link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == Form_Submission__c.SObjectType) {
                formSubmissionIds.add(link.LinkedEntityId);
                if (!documentIdsBySubmissionId.containsKey(link.LinkedEntityId)) {
                    documentIdsBySubmissionId.put(link.LinkedEntityId, new Set<Id>());
                }
                documentIdsBySubmissionId.get(link.LinkedEntityId).add(link.ContentDocumentId);
            }
        }

        if (formSubmissionIds.isEmpty()) {
            return;
        }

        List<Form_Submission__c> submissions = [
            SELECT Id,
                   RecordType.DeveloperName,
                   Prospect_Scholar_Application__c,
                   Material_Submission_Type__c,
                   Materials_Submission_Current__c
            FROM Form_Submission__c
            WHERE Id IN :formSubmissionIds
        ];

        Map<Id, Prospect_Scholar_Application__c> applicationUpdatesById =
            new Map<Id, Prospect_Scholar_Application__c>();
        Set<Id> applicationIds = new Set<Id>();
        Set<Id> documentIds = new Set<Id>();
        Map<String, ContentDocumentLink> desiredApplicationLinks = new Map<String, ContentDocumentLink>();

        for (Form_Submission__c submission : submissions) {
            if (
                submission.RecordType == null ||
                submission.RecordType.DeveloperName != RECORD_TYPE_DEVELOPER_NAME ||
                submission.Prospect_Scholar_Application__c == null ||
                !submission.Materials_Submission_Current__c
            ) {
                continue;
            }

            Prospect_Scholar_Application__c applicationUpdate =
                applicationUpdatesById.containsKey(submission.Prospect_Scholar_Application__c)
                    ? applicationUpdatesById.get(submission.Prospect_Scholar_Application__c)
                    : new Prospect_Scholar_Application__c(Id = submission.Prospect_Scholar_Application__c);

            if (submission.Material_Submission_Type__c == TYPE_APPLICANT) {
                applicationUpdate.Resume_Received__c = true;
            } else if (submission.Material_Submission_Type__c == TYPE_COACH_PROFESSOR) {
                applicationUpdate.Coach_Professor_Recommendation_Received__c = true;
            } else if (submission.Material_Submission_Type__c == TYPE_INTERNSHIP_SUPERVISOR) {
                applicationUpdate.Internship_Supervisor_Rec_Received__c = true;
            }

            applicationUpdatesById.put(submission.Prospect_Scholar_Application__c, applicationUpdate);
            applicationIds.add(submission.Prospect_Scholar_Application__c);

            for (Id documentId : documentIdsBySubmissionId.get(submission.Id)) {
                documentIds.add(documentId);
                desiredApplicationLinks.put(
                    String.valueOf(documentId) + ':' + String.valueOf(submission.Prospect_Scholar_Application__c),
                    new ContentDocumentLink(
                        ContentDocumentId = documentId,
                        LinkedEntityId = submission.Prospect_Scholar_Application__c,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );
            }
        }

        if (applicationUpdatesById.isEmpty()) {
            return;
        }

        for (ContentDocumentLink existingLink : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
            AND LinkedEntityId IN :applicationIds
        ]) {
            desiredApplicationLinks.remove(
                String.valueOf(existingLink.ContentDocumentId) + ':' + String.valueOf(existingLink.LinkedEntityId)
            );
        }

        isHandlingFiles = true;
        try {
            update applicationUpdatesById.values();
            if (!desiredApplicationLinks.isEmpty()) {
                insert desiredApplicationLinks.values();
            }
        } finally {
            isHandlingFiles = false;
        }
    }

    private static List<Messaging.SingleEmailMessage> buildRecommendationEmails(
        Form_Submission__c submission,
        Prospect_Scholar_Application__c application
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        addRecommendationEmail(
            emails,
            submission.Coach_Professor_Recommender_Email__c,
            submission.Coach_Professor_Recommender_Name__c,
            application,
            TYPE_COACH_PROFESSOR
        );
        addRecommendationEmail(
            emails,
            submission.Internship_Supervisor_Recommender_Email__c,
            submission.Internship_Supervisor_Recommender_Name__c,
            application,
            TYPE_INTERNSHIP_SUPERVISOR
        );
        return emails;
    }

    private static void addRecommendationEmail(
        List<Messaging.SingleEmailMessage> emails,
        String emailAddress,
        String recommenderName,
        Prospect_Scholar_Application__c application,
        String materialType
    ) {
        if (String.isBlank(emailAddress)) {
            return;
        }

        String formUrl = buildMaterialsFormUrl(
            application.Id,
            application.Materials_Form_Token__c,
            materialType,
            emailAddress
        );
        String greeting = String.isBlank(recommenderName)
            ? 'Hello'
            : 'Hello ' + recommenderName.escapeHtml4();

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ emailAddress });
        email.setSubject('CPL Scholar Finalist Recommendation Request');
        email.setHtmlBody(
            '<p>' + greeting + ',</p>' +
            '<p>A CPL Scholar finalist listed you as a recommender. Please submit your recommendation letter using the secure form below.</p>' +
            '<p><a href="' + formUrl.escapeHtml4() + '">Submit recommendation</a></p>' +
            '<p>Thank you,<br/>CPL</p>'
        );
        email.setSaveAsActivity(false);
        emails.add(email);
    }
}
