public with sharing class LeadContactingCheckpointAction {
    private static final String CONTACTING_TITLE = 'Lead Stage : Contacting';
    private static final List<String> CONTACTING_TOPICS = new List<String>{
        'Automated Note',
        'Contacting',
        'Lead Stage'
    };

    @InvocableMethod(label='Save Lead Contacting Checkpoint')
    public static List<Result> saveCheckpoints(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        List<Task> tasksToInsert = new List<Task>();

        for (Request request : requests) {
            if (request == null || request.leadId == null) {
                throw new AuraHandledException('Lead is required.');
            }
            Id interactionId = request.submittedInteractionId;
            if (interactionId == null && !String.isBlank(request.note)) {
                interactionId = StructuredInteractionController.saveInteraction(
                    null,
                    request.leadId,
                    CONTACTING_TITLE,
                    Date.today(),
                    request.note,
                    new List<Id>(),
                    CONTACTING_TOPICS
                );
            }

            if (request.markInitialContactEmailSent == true) {
                leadsToUpdate.add(
                    new Lead(
                        Id = request.leadId,
                        Initial_Contact_Email_Sent__c = true
                    )
                );
            }

            if (request.createFollowUpTask == true) {
                tasksToInsert.add(
                    new Task(
                        WhoId = request.leadId,
                        Subject = String.isBlank(request.followUpTaskSubject)
                            ? 'Follow up with lead'
                            : request.followUpTaskSubject.trim(),
                        ActivityDate = request.followUpTaskDueDate,
                        Status = 'Not Started',
                        Priority = 'Normal',
                        Description = request.followUpTaskNotes
                    )
                );
            }

            Result result = new Result();
            result.interactionId = interactionId;
            results.add(result);
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }

        return results;
    }

    @AuraEnabled
    public static Id createFollowUpTask(Id leadId, String subject, Date dueDate, String notes) {
        if (leadId == null) {
            throw new AuraHandledException('Lead is required.');
        }

        Task taskRecord = new Task(
            WhoId = leadId,
            Subject = String.isBlank(subject) ? 'Follow up with lead' : subject.trim(),
            ActivityDate = dueDate,
            Status = 'Not Started',
            Priority = 'Normal',
            Description = notes
        );
        insert taskRecord;
        return taskRecord.Id;
    }

    @AuraEnabled
    public static void markInitialContactEmailSent(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead is required.');
        }

        update new Lead(
            Id = leadId,
            Initial_Contact_Email_Sent__c = true
        );
    }

    @AuraEnabled
    public static void sendInitialContactEmail(Id leadId, String subject, String body) {
        if (leadId == null) {
            throw new AuraHandledException('Lead is required.');
        }
        if (String.isBlank(subject)) {
            throw new AuraHandledException('Email subject is required.');
        }
        if (String.isBlank(body)) {
            throw new AuraHandledException('Email message is required.');
        }

        Lead leadRecord = [
            SELECT Id, Email
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (String.isBlank(leadRecord.Email)) {
            throw new AuraHandledException('This lead does not have an email address.');
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(leadRecord.Id);
        email.setSaveAsActivity(true);
        email.setSubject(subject.trim());
        email.setPlainTextBody(body);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        markInitialContactEmailSent(leadRecord.Id);
    }

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable
        public String note;

        @InvocableVariable
        public Id submittedInteractionId;

        @InvocableVariable
        public Boolean markInitialContactEmailSent;

        @InvocableVariable
        public Boolean createFollowUpTask;

        @InvocableVariable
        public String followUpTaskSubject;

        @InvocableVariable
        public Date followUpTaskDueDate;

        @InvocableVariable
        public String followUpTaskNotes;
    }

    public class Result {
        @InvocableVariable
        public Id interactionId;
    }
}