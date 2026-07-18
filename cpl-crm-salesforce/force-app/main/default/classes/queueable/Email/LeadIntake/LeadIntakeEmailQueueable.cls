/**
 * @description Asynchronous Queueable worker responsible for compiling and dispatching
 * transactional notification emails to the intake teams when new leads enter the pipeline.
 *
 * @group Queueables
 */
public with sharing class LeadIntakeEmailQueueable implements Queueable {
    private final List<Id> leadIds;

    public LeadIntakeEmailQueueable(List<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext context) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        Id orgWideEmailId = OrgWideEmailUtil.getIntakeOrgWideEmailId();
        Set<String> recipientEmails = LeadIntakeNotificationService.getTeamEmails();

        if (recipientEmails.isEmpty()) {
            // Log exception/warning to your internal framework or debug log here
            System.debug(LoggingLevel.WARN, 'LeadIntakeEmailQueueable: No recipient emails found for the intake groups.');
            return;
        }

        // query the actual Lead data payload needed for the email templates
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Name, Email, RecordType.DeveloperName
            FROM Lead
            WHERE Id IN :leadIds
        ];

        if (leads.isEmpty()) {
            return;
        }

        // load resumes
        Map<Id, List<ContentVersion>> resumesByLead = loadResumes(leadIds);
        List<String> toAddressesList = new List<String>(recipientEmails);

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Lead ld : leads) {
            messages.add(buildMsg(ld, toAddressesList, orgWideEmailId, resumesByLead.get(ld.Id)));
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    // Map each lead to its already-attached resume file(s) (already created by LeadResumeFileService).
    @TestVisible
    private static Map<Id, List<ContentVersion>> loadResumes(List<Id> leadIds) {
        Map<Id, List<ContentVersion>> byLead = new Map<Id, List<ContentVersion>>();
        Map<Id, Id> leadByDoc = new Map<Id, Id>();

        // document -> id 
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :leadIds
        ]) {
            leadByDoc.put(link.ContentDocumentId, link.LinkedEntityId);
        }

        if (leadByDoc.isEmpty()) {
            return byLead;
        }

        // id -> document list 
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :leadByDoc.keySet()
                AND IsLatest = true
                AND Title LIKE '%Resume%'
            ORDER BY CreatedDate ASC
        ]) {
            Id ldId = leadByDoc.get(cv.ContentDocumentId);
            if (!byLead.containsKey(ldId)) {
                byLead.put(ldId, new List<ContentVersion>());
            }
            byLead.get(ldId).add(cv);
        }

        return byLead;
    }

    @TestVisible
    private static Messaging.SingleEmailMessage buildMsg(
        Lead ld,
        List<String> toAddresses,
        Id orgWideId,
        List<ContentVersion> documents
    ) {
        Boolean isPartner = ld.RecordType != null
            && 'Partner_Lead'.equals(ld.RecordType.DeveloperName);

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(toAddresses);
        msg.setSaveAsActivity(false);
        if (orgWideId != null) {
            msg.setOrgWideEmailAddressId(orgWideId);
        }

        List<Messaging.EmailFileAttachment> atts = new List<Messaging.EmailFileAttachment>();
        atts.add(buildPdfAttachment(ld));

        if (isPartner) {
            msg.setSubject('New CPL Partner Lead: ' + ld.Name);
            msg.setHtmlBody(buildPartnerBody(ld));
        } else {
            msg.setSubject('New CPL Scholar Interest Lead: ' + ld.Name);
            msg.setHtmlBody(buildScholarBody(ld));

            // append the resume / pdfs
            if (documents != null) {
                for (ContentVersion cv : documents) {
                    Messaging.EmailFileAttachment ra = new Messaging.EmailFileAttachment();
                    ra.setFileName(cv.Title +
                        (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : ''));
                    ra.setBody(cv.VersionData);
                    atts.add(ra);
                }
            }
        }

        msg.setFileAttachments(atts);
        return msg;
    }

    private static Messaging.EmailFileAttachment buildPdfAttachment(Lead ld) {
        PageReference pdfPage = Page.LeadIntakeSummaryPdf;
        pdfPage.getParameters().put('id', ld.Id);

        // getContentAsPDF() is unstable/blank in test context — use a placeholder there.
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF-PLACEHOLDER')
            : pdfPage.getContentAsPDF();

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName('Lead Summary - ' + ld.Name + '.pdf');
        att.setContentType('application/pdf');
        att.setBody(pdfBlob);
        return att;
    }

    @TestVisible
    private static String buildScholarBody(Lead ld) {
        String name = ld.Name == null ? '' : ld.Name.escapeHtml4();
        return '<p>A new <strong>CPL Scholar Lead</strong> has been created: <strong>'
            + name + '</strong>.</p>'
            + '<p>The full lead summary (PDF) and the applicant\'s resume are attached. '
            + 'Please review and begin intake.</p>';
    }

    @TestVisible
    private static String buildPartnerBody(Lead ld) {
        String name = ld.Name == null ? '' : ld.Name.escapeHtml4();
        return '<p>A new <strong>Partner Lead</strong> has been created: <strong>'
            + name + '</strong>.</p>'
            + '<p>The full lead summary (PDF) is attached. Please review and begin outreach.</p>';
    }

}