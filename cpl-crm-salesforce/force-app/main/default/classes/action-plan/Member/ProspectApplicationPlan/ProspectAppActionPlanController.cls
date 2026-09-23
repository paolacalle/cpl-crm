public with sharing class ProspectAppActionPlanController {
    private static final String STAGE_INVITE = 'Scholarship invite';
    private static final String STAGE_MATERIALS = 'Collecting Material';
    private static final String STAGE_INTERVIEW = 'Interview + Evaluations';
    private static final String STAGE_DECISION = 'Decision';

    private static final List<String> PLAN_SUBJECTS = new List<String>{
        'Send scholarship invite',
        'Confirm invite acceptance',
        'Send materials for review link',
        'Confirm materials',
        'Set-up final interview',
        'Collect evaluations',
        'Make decision'
    };

    private static final List<String> STAGE_SUBJECTS = new List<String>{
        STAGE_INVITE,
        STAGE_MATERIALS,
        STAGE_INTERVIEW,
        STAGE_DECISION
    };

    private static final Map<String, List<String>> STAGE_TO_TASK_SUBJECTS = new Map<String, List<String>>{
        STAGE_INVITE => new List<String>{ 'Send scholarship invite', 'Confirm invite acceptance' },
        STAGE_MATERIALS => new List<String>{ 'Send materials for review link', 'Confirm materials' },
        STAGE_INTERVIEW => new List<String>{ 'Set-up final interview', 'Collect evaluations' },
        STAGE_DECISION => new List<String>{ 'Make decision' }
    };

    @AuraEnabled(cacheable=true)
    public static List<ActionPlanTask> getTasks(Id applicationId) {
        if (applicationId == null) {
            return new List<ActionPlanTask>();
        }

        List<Prospect_Scholar_Application__c> applications = [
            SELECT Id,
                   Application_Status__c,
                   Scholarship_Invite_Sent__c,
                   Scholarship_Invite_Confirmed__c,
                   Materials_Complete__c,
                   Applicant_Account__r.Name,
                   Applicant_Account__r.PersonEmail
            FROM Prospect_Scholar_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return new List<ActionPlanTask>();
        }

        Prospect_Scholar_Application__c application = applications[0];
        Map<String, Task> tasksBySubject = new Map<String, Task>();
        for (Task t : [
            SELECT Id, Subject, Status, Priority, ActivityDate, Owner.Name
            FROM Task
            WHERE WhatId = :applicationId
            AND Subject IN :PLAN_SUBJECTS
            ORDER BY CreatedDate ASC
        ]) {
            if (!tasksBySubject.containsKey(t.Subject)) {
                tasksBySubject.put(t.Subject, t);
            }
        }

        List<ActionPlanTask> planTasks = new List<ActionPlanTask>();
        Integer step = 1;
        for (String subject : STAGE_SUBJECTS) {
            planTasks.add(new ActionPlanTask(step, subject, application, tasksBySubject));
            step++;
        }

        Boolean foundCurrent = false;
        for (ActionPlanTask t : planTasks) {
            if (!foundCurrent && t.stateClass != 'completed') {
                t.isCurrent = true;
                t.stateClass = 'current';
                foundCurrent = true;
            }
        }

        return planTasks;
    }

    @AuraEnabled
    public static void ensureCurrentStageTasks(Id applicationId) {
        if (applicationId == null) {
            return;
        }

        List<Prospect_Scholar_Application__c> applications = [
            SELECT Id, Application_Status__c, Case_Owner__c
            FROM Prospect_Scholar_Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return;
        }

        Prospect_Scholar_Application__c application = applications[0];
        Set<String> existingSubjects = new Set<String>();
        for (Task applicationTask : [
            SELECT Subject
            FROM Task
            WHERE WhatId = :application.Id
            AND Subject IN :PLAN_SUBJECTS
        ]) {
            existingSubjects.add(applicationTask.Subject);
        }

        List<Task> missingTasks = new List<Task>();
        Id taskOwnerId = application.Case_Owner__c == null ? UserInfo.getUserId() : application.Case_Owner__c;
        for (String subject : PLAN_SUBJECTS) {
            if (!existingSubjects.contains(subject)) {
                missingTasks.add(new Task(
                    WhatId = application.Id,
                    OwnerId = taskOwnerId,
                    Subject = subject,
                    Status = statusForApplicationSubject(application.Application_Status__c, subject),
                    Priority = 'Normal'
                ));
            }
        }

        if (!missingTasks.isEmpty()) {
            insert missingTasks;
        }
    }

    @AuraEnabled
    public static void markScholarshipInviteSent(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('Application is required.');
        }

        update new Prospect_Scholar_Application__c(
            Id = applicationId,
            Scholarship_Invite_Sent__c = true,
            Scholarship_Invite_Status__c = 'Sent'
        );
        completeTasks(applicationId, new List<String>{ 'Send scholarship invite' });
    }

    @AuraEnabled
    public static void markReadyForDecision(Id applicationId) {
        if (applicationId == null) {
            throw new AuraHandledException('Application is required.');
        }

        completeTasks(applicationId, new List<String>{ 'Set-up final interview', 'Collect evaluations' });
    }

    private static String statusForApplicationSubject(String applicationStatus, String subject) {
        return 'Not Started';
    }

    private static void completeTasks(Id applicationId, List<String> subjects) {
        List<Task> tasksToComplete = [
            SELECT Id, Status
            FROM Task
            WHERE WhatId = :applicationId
            AND Subject IN :subjects
            AND Status != 'Completed'
        ];
        for (Task taskRecord : tasksToComplete) {
            taskRecord.Status = 'Completed';
        }

        if (!tasksToComplete.isEmpty()) {
            update tasksToComplete;
        }
    }

    private static Boolean terminalStatus(String applicationStatus) {
        return applicationStatus == 'Accepted' ||
            applicationStatus == 'Rejected' ||
            applicationStatus == 'Withdrawn';
    }

    private static Boolean stageCompleted(
        String stage,
        Prospect_Scholar_Application__c application,
        Map<String, Task> tasksBySubject
    ) {
        if (stage == STAGE_INVITE) {
            return application.Scholarship_Invite_Sent__c == true &&
                application.Scholarship_Invite_Confirmed__c == true;
        }

        if (stage == STAGE_MATERIALS) {
            return application.Materials_Complete__c == true ||
                application.Application_Status__c == 'In Review' ||
                application.Application_Status__c == 'Waitlisted' ||
                terminalStatus(application.Application_Status__c);
        }

        if (stage == STAGE_INTERVIEW) {
            return terminalStatus(application.Application_Status__c) ||
                (
                    taskCompleted(tasksBySubject.get('Set-up final interview')) &&
                    taskCompleted(tasksBySubject.get('Collect evaluations'))
                );
        }

        if (stage == STAGE_DECISION) {
            return terminalStatus(application.Application_Status__c);
        }

        return false;
    }

    private static Boolean taskCompleted(Task taskRecord) {
        return taskRecord != null && taskRecord.Status == 'Completed';
    }

    private static Task firstStageTask(String stage, Map<String, Task> tasksBySubject) {
        for (String subject : STAGE_TO_TASK_SUBJECTS.get(stage)) {
            Task taskRecord = tasksBySubject.get(subject);
            if (taskRecord != null) {
                return taskRecord;
            }
        }
        return null;
    }

    private static StageAction flowAction(String name, String label, String flowApiName) {
        return new StageAction(name, label, 'flow', flowApiName, true);
    }

    private static StageAction apexAction(String name, String label) {
        return new StageAction(name, label, 'apex', null, true);
    }

    private static StageAction clientAction(String name, String label) {
        return new StageAction(name, label, 'client', null, true);
    }

    private static StageAction disabledAction(String name, String label) {
        return new StageAction(name, label, 'disabled', null, false);
    }

    public class ActionPlanTask {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String taskId;
        @AuraEnabled public Boolean exists;
        @AuraEnabled public String stateClass;
        @AuraEnabled public String flowApiName;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public String applicantName;
        @AuraEnabled public String applicantEmail;
        @AuraEnabled public List<StageAction> actions;

        private ActionPlanTask(
            Integer stepNumber,
            String subject,
            Prospect_Scholar_Application__c application,
            Map<String, Task> tasksBySubject
        ) {
            this.stepNumber = stepNumber;
            this.subject = subject;
            Task t = firstStageTask(subject, tasksBySubject);
            this.exists = allStageTasksExist(subject, tasksBySubject);
            this.flowApiName = null;
            this.isCurrent = false;
            this.applicantName = application.Applicant_Account__r == null
                ? null
                : application.Applicant_Account__r.Name;
            this.applicantEmail = application.Applicant_Account__r == null
                ? null
                : application.Applicant_Account__r.PersonEmail;
            this.actions = actionsForStage(subject);

            if (t == null) {
                this.status = 'Missing';
                this.priority = null;
                this.dueDate = null;
                this.ownerName = null;
                this.taskId = null;
                this.stateClass = 'missing';
                return;
            }

            Boolean isCompleted = stageCompleted(subject, application, tasksBySubject);
            this.status = isCompleted ? 'Completed' : 'Open';
            this.priority = t.Priority;
            this.dueDate = t.ActivityDate;
            this.ownerName = t.Owner == null ? null : t.Owner.Name;
            this.taskId = t.Id;
            this.stateClass = isCompleted ? 'completed' : 'upcoming';
        }

        private Boolean allStageTasksExist(String stage, Map<String, Task> tasksBySubject) {
            for (String taskSubject : STAGE_TO_TASK_SUBJECTS.get(stage)) {
                if (!tasksBySubject.containsKey(taskSubject)) {
                    return false;
                }
            }
            return true;
        }

        private List<StageAction> actionsForStage(String stage) {
            if (stage == STAGE_INVITE) {
                return new List<StageAction>{
                    flowAction('sendInvite', 'Send invite', 'App_Send_Invite'),
                    apexAction('confirmInviteSent', 'Confirm invite was sent'),
                    flowAction('confirmInviteAcceptance', 'Confirm invite acceptance', 'App_Confirm_Invite_Acceptance')
                };
            }

            if (stage == STAGE_MATERIALS) {
                return new List<StageAction>{
                    flowAction('sendMaterialsLink', 'Send materials link', 'App_Send_Materials_Link'),
                    flowAction('confirmMaterials', 'Confirm materials', 'App_Confirm_Materials')
                };
            }

            if (stage == STAGE_INTERVIEW) {
                return new List<StageAction>{
                    clientAction('googleCalendar', 'Google Calendar'),
                    disabledAction('zoom', 'Zoom coming soon'),
                    clientAction('genericEmail', 'Email applicant'),
                    clientAction('evaluationLink', 'Send evaluation link'),
                    apexAction('readyForDecision', 'Ready for decision')
                };
            }

            return new List<StageAction>{
                disabledAction('decisionActions', 'Use record actions')
            };
        }
    }

    public class StageAction {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String flowApiName;
        @AuraEnabled public Boolean enabled;

        public StageAction(String name, String label, String type, String flowApiName, Boolean enabled) {
            this.name = name;
            this.label = label;
            this.type = type;
            this.flowApiName = flowApiName;
            this.enabled = enabled;
        }
    }
}
