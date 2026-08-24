@IsTest
private class LeadReviewApplicationNoteActionTest {
    @IsTest
    static void savesReviewNoteWithTopics() {
        Lead leadRecord = new Lead(
            FirstName = 'Review',
            LastName = 'Note',
            Company = 'CPL',
            Status = 'New'
        );
        insert leadRecord;

        LeadReviewApplicationNoteAction.Request request =
            new LeadReviewApplicationNoteAction.Request();
        request.leadId = leadRecord.Id;
        request.note = 'Strong application. Ask about leadership examples.';

        Test.startTest();
        List<LeadReviewApplicationNoteAction.Result> results =
            LeadReviewApplicationNoteAction.saveNotes(
                new List<LeadReviewApplicationNoteAction.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].interactionId);

        Interaction__c interactionRecord = [
            SELECT Lead__c, Title__c, Note__c
            FROM Interaction__c
            WHERE Id = :results[0].interactionId
        ];
        System.assertEquals(leadRecord.Id, interactionRecord.Lead__c);
        System.assertEquals(
            'Lead Stage : Review of application',
            interactionRecord.Title__c
        );
        System.assertEquals(request.note, interactionRecord.Note__c);

        List<InteractionTopic__c> topicLinks = [
            SELECT Topic__r.Name
            FROM InteractionTopic__c
            WHERE Interaction__c = :interactionRecord.Id
            ORDER BY Topic__r.Name
        ];
        System.assertEquals(4, topicLinks.size());
        System.assertEquals('Automated Note', topicLinks[0].Topic__r.Name);
        System.assertEquals('Lead Stage', topicLinks[1].Topic__r.Name);
        System.assertEquals('New to Contacting', topicLinks[2].Topic__r.Name);
        System.assertEquals(
            'Review of Initial Application',
            topicLinks[3].Topic__r.Name
        );
    }

    @IsTest
    static void rejectsBlankNote() {
        LeadReviewApplicationNoteAction.Request request =
            new LeadReviewApplicationNoteAction.Request();
        request.leadId = UserInfo.getUserId();
        request.note = '';

        try {
            LeadReviewApplicationNoteAction.saveNotes(
                new List<LeadReviewApplicationNoteAction.Request>{ request }
            );
            System.assert(false, 'Expected blank note to be rejected.');
        } catch (AuraHandledException expected) {
            System.assertNotEquals(null, expected);
        }
    }
}
