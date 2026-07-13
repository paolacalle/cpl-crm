public with sharing class CplHomeIntakePipelineController {
    private static final List<String> STATUS_ORDER = new List<String>{
        'New',
        'In Intake Review',
        'Contacted',
        'Qualified',
        'Unqualified'
    };

    @AuraEnabled(cacheable=true)
    public static List<StatusCount> getPipeline() {
        List<StatusCount> ordered = new List<StatusCount>();

        Id rtId;
        for (RecordType rt : [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Lead' AND DeveloperName = 'CPL_Scholar_Lead' LIMIT 1
        ]) {
            rtId = rt.Id;
        }
        if (rtId == null) {
            for (String s : STATUS_ORDER) {
                StatusCount c = new StatusCount();
                c.status = s;
                c.count = 0;
                ordered.add(c);
            }
            return ordered;
        }

        Map<String, Integer> countsByStatus = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Status status, COUNT(Id) cnt
            FROM Lead
            WHERE RecordTypeId = :rtId AND IsConverted = false
            GROUP BY Status
        ]) {
            countsByStatus.put((String) ar.get('status'), (Integer) ar.get('cnt'));
        }

        for (String s : STATUS_ORDER) {
            StatusCount c = new StatusCount();
            c.status = s;
            c.count = countsByStatus.containsKey(s) ? countsByStatus.get(s) : 0;
            ordered.add(c);
        }
        return ordered;
    }

    public class StatusCount {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count;
    }
}