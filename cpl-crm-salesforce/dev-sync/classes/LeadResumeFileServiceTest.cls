@IsTest
private class LeadResumeFileServiceTest {
    private class ResumePdfMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/pdf');
            response.setBody('fake pdf');
            return response;
        }
    }

    private class ResumeFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(403);
            response.setBody('forbidden');
            return response;
        }
    }

    private class GenericDownloadMock implements HttpCalloutMock {
        private final String contentType;

        private GenericDownloadMock(String contentType) {
            this.contentType = contentType;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', contentType);
            response.setBody('downloaded');
            return response;
        }
    }

    @IsTest
    static void createsDownloadedResumeFileForNewLead() {
        Test.setMock(HttpCalloutMock.class, new ResumePdfMock());

        Test.startTest();
        Lead leadRecord = new Lead(
            FirstName = 'Ari',
            LastName = 'Applicant',
            Company = 'CPL',
            Status = 'New',
            Primary_Resume_URL__c = 'https://files.example.com/resume.pdf',
            Resume_Uploaded__c = true
        );
        insert leadRecord;
        Test.stopTest();

        ContentVersion resumeFile = [
            SELECT Title, PathOnClient, VersionData
            FROM ContentVersion
            WHERE FirstPublishLocationId = :leadRecord.Id
            LIMIT 1
        ];

        System.assertEquals('Resume - Ari Applicant.pdf', resumeFile.Title);
        System.assertEquals('Resume - Ari Applicant.pdf', resumeFile.PathOnClient);
        System.assertEquals('fake pdf', resumeFile.VersionData.toString());
    }

    @IsTest
    static void createsLinkFileWhenRemoteResumeCannotBeDownloaded() {
        Test.setMock(HttpCalloutMock.class, new ResumeFailureMock());

        Test.startTest();
        Lead leadRecord = new Lead(
            FirstName = 'Blair',
            LastName = 'Backup',
            Company = 'CPL',
            Status = 'New',
            Primary_Resume_URL__c = 'https://files.example.com/private-resume',
            Resume_Uploaded__c = true
        );
        insert leadRecord;
        Test.stopTest();

        ContentVersion resumeFile = [
            SELECT Title, VersionData
            FROM ContentVersion
            WHERE FirstPublishLocationId = :leadRecord.Id
            LIMIT 1
        ];

        System.assertEquals('Resume - Blair Backup.html', resumeFile.Title);
        System.assert(resumeFile.VersionData.toString().contains('https://files.example.com/private-resume'));
    }

    @IsTest
    static void extractsMultipleResumeUrls() {
        List<String> urls = LeadResumeFileService.extractUrls(
            'https://example.com/a.pdf; https://example.com/b.docx'
        );

        System.assertEquals(2, urls.size());
        System.assertEquals('https://example.com/a.pdf', urls[0]);
        System.assertEquals('https://example.com/b.docx', urls[1]);
    }

    @IsTest
    static void limitsMultipleResumeUrlsToFiveFiles() {
        Test.setMock(HttpCalloutMock.class, new ResumePdfMock());

        Test.startTest();
        Lead leadRecord = new Lead(
            FirstName = 'Casey',
            LastName = 'Many',
            Company = 'CPL',
            Status = 'New',
            Primary_Resume_URL__c =
                'https://example.com/1.pdf; https://example.com/2.pdf; https://example.com/3.pdf; ' +
                'https://example.com/4.pdf; https://example.com/5.pdf; https://example.com/6.pdf',
            Resume_Uploaded__c = true
        );
        insert leadRecord;
        Test.stopTest();

        Integer fileCount = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE FirstPublishLocationId = :leadRecord.Id
        ];
        System.assertEquals(5, fileCount);
    }

    @IsTest
    static void usesUrlExtensionWhenContentTypeIsGeneric() {
        Test.setMock(HttpCalloutMock.class, new GenericDownloadMock('application/octet-stream'));

        ContentVersion resumeFile = LeadResumeFileService.buildResumeFile(
            new Lead(
                Id = Id.valueOf(Schema.SObjectType.Lead.getKeyPrefix() + '000000000001'),
                LastName = 'UrlExtension'
            ),
            'https://example.com/resume.docx?download=1',
            1,
            1
        );

        System.assertEquals('Resume - UrlExtension.docx', resumeFile.Title);
    }

    @IsTest
    static void defaultsToPdfWhenContentTypeAndUrlDoNotRevealType() {
        Test.setMock(HttpCalloutMock.class, new GenericDownloadMock('application/octet-stream'));

        ContentVersion resumeFile = LeadResumeFileService.buildResumeFile(
            new Lead(
                Id = Id.valueOf(Schema.SObjectType.Lead.getKeyPrefix() + '000000000002'),
                LastName = 'Default'
            ),
            'https://example.com/download',
            1,
            1
        );

        System.assertEquals('Resume - Default.pdf', resumeFile.Title);
    }

    @IsTest
    static void skipsBlankAndUnchangedResumeUrls() {
        Lead noUrl = new Lead(
            Id = Id.valueOf(Schema.SObjectType.Lead.getKeyPrefix() + '000000000003'),
            LastName = 'No Url'
        );
        Lead unchanged = new Lead(
            Id = Id.valueOf(Schema.SObjectType.Lead.getKeyPrefix() + '000000000004'),
            LastName = 'Same',
            Primary_Resume_URL__c = 'https://example.com/same.pdf'
        );

        Test.startTest();
        LeadResumeFileService.enqueueForLeads(null, null);
        LeadResumeFileService.enqueueForLeads(new List<Lead>(), null);
        LeadResumeFileService.enqueueForLeads(
            new List<Lead>{ noUrl, unchanged },
            new Map<Id, Lead>{
                unchanged.Id => new Lead(
                    Id = unchanged.Id,
                    Primary_Resume_URL__c = 'https://example.com/same.pdf'
                )
            }
        );
        Test.stopTest();

        System.assertEquals(0, Limits.getQueueableJobs());
    }
}