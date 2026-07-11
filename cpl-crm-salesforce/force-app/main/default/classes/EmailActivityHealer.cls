public with sharing class EmailActivityHealer {
    // Emails captured by the intake integration only get a Task tying them to a
    // scholar when that person is already a matched Contact/PersonAccount at
    // capture time. Emails that land while the person is still a Lead (or not yet
    // in the org) stay "orphaned" and never surface on the scholar's record.
    //
    // This service is the reusable, idempotent fix: for any EmailMessage whose
    // participant addresses match a known Contact/PersonAccount, it makes the
    // email visible on that scholar's Activity Timeline the same way the working
    // records already are -- a completed Email-subtype Task with WhoId = the
    // person's Contact.
    //
    // Both EmailMessage.ActivityId and EmailMessage.RelatedToId are read-only at
    // runtime in this org, so the EmailMessage itself cannot be touched and cannot
    // hold a "healed" marker. Instead each generated Task records its origin in
    // Task.Source_Email_Message__c (a unique external id). That field is the
    // idempotency key -- re-runs skip any email already represented by a Task --
    // and doubles as provenance linking a timeline activity back to its email.

    // Addresses on these internal domains are senders/loggers, not the scholar we
    // want to attach to. They never appear in the scholar match map anyway, but
    // skipping them keeps the matching cheap and unambiguous.
    private static final Set<String> INTERNAL_DOMAINS = new Set<String>{
        'climbpauselift.org'
    };

    private class ScholarRef {
        Id accountId;
        Id contactId;
        ScholarRef(Id accountId, Id contactId) {
            this.accountId = accountId;
            this.contactId = contactId;
        }
    }

    // Heal a specific set of EmailMessages (used by the on-create / on-demand path).
    public static Integer healEmailMessages(Set<Id> emailMessageIds) {
        if (emailMessageIds == null || emailMessageIds.isEmpty()) {
            return 0;
        }
        return healRecords([
            SELECT Id, Subject, TextBody, MessageDate, ActivityId, CreatedById
            FROM EmailMessage
            WHERE Id IN :emailMessageIds
        ]);
    }

    // Heal every unattached email whose address matches one of these scholars
    // (used on Lead -> PersonAccount conversion: pass the new PersonContactIds).
    public static Integer healForScholars(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return 0;
        }
        Set<String> scholarAddrs = new Set<String>();
        for (Contact c : [SELECT Email FROM Contact WHERE Id IN :contactIds AND Email != null]) {
            scholarAddrs.add(c.Email.toLowerCase());
        }
        if (scholarAddrs.isEmpty()) {
            return 0;
        }
        Set<Id> emIds = new Set<Id>();
        for (EmailMessageRelation r : [
            SELECT EmailMessageId
            FROM EmailMessageRelation
            WHERE RelationAddress IN :scholarAddrs
        ]) {
            emIds.add(r.EmailMessageId);
        }
        return healEmailMessages(emIds);
    }

    // Core routine. Bulk-safe, idempotent, partial-success. Returns count healed.
    public static Integer healRecords(List<EmailMessage> ems) {
        if (ems == null || ems.isEmpty()) {
            return 0;
        }

        Map<Id, EmailMessage> emById = new Map<Id, EmailMessage>();
        Set<Id> activityIds = new Set<Id>();
        Set<String> emIdStrings = new Set<String>();
        for (EmailMessage em : ems) {
            emById.put(em.Id, em);
            emIdStrings.add(String.valueOf(em.Id));
            if (em.ActivityId != null) {
                activityIds.add(em.ActivityId);
            }
        }
        if (emById.isEmpty()) {
            return 0;
        }

        // Idempotency: any email we have already generated a Task for is skipped.
        Set<Id> alreadyHealed = new Set<Id>();
        for (Task t : [
            SELECT Source_Email_Message__c FROM Task WHERE Source_Email_Message__c IN :emIdStrings
        ]) {
            alreadyHealed.add((Id) t.Source_Email_Message__c);
        }

        // Participant addresses per email.
        Map<Id, Set<String>> addrsByEm = new Map<Id, Set<String>>();
        Set<String> allAddrs = new Set<String>();
        for (EmailMessageRelation r : [
            SELECT EmailMessageId, RelationAddress
            FROM EmailMessageRelation
            WHERE EmailMessageId IN :emById.keySet() AND RelationAddress != null
        ]) {
            String addr = r.RelationAddress.toLowerCase().trim();
            if (addr == '' || isInternal(addr)) {
                continue;
            }
            if (!addrsByEm.containsKey(r.EmailMessageId)) {
                addrsByEm.put(r.EmailMessageId, new Set<String>());
            }
            addrsByEm.get(r.EmailMessageId).add(addr);
            allAddrs.add(addr);
        }
        if (allAddrs.isEmpty()) {
            return 0;
        }

        // Address -> scholar. PersonAccounts first, then regular Contacts.
        Map<String, ScholarRef> scholarByAddr = new Map<String, ScholarRef>();
        for (Account a : [
            SELECT Id, PersonContactId, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true AND PersonEmail IN :allAddrs
        ]) {
            scholarByAddr.put(a.PersonEmail.toLowerCase(), new ScholarRef(a.Id, a.PersonContactId));
        }
        for (Contact c : [
            SELECT Id, AccountId, Email
            FROM Contact
            WHERE Email IN :allAddrs AND IsPersonAccount = false
        ]) {
            String addr = c.Email.toLowerCase();
            if (!scholarByAddr.containsKey(addr)) {
                scholarByAddr.put(addr, new ScholarRef(c.AccountId, c.Id));
            }
        }
        if (scholarByAddr.isEmpty()) {
            return 0;
        }

        // Any existing Task already behind these emails (so we re-point rather
        // than create a duplicate).
        Map<Id, Task> taskById = new Map<Id, Task>();
        if (!activityIds.isEmpty()) {
            taskById = new Map<Id, Task>([
                SELECT Id, WhoId, WhatId, AccountId FROM Task WHERE Id IN :activityIds
            ]);
        }

        List<Task> toInsert = new List<Task>();
        List<Task> toUpdate = new List<Task>();

        for (Id emId : emById.keySet()) {
            if (alreadyHealed.contains(emId)) {
                continue; // a Task already represents this email
            }
            EmailMessage em = emById.get(emId);
            Set<String> addrs = addrsByEm.get(emId);
            if (addrs == null) {
                continue;
            }

            // Resolve to exactly one scholar; skip on none or ambiguity.
            ScholarRef scholar = uniqueScholar(addrs, scholarByAddr);
            if (scholar == null) {
                continue;
            }

            Task existing = (em.ActivityId != null) ? taskById.get(em.ActivityId) : null;
            if (existing != null) {
                if (tiedToPerson(existing)) {
                    continue; // already visible on a Contact/Account -- leave it
                }
                // Task exists but points only at a Lead / nothing: re-point it.
                existing.WhoId = scholar.contactId;
                toUpdate.add(existing);
            } else {
                toInsert.add(buildTask(em, scholar));
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
        return toInsert.size() + toUpdate.size();
    }

    private static Boolean isInternal(String addr) {
        Integer at = addr.indexOf('@');
        if (at < 0) {
            return false;
        }
        return INTERNAL_DOMAINS.contains(addr.substring(at + 1));
    }

    // Contact = 003, Account = 001.
    private static Boolean tiedToPerson(Task t) {
        return isContact(t.WhoId) || isAccount(t.WhatId) || t.AccountId != null;
    }
    private static Boolean isContact(Id value) {
        return value != null && String.valueOf(value).startsWith('003');
    }
    private static Boolean isAccount(Id value) {
        return value != null && String.valueOf(value).startsWith('001');
    }

    private static ScholarRef uniqueScholar(Set<String> addrs, Map<String, ScholarRef> scholarByAddr) {
        ScholarRef found = null;
        for (String addr : addrs) {
            ScholarRef s = scholarByAddr.get(addr);
            if (s == null) {
                continue;
            }
            if (found == null) {
                found = s;
            } else if (found.contactId != s.contactId) {
                return null; // more than one distinct scholar -> ambiguous
            }
        }
        return found;
    }

    private static Task buildTask(EmailMessage em, ScholarRef scholar) {
        Task t = new Task(
            WhoId = scholar.contactId,
            Subject = 'Email: ' + (String.isBlank(em.Subject) ? '(no subject)' : em.Subject),
            Status = 'Completed',
            TaskSubtype = 'Email',
            ActivityDate = (em.MessageDate != null) ? em.MessageDate.date() : null,
            Description = String.isBlank(em.TextBody) ? null : em.TextBody.abbreviate(32000),
            Source_Email_Message__c = em.Id
        );
        // Attribute the activity to whoever logged the email, when available.
        if (em.CreatedById != null) {
            t.OwnerId = em.CreatedById;
        }
        return t;
    }
}
