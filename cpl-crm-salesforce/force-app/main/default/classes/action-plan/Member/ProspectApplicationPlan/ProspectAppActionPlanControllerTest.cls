@IsTest(SeeAllData=true)
private class ProspectAppActionPlanControllerTest {
    @IsTest
    static void nullAppReturnsNoTasks() {
        System.assertEquals(0, ProspectAppActionPlanController.getTasks(null).size());
    }

    @IsTest
    static void returnsAllThreeStagesForAppWithoutTasks() {
        Prospect_Scholar_Application__c app;
        for (Prospect_Scholar_Application__c existing : [
            SELECT Id FROM Prospect_Scholar_Application__c LIMIT 1
        ]) {
            app = existing;
        }
        if (app == null) {
            return; // No applications in org to test against.
        }

        List<ProspectAppActionPlanController.ActionPlanTask> tasks =
            ProspectAppActionPlanController.getTasks(app.Id);

        System.assertEquals(3, tasks.size(), 'Should always return 3 plan stages');
        System.assertEquals('Scholarship Invite + Material Collection', tasks[0].subject);
        System.assertEquals('App_Invite_Materials', tasks[0].flowApiName);
        System.assertEquals('Interview + Evaluations', tasks[1].subject);
        System.assertEquals('App_Interview_Evaluations', tasks[1].flowApiName);
        System.assertEquals('Decision', tasks[2].subject);
        System.assertEquals('App_Decision', tasks[2].flowApiName);
    }
}
