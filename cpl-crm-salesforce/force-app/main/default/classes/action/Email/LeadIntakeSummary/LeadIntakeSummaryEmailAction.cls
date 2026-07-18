/**
 * @description Invocable Action exposed to Salesforce Flows to route Lead notifications.
 * Filters out records based on resume state to avoid asynchronous race conditions with background file downloads.
 * 
 * **Business Logic Context:**
 * When a user submits a form on the website, the integration layer performs two operations concurrently:
 * 1. Creates a Lead record in Salesforce.
 * 2. Invokes an external service (`LeadResumeFileService`) to download the applicant's resume file and attach it.
 * 
 * If Salesforce dispatches the intake email immediately upon record insertion, the download may still be in-flight,
 * resulting in an incomplete notification lacking the resume attachment. This class routes traffic appropriately.
 *
 * @group InvocableActions
 */
public with sharing class LeadIntakeSummaryEmailAction {

    /**
     * @description Inner class defining the required input parameter structures received from Flow interviews.
     */
    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable
        public String resumeUrl;
    }

    /**
     * @description Enqueues an asynchronous email dispatch worker for leads that do not require an active file download.
     * Evaluates incoming requests and processes those containing a blank resume URL instantly.
     * @param requests List of Flow request payloads containing the target Lead ID and Resume URL context.
     */
    @InvocableMethod(
        label='Send Lead Intake Summary Email'
        description='Emails the intake team a PDF summary for a new lead with no resume URL. Leads that have a resume URL are handled after their resume file finishes downloading.'
    )
    public static void run(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<Id> leadIds = new List<Id>();

        for (Request rq : requests) {
            if (rq != null && rq.leadId != null && String.isBlank(rq.resumeUrl)) {
                leadIds.add(rq.leadId);
            }
        }

        // Enqueue the background execution thread exactly once for all matching 
        // records to ensure bulk safety
        if (!leadIds.isEmpty()) {
            System.enqueueJob(new LeadIntakeEmailQueueable(leadIds));
        }
    }
}
