public class ScholarApplicationStageService {
    private static final Set<String> DECISIONS = new Set<String>{'Accepted','Rejected','Waitlisted','Withdrawn'};
    public static void synchronize(List<Prospect_Scholar_Application__c> records,
        Map<Id, Prospect_Scholar_Application__c> priorRecords) {
        for (Prospect_Scholar_Application__c app : records) {
            Prospect_Scholar_Application__c prior = priorRecords == null ? null : priorRecords.get(app.Id);
            Boolean decisionEdited = app.Application_Decision__c != null &&
                (prior == null || app.Application_Decision__c != prior.Application_Decision__c);
            Boolean stageEdited = app.Application_Stage__c != null &&
                (prior == null || app.Application_Stage__c != prior.Application_Stage__c);
            Boolean legacyEdited = prior == null || app.Application_Status__c != prior.Application_Status__c;
            if (decisionEdited || stageEdited) {
                String decision = app.Application_Decision__c;
                if (decision == null) decision = DECISIONS.contains(app.Application_Status__c) ? app.Application_Status__c : 'Pending';
                app.Application_Decision__c = decision;
                if (DECISIONS.contains(decision)) {
                    app.Application_Status__c = decision;
                    app.Application_Stage__c = decision == 'Waitlisted' ? 'Ready for Decision' : 'Closed';
                } else if (app.Application_Stage__c == 'Closed') {
                    app.addError('Choose Accepted, Rejected, or Withdrawn to close the application.');
                } else {
                    if (app.Application_Stage__c == null) app.Application_Stage__c = stageFor(app.Application_Status__c);
                    if (app.Application_Stage__c == 'Invite & Materials') {
                        // Preserve the detailed invitation/materials substatus where available.
                        if (app.Application_Status__c != 'Collecting Documents') app.Application_Status__c = 'Invite Sent';
                    } else {
                        app.Application_Status__c = 'In Review';
                    }
                }
            } else if (legacyEdited || app.Application_Stage__c == null || app.Application_Decision__c == null) {
                app.Application_Decision__c = DECISIONS.contains(app.Application_Status__c) ? app.Application_Status__c : 'Pending';
                // Backfill must not invent interview completion from an old In Review status.
                app.Application_Stage__c = stageFor(app.Application_Status__c);
            }
        }
    }
    public static String stageFor(String status) {
        if (status == 'Waitlisted') return 'Ready for Decision';
        if (DECISIONS.contains(status)) return 'Closed';
        if (status == 'In Review') return 'Interview & Evaluations';
        return 'Invite & Materials';
    }
}
