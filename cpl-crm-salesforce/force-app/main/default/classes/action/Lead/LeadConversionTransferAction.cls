public with sharing class LeadConversionTransferAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable
        public Id convertedAccountId;

        @InvocableVariable(required=true)
        public Id convertedContactId;
    }

    @InvocableMethod(
        label='Transfer Converted Lead Related Records'
        description='Moves custom interaction notes and standard activities from a converted Lead to the new CPL Member contact.'
    )
    public static void transfer(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Id> leadToContact = new Map<Id, Id>();
        for (Request request : requests) {
            if (request == null || request.leadId == null || request.convertedContactId == null) {
                continue;
            }
            leadToContact.put(request.leadId, request.convertedContactId);
        }

        if (leadToContact.isEmpty()) {
            return;
        }

        transferInteractions(leadToContact);
        transferTasks(leadToContact);
        transferEvents(leadToContact);
        syncConvertedContactFields(leadToContact);
    }

    private static void syncConvertedContactFields(Map<Id, Id> leadToContact) {
        Map<Id, Lead> leadsById = new Map<Id, Lead>([
            SELECT Id, Primary_Sport__c, Why_CPL_Scholar__c,
                Commits_to_CPL_mantra__c, College_Year__c, LeadSource
            FROM Lead
            WHERE Id IN :leadToContact.keySet()
        ]);

        List<Contact> contactsToUpdate = new List<Contact>();
        for (Id leadId : leadToContact.keySet()) {
            Id contactId = leadToContact.get(leadId);
            Lead leadRecord = leadsById.get(leadId);
            if (contactId == null || leadRecord == null) {
                continue;
            }

            contactsToUpdate.add(new Contact(
                Id = contactId,
                Source_Lead_Object__c = leadId,
                Primary_Sport__c = leadRecord.Primary_Sport__c,
                Why_CPL__c = leadRecord.Why_CPL_Scholar__c,
                Commits_to_CPL_mantra__c = leadRecord.Commits_to_CPL_mantra__c,
                College_Year__c = leadRecord.College_Year__c,
                LeadSource = leadRecord.LeadSource
            ));
        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }

    private static void transferInteractions(Map<Id, Id> leadToContact) {
        List<Interaction__c> interactionsToUpdate = new List<Interaction__c>();
        for (Interaction__c interactionRecord : [
            SELECT Id, Lead__c, Contact__c
            FROM Interaction__c
            WHERE Lead__c IN :leadToContact.keySet()
        ]) {
            Id contactId = leadToContact.get(interactionRecord.Lead__c);
            if (contactId == null) {
                continue;
            }

            interactionRecord.Contact__c = contactId;
            interactionRecord.Lead__c = null;
            interactionsToUpdate.add(interactionRecord);
        }

        if (!interactionsToUpdate.isEmpty()) {
            update interactionsToUpdate;
        }
    }

    private static void transferTasks(Map<Id, Id> leadToContact) {
        List<Task> tasksToUpdate = new List<Task>();
        for (Task taskRecord : [
            SELECT Id, WhoId
            FROM Task
            WHERE WhoId IN :leadToContact.keySet()
        ]) {
            Id contactId = leadToContact.get(taskRecord.WhoId);
            if (contactId == null) {
                continue;
            }

            taskRecord.WhoId = contactId;
            tasksToUpdate.add(taskRecord);
        }

        if (!tasksToUpdate.isEmpty()) {
            update tasksToUpdate;
        }
    }

    private static void transferEvents(Map<Id, Id> leadToContact) {
        List<Event> eventsToUpdate = new List<Event>();
        for (Event eventRecord : [
            SELECT Id, WhoId
            FROM Event
            WHERE WhoId IN :leadToContact.keySet()
        ]) {
            Id contactId = leadToContact.get(eventRecord.WhoId);
            if (contactId == null) {
                continue;
            }

            eventRecord.WhoId = contactId;
            eventsToUpdate.add(eventRecord);
        }

        if (!eventsToUpdate.isEmpty()) {
            update eventsToUpdate;
        }
    }
}
