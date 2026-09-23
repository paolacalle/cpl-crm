public with sharing class ProspectAppActionPlanController {
    // controller class manages the action plan tasks
    // for prospect scholarship applications
    // it defines the standard tasks, their corresponding screen flows,
    // and provides a method to retrieve the action plan tasks for a given application.

    // these are the standard tasks for prospect scholarship action plan
    private static final List<String> PLAN_SUBJECTS = new List<String>{
        'Scholarship Invite + Material Collection',
        'Interview + Evaluations',
        'Decision'
    };

    // mapping of subject to the corresponding screen flow API name
    private static final Map<String, String> SUBJECT_TO_FLOW = new Map<String, String>{
        'Scholarship Invite + Material Collection' => 'App_Invite_Materials',
        'Interview + Evaluations' => 'App_Interview_Evaluations',
        'Decision' => 'App_Decision'
    };

    @AuraEnabled(cacheable=true)
    public static List<ActionPlanTask> getTasks(Id applicationId) {

        // return an empty list if no application ID is provided
        if (applicationId == null) {
            return new List<ActionPlanTask>();
        }

        // query all existing tasks for the given application ID
        // that match the standard subjects
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

        // build the list of action plan tasks based on the standard subjects
        List<ActionPlanTask> planTasks = new List<ActionPlanTask>();
        Integer step = 1;
        for (String subject : PLAN_SUBJECTS) {
            planTasks.add(new ActionPlanTask(step, subject, tasksBySubject.get(subject)));
            step++;
        }

        // mark the first non-completed task as current
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
