public with sharing class CplSchoolMemberSummaryController {
    @AuraEnabled(cacheable=true)
    public static SchoolSummary getSummary(Id schoolId) {
        SchoolSummary s = new SchoolSummary();
        s.total = 0;
        s.byLifecycle = new List<CountRow>();
        s.bySport = new List<CountRow>();
        s.byCollegeYear = new List<CountRow>();

        if (schoolId == null) {
            return s;
        }

        s.total = [
            SELECT COUNT()
            FROM Account
            WHERE School__pc = :schoolId AND IsPersonAccount = TRUE
        ];
        s.byLifecycle = aggregateByField('CPL_Student_Lifecycle__c', schoolId);
        s.bySport = aggregateByField('Primary_Sport__pc', schoolId);
        s.byCollegeYear = aggregateByField('College_Year__pc', schoolId);
        return s;
    }

    private static List<CountRow> aggregateByField(String fieldApi, Id schoolId) {
        String q =
            'SELECT ' + fieldApi + ' lbl, COUNT(Id) cnt ' +
            'FROM Account ' +
            'WHERE School__pc = :schoolId AND IsPersonAccount = TRUE ' +
            'GROUP BY ' + fieldApi + ' ' +
            'ORDER BY COUNT(Id) DESC';
        List<CountRow> rows = new List<CountRow>();
        for (AggregateResult ar : Database.query(q)) {
            CountRow r = new CountRow();
            String raw = (String) ar.get('lbl');
            r.label = String.isBlank(raw) ? '(unset)' : raw;
            r.count = (Integer) ar.get('cnt');
            rows.add(r);
        }
        return rows;
    }

    public class SchoolSummary {
        @AuraEnabled public Integer total;
        @AuraEnabled public List<CountRow> byLifecycle;
        @AuraEnabled public List<CountRow> bySport;
        @AuraEnabled public List<CountRow> byCollegeYear;
    }

    public class CountRow {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
    }
}