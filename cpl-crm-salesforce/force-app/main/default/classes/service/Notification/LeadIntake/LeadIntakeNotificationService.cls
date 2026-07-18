/**
 * @description Service class handling notifications and recipient targeting 
 * specifically for the Lead Intake pipeline.
 *
 * @group Services
 */
public with sharing class LeadIntakeNotificationService {

    @TestVisible 
    private static final Set<String> INTAKE_GROUP_NAMES = new Set<String>{ 'PG_CRM_Admins', 'PG_Intake_Owners' };
    
    private static final String GROUP_TYPE_REGULAR = 'Regular';

    /**
     * @description Retrieves the unified email addresses for the target Lead Intake team groups.
     * Uses no arguments to guarantee consumer classes fetch the correct intake recipients.
     * @return Set<String> Set of distinct, active email addresses for the intake team.
     */
    public static Set<String> getIntakeTeamEmails() {
        // Updated to use the correct signature from your GetGroupTeamEmailsUtils class
        return GetGroupTeamEmailsUtils.getIntakeTeamEmails(INTAKE_GROUP_NAMES, GROUP_TYPE_REGULAR);
    }
}
