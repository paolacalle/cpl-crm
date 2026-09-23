public with sharing class LeadIntakeActionPlanController {
    private static final String INTAKE_REVIEW_QUEUE_DEVELOPER_NAME = 'Intake_Review_Queue';

    private static final List<String> SCHOLAR_SUBJECTS = new List<String>{
        'Review application',
        'Active Contacting',
        'Decision - Disqualify / Convert'
    };

    private static final List<String> PARTNER_SUBJECTS = new List<String>{
        'Initial outreach',
        'Discovery meeting',
        'Convert or Disqualify'
    };

    private static final Map<String, String> LEGACY_SUBJECT_TO_SUBJECT =
        new Map<String, String>{
            'Confirm submission' => 'Review application',
            'Contact lead' => 'Active Contacting',
            'Disqualify / Convert' => 'Decision - Disqualify / Convert'
        };

    // Subject -> screen flow launched for that step. Populated incrementally as each
    // step's flow ships; a subject with no entry renders without a Launch button.
    private static final Map<String, String> SUBJECT_TO_FLOW = new Map<String, String>{
        // Student
        'Review application' => 'Lead_Guided_Intake_Review',
        'Active Contacting' => 'Lead_Log_Contact',
        'Decision - Disqualify / Convert' => 'Lead_Convert_Or_Disqualify',

        // Partner
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
        Boolean isTerminal = isTerminalLead(leadId);

        Set<String> querySubjects = new Set<String>(planSubjects);
        querySubjects.addAll(LEGACY_SUBJECT_TO_SUBJECT.keySet());

        Map<String, Task> tasksBySubject = new Map<String, Task>();
        for (Task intakeTask : [
            SELECT Id, Subject, Status, Priority, ActivityDate, Owner.Name
            FROM Task
            WHERE WhoId = :leadId
            AND Subject IN :querySubjects
            ORDER BY CreatedDate ASC
        ]) {
            String subject = canonicalSubject(intakeTask.Subject);
            if (!tasksBySubject.containsKey(subject)) {
                tasksBySubject.put(subject, intakeTask);
            }
        }

        List<ActionPlanTask> planTasks = new List<ActionPlanTask>();
        Integer step = 1;
        for (String subject : planSubjects) {
            planTasks.add(new ActionPlanTask(step, subject, tasksBySubject.get(subject)));
            step++;
        }

        // The first step that is not completed is the current/active step. A
        // converted or disqualified (Unqualified) lead is terminal: no step is
        // active and nothing should offer a Launch button ("no action required").
        if (!isTerminal) {
            for (ActionPlanTask planTask : planTasks) {
                if (planTask.stateClass != 'completed') {
                    planTask.isCurrent = true;
                    planTask.stateClass = 'current';
                    break;
                }
            }
        }

        return planTasks;
    }

    @AuraEnabled
    public static void ensureCurrentStageTasks(Id leadId) {
        if (leadId == null) {
            return;
        }

        List<Lead> leads = [
            SELECT Id, OwnerId, Status, IsConverted, RecordType.DeveloperName
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            return;
        }

        Lead lead = leads[0];
        if (
            lead.IsConverted ||
            lead.Status == 'Unqualified' ||
            (lead.RecordType != null && lead.RecordType.DeveloperName == 'Partner_Lead')
        ) {
            return;
        }

        Set<String> querySubjects = new Set<String>(SCHOLAR_SUBJECTS);
        querySubjects.addAll(LEGACY_SUBJECT_TO_SUBJECT.keySet());

        Set<String> existingCanonicalSubjects = new Set<String>();
        for (Task intakeTask : [
            SELECT Subject
            FROM Task
            WHERE WhoId = :lead.Id
            AND Subject IN :querySubjects
        ]) {
            existingCanonicalSubjects.add(canonicalSubject(intakeTask.Subject));
        }

        List<Task> missingTasks = new List<Task>();
        Id taskOwnerId = intakeReviewQueueId();
        for (String subject : SCHOLAR_SUBJECTS) {
            if (!existingCanonicalSubjects.contains(subject)) {
                missingTasks.add(new Task(
                    WhoId = lead.Id,
                    OwnerId = taskOwnerId,
                    Subject = subject,
                    Description = descriptionForScholarSubject(subject),
                    Status = statusForScholarSubject(lead.Status, subject),
                    Priority = 'Normal'
                ));
            }
        }

        if (!missingTasks.isEmpty()) {
            insert missingTasks;
        }
    }

    @AuraEnabled(cacheable=true)
    public static LeadPlanState getLeadState(Id leadId) {
        LeadPlanState state = new LeadPlanState();
        if (leadId == null) {
            return state;
        }

        for (Lead lead : [
            SELECT Status, IsConverted, ConvertedAccountId, ConvertedContactId
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ]) {
            state.statusLabel = lead.Status;
            state.isConverted = lead.IsConverted;
            state.isUnqualified = !lead.IsConverted && lead.Status == 'Unqualified';
            // Person leads convert into a Person Account (the CPL member); fall
            // back to the Contact if no account was created.
            state.convertedRecordId = lead.ConvertedAccountId != null
                ? lead.ConvertedAccountId
                : lead.ConvertedContactId;
        }
        return state;
    }

    @AuraEnabled
    public static void reopenLead(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('No lead specified.');
        }

        List<Lead> leads = [
            SELECT Status, IsConverted, RecordType.DeveloperName
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new AuraHandledException('Lead not found.');
        }

        Lead lead = leads[0];
        if (lead.IsConverted) {
            throw new AuraHandledException('Converted leads cannot be re-opened.');
        }

        // Return the lead to the decision point so the intake host can work it again.
        lead.Status = 'Decision';
        update lead;

        // Re-open the final outcome step so its Launch button reappears.
        Set<String> outcomeSubjects = new Set<String>{
            'Decision - Disqualify / Convert',
            'Disqualify / Convert'
        };
        List<Task> outcomeTasks = [
            SELECT Id, Status
            FROM Task
            WHERE WhoId = :leadId AND Subject IN :outcomeSubjects
        ];
        for (Task outcomeTask : outcomeTasks) {
            outcomeTask.Status = 'Not Started';
        }
        if (!outcomeTasks.isEmpty()) {
            update outcomeTasks;
        }
    }

    private static Boolean isTerminalLead(Id leadId) {
        for (Lead lead : [
            SELECT Status, IsConverted FROM Lead WHERE Id = :leadId LIMIT 1
        ]) {
            return lead.IsConverted || lead.Status == 'Unqualified';
        }
        return false;
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

    private static String canonicalSubject(String subject) {
        return LEGACY_SUBJECT_TO_SUBJECT.containsKey(subject)
            ? LEGACY_SUBJECT_TO_SUBJECT.get(subject)
            : subject;
    }

    private static Id intakeReviewQueueId() {
        for (Group intakeQueue : [
            SELECT Id
            FROM Group
            WHERE DeveloperName = :INTAKE_REVIEW_QUEUE_DEVELOPER_NAME
            AND Type = 'Queue'
            LIMIT 1
        ]) {
            return intakeQueue.Id;
        }
        throw new AuraHandledException('The Intake Review Queue could not be found.');
    }

    private static String descriptionForScholarSubject(String subject) {
        if (subject == 'Review application') {
            return 'Review the submitted Lead details, including email, school, college year, resume, scholar statement, school, and sport.';
        }

        if (subject == 'Active Contacting') {
            return 'Actively contact the Lead, log contact notes, and decide when they are ready for final decision.';
        }

        if (subject == 'Decision - Disqualify / Convert') {
            return 'Make the final intake decision by either disqualifying the Lead or converting it to a CPL Member.';
        }

        return null;
    }

    private static String statusForScholarSubject(String leadStatus, String subject) {
        if (leadStatus == 'Decision') {
            return subject == 'Decision - Disqualify / Convert' ? 'Not Started' : 'Completed';
        }

        if (leadStatus == 'Contacting') {
            return subject == 'Review application' ? 'Completed' : 'Not Started';
        }

        return 'Not Started';
    }

    public class LeadPlanState {
        @AuraEnabled public Boolean isConverted = false;
        @AuraEnabled public Boolean isUnqualified = false;
        @AuraEnabled public Id convertedRecordId;
        @AuraEnabled public String statusLabel;
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
