public with sharing class LeadResumeFileService {
    private static final Integer MAX_RESUME_URLS_PER_LEAD = 5;

    public static void enqueueForLeads(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || newLeads.isEmpty()) {
            return;
        }

        List<Id> leadIds = new List<Id>();
        for (Lead leadRecord : newLeads) {
            if (leadRecord.Id == null || String.isBlank(leadRecord.Primary_Resume_URL__c)) {
                continue;
            }
            if (
                oldMap != null &&
                oldMap.containsKey(leadRecord.Id) &&
                oldMap.get(leadRecord.Id).Primary_Resume_URL__c == leadRecord.Primary_Resume_URL__c
            ) {
                continue;
            }

            leadIds.add(leadRecord.Id);
        }

        if (!leadIds.isEmpty()) {
            System.enqueueJob(new ResumeFileQueueable(leadIds));
        }
    }

    private class ResumeFileQueueable implements Queueable, Database.AllowsCallouts {
        private final List<Id> leadIds;

        private ResumeFileQueueable(List<Id> leadIds) {
            this.leadIds = leadIds;
        }

        public void execute(QueueableContext context) {
            List<Lead> leads = [
                SELECT Id, FirstName, LastName, Primary_Resume_URL__c
                FROM Lead
                WHERE Id IN :leadIds
            ];

            List<ContentVersion> files = new List<ContentVersion>();
            for (Lead leadRecord : leads) {
                List<String> urls = extractUrls(leadRecord.Primary_Resume_URL__c);
                Integer fileIndex = 1;
                for (String resumeUrl : urls) {
                    if (fileIndex > MAX_RESUME_URLS_PER_LEAD) {
                        break;
                    }

                    files.add(buildResumeFile(leadRecord, resumeUrl, fileIndex, urls.size()));
                    fileIndex++;
                }
            }

            if (!files.isEmpty()) {
                insert files;
            }
        }
    }

    @TestVisible
    private static ContentVersion buildResumeFile(
        Lead leadRecord,
        String resumeUrl,
        Integer fileIndex,
        Integer urlCount
    ) {
        DownloadedResume downloadedResume = downloadResume(resumeUrl);
        String title = buildFileTitle(leadRecord, fileIndex, urlCount, downloadedResume.extension);

        return new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = downloadedResume.body,
            FirstPublishLocationId = leadRecord.Id
        );
    }

    @TestVisible
    private static DownloadedResume downloadResume(String resumeUrl) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(resumeUrl);
            request.setMethod('GET');
            request.setTimeout(20000);

            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                String extension = extensionFromContentType(response.getHeader('Content-Type'));
                if (String.isBlank(extension)) {
                    extension = extensionFromUrl(resumeUrl);
                }
                if (String.isBlank(extension)) {
                    extension = 'pdf';
                }

                return new DownloadedResume(response.getBodyAsBlob(), extension);
            }
        } catch (Exception ignored) {
            // If the source host is not allowlisted or the download fails, keep the lead usable
            // by attaching a file that opens the submitted resume URL.
        }

        String html = '<!doctype html><html><body><p>Submitted resume: ' +
            '<a href="' + resumeUrl.escapeHtml4() + '">' + resumeUrl.escapeHtml4() + '</a>' +
            '</p></body></html>';
        return new DownloadedResume(Blob.valueOf(html), 'html');
    }

    @TestVisible
    private static List<String> extractUrls(String resumeUrlValue) {
        List<String> urls = new List<String>();
        if (String.isBlank(resumeUrlValue)) {
            return urls;
        }

        Pattern urlPattern = Pattern.compile('https?://[^\\s,;]+');
        Matcher matcher = urlPattern.matcher(resumeUrlValue);
        while (matcher.find()) {
            String url = matcher.group(0).trim();
            if (!urls.contains(url)) {
                urls.add(url);
            }
        }

        return urls;
    }

    private static String buildFileTitle(
        Lead leadRecord,
        Integer fileIndex,
        Integer urlCount,
        String extension
    ) {
        List<String> nameParts = new List<String>();
        if (!String.isBlank(leadRecord.FirstName)) {
            nameParts.add(leadRecord.FirstName.trim());
        }
        if (!String.isBlank(leadRecord.LastName)) {
            nameParts.add(leadRecord.LastName.trim());
        }

        String applicantName = String.join(nameParts, ' ').trim();
        if (String.isBlank(applicantName)) {
            applicantName = String.valueOf(leadRecord.Id);
        }

        String suffix = urlCount > 1 ? ' ' + String.valueOf(fileIndex) : '';
        return sanitizeFileName('Resume - ' + applicantName + suffix + '.' + extension);
    }

    private static String sanitizeFileName(String fileName) {
        return fileName.replaceAll('[\\\\/:*?"<>|]', '-');
    }

    private static String extensionFromContentType(String contentType) {
        if (String.isBlank(contentType)) {
            return null;
        }

        String normalizedContentType = contentType.toLowerCase();
        if (normalizedContentType.contains('pdf')) {
            return 'pdf';
        }
        if (normalizedContentType.contains('msword')) {
            return 'doc';
        }
        if (normalizedContentType.contains('wordprocessingml')) {
            return 'docx';
        }
        if (normalizedContentType.contains('rtf')) {
            return 'rtf';
        }
        if (normalizedContentType.contains('plain')) {
            return 'txt';
        }

        return null;
    }

    private static String extensionFromUrl(String resumeUrl) {
        if (String.isBlank(resumeUrl)) {
            return null;
        }

        String urlWithoutQuery = resumeUrl.split('\\?')[0];
        Integer lastDotIndex = urlWithoutQuery.lastIndexOf('.');
        if (lastDotIndex < 0 || lastDotIndex == urlWithoutQuery.length() - 1) {
            return null;
        }

        String extension = urlWithoutQuery.substring(lastDotIndex + 1).toLowerCase();
        return Pattern.matches('[a-z0-9]{1,5}', extension) ? extension : null;
    }

    @TestVisible
    private class DownloadedResume {
        private Blob body;
        private String extension;

        private DownloadedResume(Blob body, String extension) {
            this.body = body;
            this.extension = extension;
        }
    }
}