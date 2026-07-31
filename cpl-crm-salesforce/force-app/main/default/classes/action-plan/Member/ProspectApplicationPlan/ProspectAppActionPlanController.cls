public with sharing class ProspectAppActionPlanController {
    private static final List<String> PLAN_SUBJECTS = new List<String>{
        'Send scholarship invite',
        'Confirm invite acceptance',
        'Send materials for review link',
        'Confirm materials',
        'Set-up final interview',
        'Collect evaluations',
        'Make decision'
    };

    // Subject -> screen flow API name. Populated incrementally as each step flow ships.
    // A subject with no entry renders without a Launch button.
    private static final Map<String, String> SUBJECT_TO_FLOW = new Map<String, String>{
        'Send scholarship invite' => 'App_Send_Invite',
        'Confirm invite acceptance' => 'App_Confirm_Invite_Acceptance',
        'Send materials for review link' => 'App_Send_Materials_Link',
        'Confirm materials' => 'App_Confirm_Materials'
    };

    @AuraEnabled(cacheable=true)
    public static List<ActionPlanTask> getTasks(Id applicationId) {
        if (applicationId == null) {
            return new List<ActionPlanTask>();
        }

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
        for (String subject : PLAN_SUBJECTS) {
            planTasks.add(new ActionPlanTask(step, subject, tasksBySubject.get(subject)));
            step++;
        }

        for (ActionPlanTask t : planTasks) {
            if (t.stateClass != 'completed') {
                t.isCurrent = true;
                t.stateClass = 'current';
                break;
            }
        }

        return planTasks;
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

        private ActionPlanTask(Integer stepNumber, String subject, Task t) {
            this.stepNumber = stepNumber;
            this.subject = subject;
            this.exists = t != null;
            this.flowApiName = SUBJECT_TO_FLOW.get(subject);
            this.isCurrent = false;

            if (t == null) {
                this.status = 'Missing';
                this.priority = null;
                this.dueDate = null;
                this.ownerName = null;
                this.taskId = null;
                this.stateClass = 'missing';
                return;
            }

            this.status = t.Status;
            this.priority = t.Priority;
            this.dueDate = t.ActivityDate;
            this.ownerName = t.Owner == null ? null : t.Owner.Name;
            this.taskId = t.Id;
            this.stateClass = t.Status == 'Completed' ? 'completed' : 'upcoming';
        }
    }
}