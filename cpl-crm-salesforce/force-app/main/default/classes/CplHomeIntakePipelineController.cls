public with sharing class CplHomeIntakePipelineController {
    private static final Id SCHOLAR_LEAD_RECORD_TYPE_ID = '012Kd00000163evIAA';
    private static final Id MEMBER_PERSON_RECORD_TYPE_ID = '012Vx000003FTsn';

    private static final List<String> SCHOLAR_LEAD_STATUS_ORDER = new List<String>{
        'New',
        'In Intake Review',
        'Contacted',
        'Qualified',
        'Unqualified'
    };

    private static final List<String> MEMBER_PERSON_STATUS_ORDER = new List<String>{
        'Athlete',
        'Prospect',
        'Applicant',
        'Scholar',
        'Scholar Alumni',
        'Alumni',
        'Inactive'
    };

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getPipeline() {
        List<StatusCount> ordered = getScholarLead();

        StatusCount converted = new StatusCount();
        converted.status = 'Converted';
        converted.count = [
            SELECT COUNT()
            FROM Account
            WHERE RecordTypeId = :MEMBER_PERSON_RECORD_TYPE_ID
        ];
        ordered.add(converted);

        return ordered;
    }

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getScholarLead() {
        List<StatusCount> ordered = new List<StatusCount>();

        Map<String, Integer> countsByStatus = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status status, COUNT(Id) cnt
            FROM Lead
            WHERE RecordTypeId = :SCHOLAR_LEAD_RECORD_TYPE_ID
            GROUP BY Status
        ]) {
            countsByStatus.put((String) ar.get('status'), (Integer) ar.get('cnt'));
        }

        for (String s : SCHOLAR_LEAD_STATUS_ORDER) {
            StatusCount c = new StatusCount();
            c.status = s;
            c.count = countsByStatus.containsKey(s) ? countsByStatus.get(s) : 0;

            if (c.status == 'In Intake Review') {
                c.status = 'In Review';
            }

            ordered.add(c);
        }
        return ordered;
    }

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getMemberPerson() {
        List<StatusCount> ordered = new List<StatusCount>();

        Map<String, Integer> countsByLifecycle = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT CPL_Student_Lifecycle__c lifecycle, COUNT(Id) cnt
            FROM Account
            WHERE RecordTypeId = :MEMBER_PERSON_RECORD_TYPE_ID
            GROUP BY CPL_Student_Lifecycle__c
        ]) {
            countsByLifecycle.put((String) ar.get('lifecycle'), (Integer) ar.get('cnt'));
        }

        for (String s : MEMBER_PERSON_STATUS_ORDER) {
            StatusCount c = new StatusCount();
            c.status = s;
            c.count = countsByLifecycle.containsKey(s) ? countsByLifecycle.get(s) : 0;
            ordered.add(c);
        }
        return ordered;
    }

    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }
}
