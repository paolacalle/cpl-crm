@IsTest
private class ScholarApplicationStageServiceTest {
    @IsTest static void emptyBackfillCompletes() {
        Test.startTest();
        Id jobId = Database.executeBatch(new ScholarApplicationStageBackfill(), 100);
        Test.stopTest();
        System.assertEquals(0, [SELECT NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId].NumberOfErrors);
    }
    private static Prospect_Scholar_Application__c legacy(String status) {
        return new Prospect_Scholar_Application__c(Application_Status__c = status);
    }
    @IsTest static void mapsLegacyStatuses() {
        Map<String,String> expected = new Map<String,String>{
            'Invite Sent'=>'Invite & Materials', 'Collecting Documents'=>'Invite & Materials',
            'In Review'=>'Interview & Evaluations', 'Waitlisted'=>'Ready for Decision',
            'Accepted'=>'Closed', 'Rejected'=>'Closed', 'Withdrawn'=>'Closed'};
        for (String status : expected.keySet()) {
            Prospect_Scholar_Application__c app = legacy(status);
            ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{app}, null);
            System.assertEquals(expected.get(status), app.Application_Stage__c);
            System.assertEquals(status, app.Application_Status__c, 'Mapping must preserve historical outcome');
            System.assertEquals(status == 'Invite Sent' || status == 'Collecting Documents' || status == 'In Review'
                ? 'Pending' : status, app.Application_Decision__c);
        }
    }
    @IsTest static void translatesStaffEditsAndRejectsClosedPending() {
        for (String decision : new List<String>{'Accepted','Rejected','Withdrawn','Waitlisted'}) {
            Prospect_Scholar_Application__c app = legacy('In Review');
            app.Application_Decision__c = decision;
            ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{app}, null);
            System.assertEquals(decision, app.Application_Status__c);
            System.assertEquals(decision == 'Waitlisted' ? 'Ready for Decision' : 'Closed', app.Application_Stage__c);
        }
        for (String stage : new List<String>{'Invite & Materials','Interview & Evaluations','Ready for Decision'}) {
            Prospect_Scholar_Application__c app = legacy('Invite Sent');
            app.Application_Stage__c = stage;
            app.Application_Decision__c = 'Pending';
            ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{app}, null);
            System.assertEquals(stage, app.Application_Stage__c);
            System.assertEquals(stage == 'Invite & Materials' ? 'Invite Sent' : 'In Review', app.Application_Status__c);
        }
        Prospect_Scholar_Application__c invalid = legacy('In Review');
        invalid.Application_Stage__c = 'Closed';
        invalid.Application_Decision__c = 'Pending';
        ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{invalid}, null);
        System.assert(invalid.hasErrors());
    }
    @IsTest static void unrelatedUpdatesPreserveReadyAndLegacyChangesWinWhenNewFieldsUnchanged() {
        Id fakeId = (Id)(Prospect_Scholar_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Prospect_Scholar_Application__c prior = new Prospect_Scholar_Application__c(Id=fakeId,
            Application_Status__c='In Review', Application_Stage__c='Ready for Decision', Application_Decision__c='Pending');
        Map<Id,Prospect_Scholar_Application__c> oldMap = new Map<Id,Prospect_Scholar_Application__c>{fakeId=>prior};
        Prospect_Scholar_Application__c app = prior.clone(true);
        ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{app}, oldMap);
        System.assertEquals('Ready for Decision', app.Application_Stage__c);
        app.Application_Status__c = 'Accepted';
        ScholarApplicationStageService.synchronize(new List<Prospect_Scholar_Application__c>{app}, oldMap);
        System.assertEquals('Closed', app.Application_Stage__c);
        System.assertEquals('Accepted', app.Application_Decision__c);
    }
}
