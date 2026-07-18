@isTest
private class LeadIntakeSummaryEmailActionTest {
    @isTest
    static void nullAndEmptyAreNoOps() {
        Test.startTest();
        LeadIntakeSummaryEmailAction.run(null);
        LeadIntakeSummaryEmailAction.run(new List<LeadIntakeSummaryEmailAction.Request>());
        System.assertEquals(0, Limits.getQueueableJobs(), 'Nothing should be enqueued');
        Test.stopTest();
    }

    @isTest
    static void blankResumeUrlEnqueues() {
        Lead ld = new Lead(LastName = 'NoResume', Company = 'N/A', Status = 'New');
        insert ld;

        LeadIntakeSummaryEmailAction.Request req = new LeadIntakeSummaryEmailAction.Request();
        req.leadId = ld.Id;
        req.resumeUrl = null;

        Test.startTest();
        LeadIntakeSummaryEmailAction.run(new List<LeadIntakeSummaryEmailAction.Request>{ req });
        System.assertEquals(1, Limits.getQueueableJobs(),
            'A lead without a resume URL should enqueue the email job');
        Test.stopTest();
    }

    @isTest
    static void resumeUrlPresentSkips() {
        Lead ld = new Lead(LastName = 'HasResume', Company = 'N/A', Status = 'New');
        insert ld;

        LeadIntakeSummaryEmailAction.Request req = new LeadIntakeSummaryEmailAction.Request();
        req.leadId = ld.Id;
        req.resumeUrl = 'https://example.com/r.pdf';

        Test.startTest();
        LeadIntakeSummaryEmailAction.run(new List<LeadIntakeSummaryEmailAction.Request>{ req });
        System.assertEquals(0, Limits.getQueueableJobs(),
            'Leads with a resume URL are handled by the resume-download chain, not here');
        Test.stopTest();
    }
}
