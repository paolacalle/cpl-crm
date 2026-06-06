public with sharing class LeadResumePreviewController {
    @AuraEnabled(cacheable=true)
    public static ResumeInfo getResume(Id leadId) {
        ResumeInfo info = new ResumeInfo();
        if (leadId == null) {
            return info;
        }

        for (Lead leadRecord : [
            SELECT Primary_Resume_URL__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ]) {
            info.resumeUrl = leadRecord.Primary_Resume_URL__c;
        }

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :leadId
        ]) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        if (contentDocumentIds.isEmpty()) {
            return info;
        }

        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
            AND Title LIKE 'Resume%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ]) {
            info.contentDocumentId = version.ContentDocumentId;
            info.contentVersionId = version.Id;
            info.title = version.Title;
            info.fileExtension = version.FileExtension == null
                ? null
                : version.FileExtension.toLowerCase();
        }

        return info;
    }

    public class ResumeInfo {
        @AuraEnabled
        public String contentDocumentId;
        @AuraEnabled
        public String contentVersionId;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String fileExtension;
        @AuraEnabled
        public String resumeUrl;
    }
}
