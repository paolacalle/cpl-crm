public with sharing class ScholarshipInviteActionCtrl {
    @AuraEnabled
    public static void sendInvite(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('No Prospect Scholar Application was provided.');
        }

        ScholarshipInviteEmailAction.Request request = new ScholarshipInviteEmailAction.Request();
        request.applicationId = applicationId;
        ScholarshipInviteEmailAction.sendInvite(
            new List<ScholarshipInviteEmailAction.Request>{ request }
        );
    }
}
