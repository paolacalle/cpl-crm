public with sharing class EmailActivityHealAction {
    // Invoked by the record-triggered Flow that fires when a scholar PersonAccount
    // is created. Emails captured before that account existed are orphaned; the
    // moment the account (and its PersonContact) comes into being is exactly when
    // they should be attached. The work is enqueued so it runs after the account
    // commits -- off the creation transaction's critical path, and never able to
    // fail the account insert.

    public class Request {
        @InvocableVariable(
            required=true
            label='Scholar Contact Id'
            description='PersonContactId of the newly created scholar PersonAccount.'
        )
        public Id scholarContactId;
    }

    @InvocableMethod(
        label='Heal Scholar Email Activities'
        description='Attaches previously-captured emails to a newly created scholar by matching addresses and logging Email Tasks on the timeline.'
    )
    public static void run(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Id> contactIds = new Set<Id>();
        for (Request req : requests) {
            if (req.scholarContactId != null) {
                contactIds.add(req.scholarContactId);
            }
        }
        if (contactIds.isEmpty()) {
            return;
        }
        // Enqueue when we can (the normal Flow path); fall back to synchronous when
        // already inside async where a fresh enqueue is not allowed.
        if (!System.isBatch() && !System.isFuture() && Limits.getLimitQueueableJobs() - Limits.getQueueableJobs() > 0) {
            System.enqueueJob(new HealJob(contactIds));
        } else {
            EmailActivityHealer.healForScholars(contactIds);
        }
    }

    private class HealJob implements Queueable {
        private Set<Id> contactIds;
        private HealJob(Set<Id> contactIds) {
            this.contactIds = contactIds;
        }
        public void execute(QueueableContext context) {
            EmailActivityHealer.healForScholars(contactIds);
        }
    }
}
