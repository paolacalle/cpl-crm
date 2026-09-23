@IsTest(SeeAllData=true)
private class ProspectAppActionPlanControllerTest {
    @IsTest
    static void nullAppReturnsNoTasks() {
        System.assertEquals(0, ProspectAppActionPlanController.getTasks(null).size());
    }

    @IsTest
    static void returnsFourPipelineStagesForAppWithoutTasks() {
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

        System.assertEquals(4, tasks.size(), 'Should always return 4 pipeline stages');
        System.assertEquals('Scholarship invite', tasks[0].subject);
        System.assertEquals(3, tasks[0].actions.size());
        System.assertEquals('Send invite', tasks[0].actions[0].label);
        System.assertEquals('Collecting Material', tasks[1].subject);
        System.assertEquals('Interview + Evaluations', tasks[2].subject);
        System.assertEquals('Decision', tasks[3].subject);
    }

    @IsTest
    static void ensureCurrentStageTasksCreatesMissingApplicationTasks() {
        Prospect_Scholar_Application__c app = new Prospect_Scholar_Application__c(
            Applicant_Account__c = applicantAccountId(),
            Application_Status__c = 'Invite Sent',
            Case_Owner__c = UserInfo.getUserId()
        );
        insert app;
        app.Application_Status__c = 'Collecting Documents';
        app.Scholarship_Invite_Sent__c = true;
        app.Scholarship_Invite_Confirmed__c = true;
        app.Scholarship_Invite_Status__c = 'Confirmed';
        update app;
        clearSeededTasks(app.Id);

        Test.startTest();
        ProspectAppActionPlanController.ensureCurrentStageTasks(app.Id);
        Test.stopTest();

        Map<String, Task> tasksBySubject = tasksBySubject(app.Id);
        System.assertEquals(7, tasksBySubject.size());
        System.assertEquals('Not Started', tasksBySubject.get('Send scholarship invite').Status);
        System.assertEquals('Not Started', tasksBySubject.get('Confirm invite acceptance').Status);
        System.assertEquals('Not Started', tasksBySubject.get('Send materials for review link').Status);
        System.assertEquals(UserInfo.getUserId(), tasksBySubject.get('Confirm materials').OwnerId);
        System.assertEquals('Normal', tasksBySubject.get('Make decision').Priority);

        List<ProspectAppActionPlanController.ActionPlanTask> tasks =
            ProspectAppActionPlanController.getTasks(app.Id);
        System.assertEquals(true, tasks[1].isCurrent);
        System.assertEquals('Collecting Material', tasks[1].subject);
        System.assertEquals('current', tasks[1].stateClass);
    }

    @IsTest
    static void ensureCurrentStageTasksDoesNotDuplicateExistingApplicationTasks() {
        Prospect_Scholar_Application__c app = new Prospect_Scholar_Application__c(
            Applicant_Account__c = applicantAccountId(),
            Application_Status__c = 'Invite Sent',
            Case_Owner__c = UserInfo.getUserId()
        );
        insert app;
        clearSeededTasks(app.Id);

        ProspectAppActionPlanController.ensureCurrentStageTasks(app.Id);
        ProspectAppActionPlanController.ensureCurrentStageTasks(app.Id);

        System.assertEquals(7, [SELECT COUNT() FROM Task WHERE WhatId = :app.Id]);
    }

    @IsTest
    static void markScholarshipInviteSentCompletesOnlyInviteSendTask() {
        Prospect_Scholar_Application__c app = new Prospect_Scholar_Application__c(
            Applicant_Account__c = applicantAccountId(),
            Application_Status__c = 'Invite Sent',
            Case_Owner__c = UserInfo.getUserId()
        );
        insert app;
        clearSeededTasks(app.Id);
        ProspectAppActionPlanController.ensureCurrentStageTasks(app.Id);

        Test.startTest();
        ProspectAppActionPlanController.markScholarshipInviteSent(app.Id);
        Test.stopTest();

        Prospect_Scholar_Application__c updatedApp = [
            SELECT Scholarship_Invite_Sent__c, Scholarship_Invite_Status__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :app.Id
        ];
        Map<String, Task> tasksBySubject = tasksBySubject(app.Id);
        System.assertEquals(true, updatedApp.Scholarship_Invite_Sent__c);
        System.assertEquals('Sent', updatedApp.Scholarship_Invite_Status__c);
        System.assertEquals('Completed', tasksBySubject.get('Send scholarship invite').Status);
        System.assertEquals('Not Started', tasksBySubject.get('Confirm invite acceptance').Status);

        List<ProspectAppActionPlanController.ActionPlanTask> stages =
            ProspectAppActionPlanController.getTasks(app.Id);
        System.assertEquals('Scholarship invite', stages[0].subject);
        System.assertEquals(true, stages[0].isCurrent, 'Invite stage stays current until acceptance is confirmed');
    }

    @IsTest
    static void markReadyForDecisionMovesCurrentStageToDecision() {
        Prospect_Scholar_Application__c app = new Prospect_Scholar_Application__c(
            Applicant_Account__c = applicantAccountId(),
            Application_Status__c = 'Invite Sent',
            Case_Owner__c = UserInfo.getUserId()
        );
        insert app;
        app.Scholarship_Invite_Sent__c = true;
        app.Scholarship_Invite_Confirmed__c = true;
        app.Scholarship_Invite_Status__c = 'Confirmed';
        app.Resume_Received__c = true;
        app.Essay_Received__c = true;
        app.Coach_Professor_Recommendation_Received__c = true;
        app.Internship_Supervisor_Rec_Received__c = true;
        update app;
        clearSeededTasks(app.Id);
        ProspectAppActionPlanController.ensureCurrentStageTasks(app.Id);

        Test.startTest();
        ProspectAppActionPlanController.markReadyForDecision(app.Id);
        Test.stopTest();

        Map<String, Task> tasksBySubject = tasksBySubject(app.Id);
        System.assertEquals('Completed', tasksBySubject.get('Set-up final interview').Status);
        System.assertEquals('Completed', tasksBySubject.get('Collect evaluations').Status);

        List<ProspectAppActionPlanController.ActionPlanTask> stages =
            ProspectAppActionPlanController.getTasks(app.Id);
        System.assertEquals(true, stages[3].isCurrent);
        System.assertEquals('Decision', stages[3].subject);
    }

    private static Id applicantAccountId() {
        RecordType applicantRecordType = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'cpl_applicant_account'
            LIMIT 1
        ];
        Account applicant = new Account(
            FirstName = 'Action',
            LastName = 'Plan Applicant',
            College_Year__pc = 'Junior',
            PersonEmail = 'action.plan+' + System.now().getTime() + '@example.com',
            RecordTypeId = applicantRecordType.Id
        );
        insert applicant;

        RecordType internshipRecordType = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Employment__c'
            AND DeveloperName = 'Internship'
            LIMIT 1
        ];
        insert new Employment__c(
            CPL_Member__c = applicant.Id,
            Employment_Type__c = 'Internship',
            Is_qualifying__c = true,
            RecordTypeId = internshipRecordType.Id,
            Start_Date__c = Date.today().addMonths(-3)
        );

        return applicant.Id;
    }

    private static void clearSeededTasks(Id applicationId) {
        delete [
            SELECT Id
            FROM Task
            WHERE WhatId = :applicationId
        ];
    }

    private static Map<String, Task> tasksBySubject(Id applicationId) {
        Map<String, Task> tasksBySubject = new Map<String, Task>();
        for (Task applicationTask : [
            SELECT Subject, Status, OwnerId, Priority
            FROM Task
            WHERE WhatId = :applicationId
        ]) {
            tasksBySubject.put(applicationTask.Subject, applicationTask);
        }
        return tasksBySubject;
    }
}
