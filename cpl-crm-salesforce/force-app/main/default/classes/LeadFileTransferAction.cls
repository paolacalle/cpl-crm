public with sharing class LeadFileTransferAction {
    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;
        @InvocableVariable(required=true)
        public Id targetId;
    }

    @InvocableMethod(
        label='Transfer Lead Files'
        description='Links the files attached to a converted lead onto the new record (CPL Member).'
    )
    public static void transfer(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Map<Id, Id> leadToTarget = new Map<Id, Id>();
        for (Request req : requests) {
            if (req.leadId != null && req.targetId != null) {
                leadToTarget.put(req.leadId, req.targetId);
            }
        }
        if (leadToTarget.isEmpty()) {
            return;
        }

        // Files currently linked to each lead.
        Map<Id, Set<Id>> docsByLead = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :leadToTarget.keySet()
        ]) {
            if (!docsByLead.containsKey(link.LinkedEntityId)) {
                docsByLead.put(link.LinkedEntityId, new Set<Id>());
            }
            docsByLead.get(link.LinkedEntityId).add(link.ContentDocumentId);
        }

        // Files already on the target records, to avoid duplicate links.
        Map<Id, Set<Id>> docsByTarget = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :leadToTarget.values()
        ]) {
            if (!docsByTarget.containsKey(link.LinkedEntityId)) {
                docsByTarget.put(link.LinkedEntityId, new Set<Id>());
            }
            docsByTarget.get(link.LinkedEntityId).add(link.ContentDocumentId);
        }

        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (Id leadId : docsByLead.keySet()) {
            Id targetId = leadToTarget.get(leadId);
            Set<Id> alreadyLinked = docsByTarget.containsKey(targetId)
                ? docsByTarget.get(targetId)
                : new Set<Id>();
            for (Id documentId : docsByLead.get(leadId)) {
                if (!alreadyLinked.contains(documentId)) {
                    newLinks.add(new ContentDocumentLink(
                        ContentDocumentId = documentId,
                        LinkedEntityId = targetId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }
        }

        if (!newLinks.isEmpty()) {
            // Partial success: never let a file-link failure roll back the conversion.
            Database.insert(newLinks, false);
        }
    }
}
