public with sharing class LeadIntakeActionPlanController {
    private static final List<String> SCHOLAR_SUBJECTS = new List<String>{
        'Confirm submission',
        'Contact lead',
        'Disqualify / Convert'
    };

    private static final List<String> PARTNER_SUBJECTS = new List<String>{
        'Initial outreach',
        'Discovery meeting',
        'Convert or Disqualify'
    };

    // Subject -> screen flow launched for that step. Populated incrementally as each
    // step's flow ships; a subject with no entry renders without a Launch button.
    private static final Map<String, String> SUBJECT_TO_FLOW = new Map<String, String>{
        'Confirm submission' => 'Lead_Guided_Intake_Review',
        'Contact lead' => 'Lead_Log_Contact',
        'Disqualify / Convert' => 'Lead_Convert_Or_Disqualify',
        'Initial outreach' => 'Partner_Initial_Outreach',
        'Discovery meeting' => 'Partner_Discovery_Meeting',
        'Convert or Disqualify' => 'Partner_Convert_Or_Disqualify'
    };

    @AuraEnabled(cacheable=true)
    public static List<ActionPlanTask> getTasks(Id leadId) {
        if (leadId == null) {
            return new List<ActionPlanTask>();
        }

        List<String> planSubjects = subjectsForLead(leadId);

        Map<String, Task> tasksBySubject = new Map<String, Task>();
        for (Task intakeTask : [
            SELECT Id, Subject, Status, Priority, ActivityDate, Owner.Name
            FROM Task
            WHERE WhoId = :leadId
            AND Subject IN :planSubjects
            ORDER BY CreatedDate ASC
        ]) {
            if (!tasksBySubject.containsKey(intakeTask.Subject)) {
                tasksBySubject.put(intakeTask.Subject, intakeTask);
            }
        }

        List<ActionPlanTask> planTasks = new List<ActionPlanTask>();
        Integer step = 1;
        for (String subject : planSubjects) {
            planTasks.add(new ActionPlanTask(step, subject, tasksBySubject.get(subject)));
            step++;
        }

        // The first step that is not completed is the current/active step.
        for (ActionPlanTask planTask : planTasks) {
            if (planTask.stateClass != 'completed') {
                planTask.isCurrent = true;
                planTask.stateClass = 'current';
                break;
            }
        }

        return planTasks;
    }

    private static List<String> subjectsForLead(Id leadId) {
        for (Lead lead : [
            SELECT RecordType.DeveloperName FROM Lead WHERE Id = :leadId LIMIT 1
        ]) {
            if (lead.RecordType != null && lead.RecordType.DeveloperName == 'Partner_Lead') {
                return PARTNER_SUBJECTS;
            }
        }
        return SCHOLAR_SUBJECTS;
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

        private ActionPlanTask(Integer stepNumber, String subject, Task intakeTask) {
            this.stepNumber = stepNumber;
            this.subject = subject;
            this.exists = intakeTask != null;
            this.flowApiName = SUBJECT_TO_FLOW.get(subject);
            this.isCurrent = false;

            if (intakeTask == null) {
                this.status = 'Missing';
                this.priority = null;
                this.dueDate = null;
                this.ownerName = null;
                this.taskId = null;
                this.stateClass = 'missing';
                return;
            }

            this.status = intakeTask.Status;
            this.priority = intakeTask.Priority;
            this.dueDate = intakeTask.ActivityDate;
            this.ownerName = intakeTask.Owner == null ? null : intakeTask.Owner.Name;
            this.taskId = intakeTask.Id;
            this.stateClass = intakeTask.Status == 'Completed' ? 'completed' : 'upcoming';
        }
    }
}
