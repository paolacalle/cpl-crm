@IsTest
private class LeadContactingCheckpointActionTest {
    @IsTest
    static void savesNoteMarksEmailAndCreatesTask() {
        Lead leadRecord = new Lead(
            FirstName = 'Active',
            LastName = 'Contacting',
            Company = 'CPL',
            Status = 'Contacting',
            Initial_Contact_Email_Sent__c = false
        );
        insert leadRecord;

        LeadContactingCheckpointAction.Request request =
            new LeadContactingCheckpointAction.Request();
        request.leadId = leadRecord.Id;
        request.note = 'Sent email and will follow up next week.';
        request.markInitialContactEmailSent = true;
        request.createFollowUpTask = true;
        request.followUpTaskSubject = 'Call scholar lead';
        request.followUpTaskDueDate = Date.today().addDays(7);
        request.followUpTaskNotes = 'Ask about availability.';

        Test.startTest();
        List<LeadContactingCheckpointAction.Result> results =
            LeadContactingCheckpointAction.saveCheckpoints(
                new List<LeadContactingCheckpointAction.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].interactionId);

        Lead updatedLead = [
            SELECT Initial_Contact_Email_Sent__c
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(true, updatedLead.Initial_Contact_Email_Sent__c);

        Interaction__c interactionRecord = [
            SELECT Lead__c, Title__c, Note__c
            FROM Interaction__c
            WHERE Id = :results[0].interactionId
        ];
        System.assertEquals(leadRecord.Id, interactionRecord.Lead__c);
        System.assertEquals('Lead Stage : Contacting', interactionRecord.Title__c);
        System.assertEquals(request.note, interactionRecord.Note__c);

        List<InteractionTopic__c> topicLinks = [
            SELECT Topic__r.Name
            FROM InteractionTopic__c
            WHERE Interaction__c = :interactionRecord.Id
            ORDER BY Topic__r.Name
        ];
        System.assertEquals(3, topicLinks.size());
        System.assertEquals('Automated Note', topicLinks[0].Topic__r.Name);
        System.assertEquals('Contacting', topicLinks[1].Topic__r.Name);
        System.assertEquals('Lead Stage', topicLinks[2].Topic__r.Name);

        Task followUpTask = [
            SELECT Subject, ActivityDate, Status, Priority, Description, WhoId
            FROM Task
            WHERE WhoId = :leadRecord.Id AND Subject = 'Call scholar lead'
            LIMIT 1
        ];
        System.assertEquals(Date.today().addDays(7), followUpTask.ActivityDate);
        System.assertEquals('Not Started', followUpTask.Status);
        System.assertEquals('Normal', followUpTask.Priority);
        System.assertEquals('Ask about availability.', followUpTask.Description);
    }

    @IsTest
    static void allowsMissingNote() {
        Lead leadRecord = new Lead(
            FirstName = 'No',
            LastName = 'Note',
            Company = 'CPL',
            Status = 'Contacting'
        );
        insert leadRecord;

        LeadContactingCheckpointAction.Request request =
            new LeadContactingCheckpointAction.Request();
        request.leadId = leadRecord.Id;
        request.note = '';

        Test.startTest();
        List<LeadContactingCheckpointAction.Result> results =
            LeadContactingCheckpointAction.saveCheckpoints(
                new List<LeadContactingCheckpointAction.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(null, results[0].interactionId);
        System.assertEquals(0, [
            SELECT COUNT()
            FROM Interaction__c
            WHERE Lead__c = :leadRecord.Id
        ]);
    }

    @IsTest
    static void skipsDuplicateNoteWhenSubmittedInteractionProvided() {
        Lead leadRecord = new Lead(
            FirstName = 'Submitted',
            LastName = 'Note',
            Company = 'CPL',
            Status = 'Contacting'
        );
        insert leadRecord;

        Id submittedInteractionId = StructuredInteractionController.saveInteraction(
            null,
            leadRecord.Id,
            'Lead Stage : Contacting',
            Date.today(),
            'Already submitted from the Flow component.',
            new List<Id>(),
            new List<String>{ 'Automated Note', 'Contacting', 'Lead Stage' }
        );

        LeadContactingCheckpointAction.Request request =
            new LeadContactingCheckpointAction.Request();
        request.leadId = leadRecord.Id;
        request.note = '';
        request.submittedInteractionId = submittedInteractionId;

        Test.startTest();
        List<LeadContactingCheckpointAction.Result> results =
            LeadContactingCheckpointAction.saveCheckpoints(
                new List<LeadContactingCheckpointAction.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(submittedInteractionId, results[0].interactionId);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Interaction__c
            WHERE Lead__c = :leadRecord.Id
        ]);
    }

    @IsTest
    static void directSubmitMethodsCreateTaskMarkSentAndSendEmail() {
        Lead leadRecord = new Lead(
            FirstName = 'Direct',
            LastName = 'Submit',
            Company = 'CPL',
            Status = 'Contacting',
            Email = 'direct.submit@example.com',
            Initial_Contact_Email_Sent__c = false
        );
        insert leadRecord;

        Test.startTest();
        Id taskId = LeadContactingCheckpointAction.createFollowUpTask(
            leadRecord.Id,
            'Direct submit task',
            Date.today().addDays(3),
            'Created from the Flow task submit button.'
        );
        LeadContactingCheckpointAction.markInitialContactEmailSent(leadRecord.Id);
        LeadContactingCheckpointAction.sendInitialContactEmail(
            leadRecord.Id,
            'Initial contact',
            'Hello from CPL.'
        );
        Test.stopTest();

        Task taskRecord = [
            SELECT WhoId, Subject, ActivityDate, Description
            FROM Task
            WHERE Id = :taskId
        ];
        System.assertEquals(leadRecord.Id, taskRecord.WhoId);
        System.assertEquals('Direct submit task', taskRecord.Subject);
        System.assertEquals(Date.today().addDays(3), taskRecord.ActivityDate);
        System.assertEquals('Created from the Flow task submit button.', taskRecord.Description);

        Lead updatedLead = [
            SELECT Initial_Contact_Email_Sent__c
            FROM Lead
            WHERE Id = :leadRecord.Id
        ];
        System.assertEquals(true, updatedLead.Initial_Contact_Email_Sent__c);
    }
}
