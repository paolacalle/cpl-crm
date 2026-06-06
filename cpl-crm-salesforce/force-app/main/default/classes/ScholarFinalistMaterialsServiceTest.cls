@IsTest
private class ScholarFinalistMaterialsServiceTest {
    @IsTest
    static void applicantSubmissionMarksEssayAidAndCurrent() {
        Id appId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000001'
        );
        Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(
            Id = appId,
            Materials_Form_Token__c = 'token'
        );

        Form_Submission__c submission = new Form_Submission__c(
            Id = Id.valueOf(Schema.SObjectType.Form_Submission__c.getKeyPrefix() + '000000000001'),
            RecordTypeId = Schema.SObjectType.Form_Submission__c
                .getRecordTypeInfosByDeveloperName()
                .get(ScholarFinalistMaterialsService.RECORD_TYPE_DEVELOPER_NAME)
                .getRecordTypeId(),
            Prospect_Scholar_Application__c = appId,
            Submission_Token__c = 'token',
            Material_Submission_Type__c = ScholarFinalistMaterialsService.TYPE_APPLICANT,
            Finalist_Essay__c = 'Essay',
            Financial_Aid_Scholarship_Grant_Details__c = 'Aid',
            Coach_Professor_Recommender_Email__c = 'coach@example.com',
            Internship_Supervisor_Recommender_Email__c = 'supervisor@example.com'
        );

        ScholarFinalistMaterialsService.SubmissionProcessingResult result =
            ScholarFinalistMaterialsService.evaluateSubmissions(
            new List<Form_Submission__c>{ submission },
            new Map<Id, Prospect_Scholar_Application__c>{ appId => application }
        );

        System.assertEquals(1, result.submissionUpdates.size());
        System.assertEquals('Processed', result.submissionUpdates[0].Processing_Status__c);
        System.assertEquals(true, result.submissionUpdates[0].Materials_Submission_Current__c);
        System.assertEquals(1, result.applicationUpdates.size());
        System.assertEquals(true, result.applicationUpdates[0].Essay_Received__c);
        System.assertEquals(true, result.applicationUpdates[0].Financial_Aid_Info_Received__c);
        System.assertEquals(2, result.recommendationEmails.size());
    }

    @IsTest
    static void invalidTokenDoesNotThrow() {
        Id appId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000002'
        );
        Form_Submission__c submission = new Form_Submission__c(
            Id = Id.valueOf(Schema.SObjectType.Form_Submission__c.getKeyPrefix() + '000000000003'),
            RecordTypeId = Schema.SObjectType.Form_Submission__c
                .getRecordTypeInfosByDeveloperName()
                .get(ScholarFinalistMaterialsService.RECORD_TYPE_DEVELOPER_NAME)
                .getRecordTypeId(),
            Prospect_Scholar_Application__c = appId,
            Submission_Token__c = 'wrong',
            Material_Submission_Type__c = ScholarFinalistMaterialsService.TYPE_COACH_PROFESSOR
        );

        ScholarFinalistMaterialsService.SubmissionProcessingResult result =
            ScholarFinalistMaterialsService.evaluateSubmissions(
            new List<Form_Submission__c>{ submission },
            new Map<Id, Prospect_Scholar_Application__c>{
                appId => new Prospect_Scholar_Application__c(
                    Id = appId,
                    Materials_Form_Token__c = 'expected'
                )
            }
        );

        System.assertEquals(1, result.submissionUpdates.size());
        System.assertEquals('Needs Review', result.submissionUpdates[0].Processing_Status__c);
        System.assertEquals(true, result.submissionUpdates[0].Needs_Review__c);
        System.assertEquals(false, result.submissionUpdates[0].Materials_Submission_Current__c);
    }

    @IsTest
    static void buildsTokenizedUrls() {
        Id appId = Id.valueOf(
            Schema.SObjectType.Prospect_Scholar_Application__c.getKeyPrefix() + '000000000003'
        );

        String url = ScholarFinalistMaterialsService.buildMaterialsFormUrl(
            appId,
            'abc123',
            ScholarFinalistMaterialsService.TYPE_INTERNSHIP_SUPERVISOR,
            'mentor@example.com'
        );

        System.assert(url.contains('applicationId='));
        System.assert(url.contains('token=abc123'));
        System.assert(url.contains('materialType='));
        System.assert(url.contains('recommenderEmail=mentor%40example.com'));
    }
}
