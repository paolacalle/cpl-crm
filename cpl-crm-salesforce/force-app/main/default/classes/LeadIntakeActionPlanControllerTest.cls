@IsTest
private class LeadIntakeActionPlanControllerTest {
    private static Id scholarLeadRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Lead' AND DeveloperName = 'CPL_Scholar_Lead' LIMIT 1
        ].Id;
    }

    // Some test orgs auto-seed Tasks via a record-triggered flow when the Lead is inserted.
    // Clear them out so each test has predictable Task state.
    private static void clearSeededTasks(Id leadId) {
        delete [SELECT Id FROM Task WHERE WhoId = :leadId];
    }

    @IsTest
    static void returnsPlanTasksInOrder() {
        Lead leadRecord = new Lead(
            FirstName = 'Action',
            LastName = 'Plan',
            Company = 'CPL',
            Status = 'New',
            RecordTypeId = scholarLeadRtId()
        );
        insert leadRecord;
        clearSeededTasks(leadRecord.Id);

        insert new List<Task>{
            new Task(
                WhoId = leadRecord.Id,
                Subject = 'Contact lead',
                Status = 'Not Started',
                Priority = 'Normal',
                OwnerId = UserInfo.getUserId()
            ),
            new Task(
                WhoId = leadRecord.Id,
                Subject = 'Confirm submission',
                Status = 'Completed',
                Priority = 'Normal',
                OwnerId = UserInfo.getUserId()
            )
        };

        Test.startTest();
        List<LeadIntakeActionPlanController.ActionPlanTask> tasks =
            LeadIntakeActionPlanController.getTasks(leadRecord.Id);
        Test.stopTest();

        System.assertEquals(3, tasks.size());

        // Step 1 is complete, so it is not the current step.
        System.assertEquals('Confirm submission', tasks[0].subject);
        System.assertEquals('Completed', tasks[0].status);
        System.assertEquals('completed', tasks[0].stateClass);
        System.assertEquals(false, tasks[0].isCurrent);
        System.assertEquals('Lead_Guided_Intake_Review', tasks[0].flowApiName);

        // Step 2 is the first incomplete step, so it becomes current.
        System.assertEquals('Contact lead', tasks[1].subject);
        System.assertEquals(true, tasks[1].exists);
        System.assertEquals('current', tasks[1].stateClass);
        System.assertEquals(true, tasks[1].isCurrent);
        System.assertEquals('Lead_Log_Contact', tasks[1].flowApiName);

        // Step 3 has no Task yet.
        System.assertEquals('Disqualify / Convert', tasks[2].subject);
        System.assertEquals(false, tasks[2].exists);
        System.assertEquals('Missing', tasks[2].status);
        System.assertEquals('missing', tasks[2].stateClass);
        System.assertEquals(false, tasks[2].isCurrent);
        System.assertEquals('Lead_Convert_Or_Disqualify', tasks[2].flowApiName);
    }

    @IsTest
    static void firstStepCurrentWhenNoneCompleted() {
        Lead leadRecord = new Lead(
            FirstName = 'Fresh',
            LastName = 'Intake',
            Company = 'CPL',
            Status = 'New',
            RecordTypeId = scholarLeadRtId()
        );
        insert leadRecord;
        clearSeededTasks(leadRecord.Id);

        insert new List<Task>{
            new Task(WhoId = leadRecord.Id, Subject = 'Confirm submission', Status = 'Not Started'),
            new Task(WhoId = leadRecord.Id, Subject = 'Contact lead', Status = 'Not Started'),
            new Task(WhoId = leadRecord.Id, Subject = 'Disqualify / Convert', Status = 'Not Started')
        };

        List<LeadIntakeActionPlanController.ActionPlanTask> tasks =
            LeadIntakeActionPlanController.getTasks(leadRecord.Id);

        System.assertEquals(3, tasks.size());
        System.assertEquals('current', tasks[0].stateClass);
        System.assertEquals(true, tasks[0].isCurrent);
        System.assertEquals('Lead_Guided_Intake_Review', tasks[0].flowApiName);
        System.assertEquals('upcoming', tasks[1].stateClass);
        System.assertEquals(false, tasks[1].isCurrent);
        System.assertEquals('Lead_Log_Contact', tasks[1].flowApiName);
        System.assertEquals('upcoming', tasks[2].stateClass);
        System.assertEquals(false, tasks[2].isCurrent);
        System.assertEquals('Lead_Convert_Or_Disqualify', tasks[2].flowApiName);
    }

    @IsTest
    static void nullLeadReturnsNoTasks() {
        System.assertEquals(0, LeadIntakeActionPlanController.getTasks(null).size());
    }

    @IsTest
    static void disqualifiedLeadHasNoCurrentStep() {
        Lead leadRecord = new Lead(
            FirstName = 'Dis',
            LastName = 'Qualified',
            Company = 'CPL',
            Status = 'Unqualified',
            RecordTypeId = scholarLeadRtId()
        );
        insert leadRecord;
        clearSeededTasks(leadRecord.Id);

        insert new List<Task>{
            new Task(WhoId = leadRecord.Id, Subject = 'Confirm submission', Status = 'Completed'),
            new Task(WhoId = leadRecord.Id, Subject = 'Contact lead', Status = 'Completed'),
            new Task(WhoId = leadRecord.Id, Subject = 'Disqualify / Convert', Status = 'Completed')
        };

        List<LeadIntakeActionPlanController.ActionPlanTask> tasks =
            LeadIntakeActionPlanController.getTasks(leadRecord.Id);
        for (LeadIntakeActionPlanController.ActionPlanTask task : tasks) {
            System.assertEquals(false, task.isCurrent, 'Terminal lead should have no active step');
        }

        LeadIntakeActionPlanController.LeadPlanState state =
            LeadIntakeActionPlanController.getLeadState(leadRecord.Id);
        System.assertEquals(true, state.isUnqualified);
        System.assertEquals(false, state.isConverted);
    }

    @IsTest
    static void reopenLeadResetsStatusAndOutcomeTask() {
        Lead leadRecord = new Lead(
            FirstName = 'Re',
            LastName = 'Open',
            Company = 'CPL',
            Status = 'Unqualified',
            RecordTypeId = scholarLeadRtId()
        );
        insert leadRecord;
        clearSeededTasks(leadRecord.Id);

        insert new List<Task>{
            new Task(WhoId = leadRecord.Id, Subject = 'Confirm submission', Status = 'Completed'),
            new Task(WhoId = leadRecord.Id, Subject = 'Contact lead', Status = 'Completed')
        };
        Task outcome = new Task(
            WhoId = leadRecord.Id,
            Subject = 'Disqualify / Convert',
            Status = 'Completed'
        );
        insert outcome;

        Test.startTest();
        LeadIntakeActionPlanController.reopenLead(leadRecord.Id);
        Test.stopTest();

        Lead reloaded = [SELECT Status FROM Lead WHERE Id = :leadRecord.Id];
        System.assertEquals('Contacted', reloaded.Status);

        Task reloadedTask = [SELECT Status FROM Task WHERE Id = :outcome.Id];
        System.assertEquals('Not Started', reloadedTask.Status);

        // The reopened outcome step is active again.
        List<LeadIntakeActionPlanController.ActionPlanTask> tasks =
            LeadIntakeActionPlanController.getTasks(leadRecord.Id);
        System.assertEquals('Disqualify / Convert', tasks[2].subject);
        System.assertEquals(true, tasks[2].isCurrent);
    }

    @IsTest
    static void nullLeadStateIsEmpty() {
        LeadIntakeActionPlanController.LeadPlanState state =
            LeadIntakeActionPlanController.getLeadState(null);
        System.assertEquals(false, state.isConverted);
        System.assertEquals(false, state.isUnqualified);
    }

    @IsTest
    static void partnerLeadReturnsPartnerSubjects() {
        RecordType partnerRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Lead' AND DeveloperName = 'Partner_Lead' LIMIT 1
        ];
        Lead partnerLead = new Lead(
            FirstName = 'Pat',
            LastName = 'Partner',
            Company = 'Pending - Partner Outreach',
            Status = 'New',
            RecordTypeId = partnerRt.Id
        );
        insert partnerLead;
        clearSeededTasks(partnerLead.Id);

        insert new List<Task>{
            new Task(WhoId = partnerLead.Id, Subject = 'Initial outreach', Status = 'Not Started'),
            new Task(WhoId = partnerLead.Id, Subject = 'Discovery meeting', Status = 'Not Started'),
            new Task(WhoId = partnerLead.Id, Subject = 'Convert or Disqualify', Status = 'Not Started')
        };

        List<LeadIntakeActionPlanController.ActionPlanTask> tasks =
            LeadIntakeActionPlanController.getTasks(partnerLead.Id);

        System.assertEquals(3, tasks.size());
        System.assertEquals('Initial outreach', tasks[0].subject);
        System.assertEquals('current', tasks[0].stateClass);
        System.assertEquals('Partner_Initial_Outreach', tasks[0].flowApiName);

        System.assertEquals('Discovery meeting', tasks[1].subject);
        System.assertEquals('upcoming', tasks[1].stateClass);
        System.assertEquals('Partner_Discovery_Meeting', tasks[1].flowApiName);

        System.assertEquals('Convert or Disqualify', tasks[2].subject);
        System.assertEquals('upcoming', tasks[2].stateClass);
        System.assertEquals('Partner_Convert_Or_Disqualify', tasks[2].flowApiName);
    }
}