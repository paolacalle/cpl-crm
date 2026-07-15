public with sharing class CplHomeMemberPipelineController {
    private static final List<String> STATUS_ORDER = new List<String>{
        'Athlete',
        'Prospect',
        'Applicant',
        'Scholar',
        'Scholar Alumni',
        'Alumni',
        'Inactive'
    };

    // cache the method's results on the client-side
    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getPipeline() {
        List<StatusCount> ordered = new List<StatusCount>();

        // record type for a CPL member person account
        Id rtId='012Vx000003FTsnIAG';

        // fill count for each of the status
        for (AggregateResult ar : [
            SELECT CPL_Student_Lifecycle__c status, COUNT(Id) cnt
            FROM PersonAccount
            WHERE RecordTypeId = :rtId AND CPL_Student_Lifecycle__c != Null
            GROUP BY CPL_Student_Lifecycle__c
        ]) {
            StatusCount c = new StatusCount();
            c.status = (String) ar.get('status');
            c.count = (Integer) ar.get('cnt');
            ordered.add(c);
        }

        return ordered;
    }

    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }
}