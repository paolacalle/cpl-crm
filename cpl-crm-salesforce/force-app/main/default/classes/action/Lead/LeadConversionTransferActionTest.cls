@IsTest
private class LeadConversionTransferActionTest {
    private static String firstActivePicklistValue(Schema.SObjectField fieldRef) {
        for (Schema.PicklistEntry picklistEntry : fieldRef.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    @IsTest
    static void transfersInteractionsAndActivitiesToConvertedContact() {
        String primarySport = firstActivePicklistValue(Lead.Primary_Sport__c);
        String collegeYear = firstActivePicklistValue(Lead.College_Year__c);
        String leadSource = firstActivePicklistValue(Lead.LeadSource);

        Lead leadRecord = new Lead(
            FirstName = 'Convert',
            LastName = 'Transfer',
            Company = 'CPL',
            Status = 'Decision',
            Email = 'convert.transfer@example.com',
            Primary_Sport__c = primarySport,
            College_Year__c = collegeYear,
            LeadSource = leadSource,
            Why_CPL_Scholar__c = 'CPL aligns with my goals.',
            Commits_to_CPL_mantra__c = true
        );
        insert leadRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Converted',
            LastName = 'Member',
            Email = 'convert.transfer@example.com'
        );
        insert contactRecord;

        Interaction__c interactionRecord = new Interaction__c(
            Lead__c = leadRecord.Id,
            Title__c = 'Lead Stage : Contacting',
            Note__c = 'Important conversion note.',
            Interaction_Date__c = Date.today()
        );
        insert interactionRecord;

        Task taskRecord = new Task(
            WhoId = leadRecord.Id,
            Subject = 'Lead follow up',
            Status = 'Not Started',
            Priority = 'Normal'
        );
        insert taskRecord;

        Event eventRecord = new Event(
            WhoId = leadRecord.Id,
            Subject = 'Lead meeting',
            StartDateTime = System.now().addDays(1),
            EndDateTime = System.now().addDays(1).addHours(1)
        );
        insert eventRecord;

        LeadConversionTransferAction.Request request =
            new LeadConversionTransferAction.Request();
        request.leadId = leadRecord.Id;
        request.convertedContactId = contactRecord.Id;

        Test.startTest();
        LeadConversionTransferAction.transfer(
            new List<LeadConversionTransferAction.Request>{ request }
        );
        LeadConversionTransferAction.transfer(new List<LeadConversionTransferAction.Request>());
        LeadConversionTransferAction.transfer(null);
        Test.stopTest();

        Interaction__c updatedInteraction = [
            SELECT Lead__c, Contact__c
            FROM Interaction__c
            WHERE Id = :interactionRecord.Id
        ];
        System.assertEquals(null, updatedInteraction.Lead__c);
        System.assertEquals(contactRecord.Id, updatedInteraction.Contact__c);

        Task updatedTask = [SELECT WhoId FROM Task WHERE Id = :taskRecord.Id];
        System.assertEquals(contactRecord.Id, updatedTask.WhoId);

        Event updatedEvent = [SELECT WhoId FROM Event WHERE Id = :eventRecord.Id];
        System.assertEquals(contactRecord.Id, updatedEvent.WhoId);

        Contact updatedContact = [
            SELECT Source_Lead_Object__c, Primary_Sport__c, College_Year__c,
                LeadSource, Why_CPL__c, Commits_to_CPL_mantra__c
            FROM Contact
            WHERE Id = :contactRecord.Id
        ];
        System.assertEquals(leadRecord.Id, updatedContact.Source_Lead_Object__c);
        System.assertEquals(primarySport, updatedContact.Primary_Sport__c);
        System.assertEquals(collegeYear, updatedContact.College_Year__c);
        System.assertEquals(leadSource, updatedContact.LeadSource);
        System.assertEquals('CPL aligns with my goals.', updatedContact.Why_CPL__c);
        System.assertEquals(true, updatedContact.Commits_to_CPL_mantra__c);
    }

    @IsTest
    static void ignoresIncompleteRequests() {
        Lead leadRecord = new Lead(
            FirstName = 'Incomplete',
            LastName = 'Request',
            Company = 'CPL',
            Status = 'Decision'
        );
        insert leadRecord;

        Interaction__c interactionRecord = new Interaction__c(
            Lead__c = leadRecord.Id,
            Title__c = 'Lead Stage : Contacting',
            Note__c = 'Should stay on lead.',
            Interaction_Date__c = Date.today()
        );
        insert interactionRecord;

        LeadConversionTransferAction.Request request =
            new LeadConversionTransferAction.Request();
        request.leadId = leadRecord.Id;

        Test.startTest();
        LeadConversionTransferAction.transfer(
            new List<LeadConversionTransferAction.Request>{ request, null }
        );
        Test.stopTest();

        Interaction__c unchangedInteraction = [
            SELECT Lead__c, Contact__c
            FROM Interaction__c
            WHERE Id = :interactionRecord.Id
        ];
        System.assertEquals(leadRecord.Id, unchangedInteraction.Lead__c);
        System.assertEquals(null, unchangedInteraction.Contact__c);
    }
}
