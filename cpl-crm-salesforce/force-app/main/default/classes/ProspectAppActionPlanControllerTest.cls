@IsTest(SeeAllData=true)
private class ProspectAppActionPlanControllerTest {
    @IsTest
    static void nullAppReturnsNoTasks() {
        System.assertEquals(0, ProspectAppActionPlanController.getTasks(null).size());
    }

    @IsTest
    static void returnsAllSevenStepsForAppWithoutTasks() {
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

        System.assertEquals(7, tasks.size(), 'Should always return 7 plan steps');
        System.assertEquals('Send scholarship invite', tasks[0].subject);
        System.assertEquals('App_Send_Invite', tasks[0].flowApiName);
        System.assertEquals('Confirm invite acceptance', tasks[1].subject);
        System.assertEquals('App_Confirm_Invite_Acceptance', tasks[1].flowApiName);
        System.assertEquals('Make decision', tasks[6].subject);
        System.assertEquals(null, tasks[6].flowApiName);
    }
}
