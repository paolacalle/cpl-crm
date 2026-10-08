@IsTest
private class MCPInteractionFlowsTest {
    @TestSetup
    static void setupRecords() {
        insert new Contact(LastName = 'MCP Flow Test');
        insert new Lead(LastName = 'MCP Flow Test', Company = 'CPL', Status = 'New');
        insert new List<Topic__c>{
            new Topic__c(Name = 'MCP Active A', Active__c = true),
            new Topic__c(Name = 'MCP Active B', Active__c = true),
            new Topic__c(Name = 'MCP Retired', Active__c = false)
        };
    }

    private static Map<String, Object> createInputs() {
        return new Map<String, Object>{
            'contactId' => String.valueOf([SELECT Id FROM Contact LIMIT 1].Id),
            'title' => 'Employment follow-up',
            'note' => 'Discussed the next application step.',
            'interactionDate' => Date.today()
        };
    }

    private static Flow.Interview runFlow(String name, Map<String, Object> inputs) {
        Flow.Interview interview = Flow.Interview.createInterview(name, inputs);
        interview.start();
        return interview;
    }

    private static void assertFailure(Flow.Interview interview) {
        Assert.areEqual(false, interview.getVariableValue('isSuccess'));
        Assert.isTrue(String.isNotBlank((String) interview.getVariableValue('errorMessage')));
    }

    @IsTest
    static void createsContactNoteAndDeduplicatesTopics() {
        List<Topic__c> topics = [SELECT Id FROM Topic__c WHERE Active__c = true ORDER BY Name];
        Map<String, Object> inputs = createInputs();
        inputs.put('topicIds', new List<String>{String.valueOf(topics[0].Id), String.valueOf(topics[1].Id), String.valueOf(topics[0].Id)});
        Test.startTest();
        Flow.Interview result = runFlow('MCP_Create_Interaction_Note', inputs);
        Test.stopTest();
        Assert.areEqual(true, result.getVariableValue('isSuccess'));
        Id createdId = (String) result.getVariableValue('interactionId');
        Interaction__c saved = [SELECT Contact__c, Lead__c, Title__c, Note__c, Interaction_Date__c FROM Interaction__c WHERE Id = :createdId];
        Assert.areEqual(inputs.get('contactId'), String.valueOf(saved.Contact__c));
        Assert.isNull(saved.Lead__c);
        Assert.areEqual(inputs.get('title'), saved.Title__c);
        Assert.areEqual(inputs.get('note'), saved.Note__c);
        Assert.areEqual(inputs.get('interactionDate'), saved.Interaction_Date__c);
        Assert.areEqual(2, [SELECT COUNT() FROM InteractionTopic__c WHERE Interaction__c = :createdId]);
        Assert.areEqual(3, [SELECT COUNT() FROM Topic__c], 'No reusable topics are created.');
        Assert.areEqual(Decimal.valueOf('2'), result.getVariableValue('topicCount'));
    }

    @IsTest
    static void acceptsFifteenCharacterTopicIds() {
        String topicId = String.valueOf([SELECT Id FROM Topic__c WHERE Active__c = true LIMIT 1].Id);
        Map<String, Object> inputs = createInputs();
        inputs.put('topicIds', new List<String>{topicId.substring(0, 15), topicId});
        Test.startTest();
        Flow.Interview result = runFlow('MCP_Create_Interaction_Note', inputs);
        Test.stopTest();
        Assert.areEqual(true, result.getVariableValue('isSuccess'));
        Assert.areEqual(1, [SELECT COUNT() FROM InteractionTopic__c]);
    }

    @IsTest
    static void rejectsWhitespaceOnlyContent() {
        Map<String, Object> inputs = createInputs();
        inputs.put('note', '   ');
        Test.startTest();
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Interaction__c]);
    }

    @IsTest
    static void createsLeadNoteWithoutLabels() {
        Map<String, Object> inputs = createInputs();
        inputs.remove('contactId');
        Id leadId = [SELECT Id FROM Lead LIMIT 1].Id;
        inputs.put('leadId', String.valueOf(leadId));
        Test.startTest();
        Flow.Interview result = runFlow('MCP_Create_Interaction_Note', inputs);
        Test.stopTest();
        Assert.areEqual(true, result.getVariableValue('isSuccess'));
        Interaction__c saved = [SELECT Contact__c, Lead__c FROM Interaction__c LIMIT 1];
        Assert.areEqual(leadId, saved.Lead__c);
        Assert.isNull(saved.Contact__c);
        Assert.areEqual(0, [SELECT COUNT() FROM InteractionTopic__c]);
    }

    @IsTest
    static void rejectsInactiveTopicBeforeAnyWrites() {
        Map<String, Object> inputs = createInputs();
        inputs.put('topicIds', new List<String>{String.valueOf([SELECT Id FROM Topic__c WHERE Active__c = false LIMIT 1].Id)});
        Test.startTest();
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Interaction__c]);
        Assert.areEqual(0, [SELECT COUNT() FROM InteractionTopic__c]);
    }

    @IsTest
    static void rejectsWrongTopicTypeAndBothParents() {
        Map<String, Object> inputs = createInputs();
        inputs.put('topicIds', new List<String>{(String) inputs.get('contactId')});
        Test.startTest();
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        inputs.remove('topicIds');
        inputs.put('leadId', String.valueOf([SELECT Id FROM Lead LIMIT 1].Id));
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Interaction__c]);
    }

    @IsTest
    static void rejectsMissingRequiredFieldsAndParent() {
        Map<String, Object> inputs = createInputs();
        String originalTitle = (String) inputs.get('title');
        inputs.put('title', '');
        Test.startTest();
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        inputs.put('title', originalTitle);
        inputs.put('contactId', String.valueOf([SELECT Id FROM Lead LIMIT 1].Id));
        assertFailure(runFlow('MCP_Create_Interaction_Note', inputs));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Interaction__c]);
    }

    private static Interaction__c existingNote() {
        Interaction__c record = new Interaction__c(
            Contact__c = [SELECT Id FROM Contact LIMIT 1].Id,
            Title__c = 'Original title', Note__c = 'Original content',
            Interaction_Date__c = Date.today().addDays(-2)
        );
        insert record;
        insert new InteractionTopic__c(Interaction__c = record.Id, Topic__c = [SELECT Id FROM Topic__c WHERE Active__c = true LIMIT 1].Id);
        return record;
    }

    @IsTest
    static void updatesTitlePreservingContentParentAndLinks() {
        Interaction__c original = existingNote();
        Id linkId = [SELECT Id FROM InteractionTopic__c LIMIT 1].Id;
        Test.startTest();
        Flow.Interview result = runFlow('MCP_Update_Interaction_Note', new Map<String, Object>{'interactionId' => String.valueOf(original.Id), 'title' => 'Corrected title'});
        Test.stopTest();
        Assert.areEqual(true, result.getVariableValue('isSuccess'));
        Interaction__c saved = [SELECT Title__c, Note__c, Contact__c, Interaction_Date__c FROM Interaction__c WHERE Id = :original.Id];
        Assert.areEqual('Corrected title', saved.Title__c);
        Assert.areEqual(original.Note__c, saved.Note__c);
        Assert.areEqual(original.Contact__c, saved.Contact__c);
        Assert.areEqual(original.Interaction_Date__c, saved.Interaction_Date__c);
        Assert.areEqual(linkId, [SELECT Id FROM InteractionTopic__c LIMIT 1].Id);
    }

    @IsTest
    static void updatesContentAndDateButBlankTitlePreserves() {
        Interaction__c original = existingNote();
        Test.startTest();
        Flow.Interview result = runFlow('MCP_Update_Interaction_Note', new Map<String, Object>{'interactionId' => String.valueOf(original.Id), 'title' => '', 'note' => 'Revised content', 'interactionDate' => Date.today()});
        Test.stopTest();
        Assert.areEqual(true, result.getVariableValue('isSuccess'));
        Interaction__c saved = [SELECT Title__c, Note__c, Interaction_Date__c FROM Interaction__c WHERE Id = :original.Id];
        Assert.areEqual(original.Title__c, saved.Title__c);
        Assert.areEqual('Revised content', saved.Note__c);
        Assert.areEqual(Date.today(), saved.Interaction_Date__c);
    }

    @IsTest
    static void rejectsNoChangeAndMissingRecord() {
        Interaction__c original = existingNote();
        Test.startTest();
        assertFailure(runFlow('MCP_Update_Interaction_Note', new Map<String, Object>{'interactionId' => String.valueOf(original.Id)}));
        assertFailure(runFlow('MCP_Update_Interaction_Note', new Map<String, Object>{'interactionId' => String.valueOf(original.Contact__c), 'title' => 'Do not save'}));
        Test.stopTest();
        Assert.areEqual(original.Title__c, [SELECT Title__c FROM Interaction__c WHERE Id = :original.Id].Title__c);
    }
}
