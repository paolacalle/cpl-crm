public with sharing class CplHomeMemberPipelineController {
    // Lifecycle stages are defined in CPL_Student_Lifecycle__c picklist values.
    private static final List<String> STATUS_ORDER = new List<String>{
        'Athlete',
        // 'Prospect',
        'Applicant',
        'Member Scholar', 
        'Scholar Alumni',
        'Alumni'
        // 'Inactive'
    };

    // cache the method's results on the client-side
    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getPipeline() {
        // count members in each lifecycle stage. The lifecycle field is CPL-member
        // specific, so a non-null value on a person account identifies a member --
        // no record-type filter needed (matches the IsPersonAccount pattern used
        // elsewhere in this project).
        Map<String, Integer> countByStatus = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT CPL_Student_Lifecycle__c status, COUNT(Id) cnt
            FROM Account
            WHERE IsPersonAccount = TRUE AND CPL_Student_Lifecycle__c != Null
            GROUP BY CPL_Student_Lifecycle__c
        ]) {
            countByStatus.put((String) ar.get('status'), (Integer) ar.get('cnt'));
        }

        // replace scholar key with member-scholar key 
        if (countByStatus.containsKey('Scholar')) {
            Integer scholarCount = countByStatus.remove('Scholar');
            countByStatus.put('Member Scholar', scholarCount);
        }

        // emit every stage in lifecycle order, including empty ones
        List<StatusCount> ordered = new List<StatusCount>();
        for (String status : STATUS_ORDER) {
            StatusCount c = new StatusCount();
            c.status = status;
            c.count = countByStatus.containsKey(status) ? countByStatus.get(status) : 0;
            ordered.add(c);
        }

        return ordered;
    }

    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }
}