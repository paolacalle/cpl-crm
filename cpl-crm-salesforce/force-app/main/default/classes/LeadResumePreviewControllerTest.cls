@IsTest
private class LeadResumePreviewControllerTest {
    @IsTest
    static void returnsAttachedResumeFileAndUrl() {
        Lead leadRecord = new Lead(
            FirstName = 'Resume',
            LastName = 'Preview',
            Company = 'CPL',
            Status = 'New',
            Primary_Resume_URL__c = 'https://example.com/resume.pdf'
        );
        insert leadRecord;

        ContentVersion version = new ContentVersion(
            Title = 'Resume - Resume Preview.pdf',
            PathOnClient = 'Resume - Resume Preview.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = leadRecord.Id
        );
        insert version;

        Test.startTest();
        LeadResumePreviewController.ResumeInfo info =
            LeadResumePreviewController.getResume(leadRecord.Id);
        Test.stopTest();

        System.assertNotEquals(null, info.contentDocumentId, 'Resume file id should be found');
        System.assertNotEquals(null, info.contentVersionId, 'Resume version should be found');
        System.assertEquals('Resume - Resume Preview.pdf', info.title);
        System.assertEquals('pdf', info.fileExtension);
        System.assertEquals('https://example.com/resume.pdf', info.resumeUrl);
    }

    @IsTest
    static void returnsUrlOnlyWhenNoFile() {
        Lead leadRecord = new Lead(
            FirstName = 'No',
            LastName = 'File',
            Company = 'CPL',
            Status = 'New',
            Primary_Resume_URL__c = 'https://example.com/only-url.pdf'
        );
        insert leadRecord;

        LeadResumePreviewController.ResumeInfo info =
            LeadResumePreviewController.getResume(leadRecord.Id);

        System.assertEquals(null, info.contentVersionId);
        System.assertEquals('https://example.com/only-url.pdf', info.resumeUrl);
    }

    @IsTest
    static void nullLeadReturnsEmptyInfo() {
        LeadResumePreviewController.ResumeInfo info =
            LeadResumePreviewController.getResume(null);
        System.assertEquals(null, info.contentVersionId);
        System.assertEquals(null, info.resumeUrl);
    }
}
