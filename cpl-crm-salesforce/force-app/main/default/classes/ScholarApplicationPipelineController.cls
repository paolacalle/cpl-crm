public with sharing class ScholarApplicationPipelineController {
    @AuraEnabled(cacheable=true)
    public static List<Tile> getPipeline() {
        Map<String,Integer> counts = new Map<String,Integer>();
        for (AggregateResult row : [SELECT Application_Stage__c stage, COUNT(Id) total
            FROM Prospect_Scholar_Application__c WITH USER_MODE GROUP BY Application_Stage__c]) {
            counts.put((String)row.get('stage'), (Integer)row.get('total'));
        }
        Integer decisions = [SELECT COUNT() FROM Prospect_Scholar_Application__c
            WHERE Application_Decision__c != null AND Application_Decision__c != 'Pending' WITH USER_MODE];
        return new List<Tile>{
            new Tile('Invite & Materials', 'Scholar_Invite_Materials', counts.get('Invite & Materials')),
            new Tile('Interview & Evaluations', 'Scholar_Interview_Evaluations', counts.get('Interview & Evaluations')),
            new Tile('Ready for Decision', 'Scholar_Ready_for_Decision', counts.get('Ready for Decision')),
            new Tile('All Decisions', 'Scholar_All_Decisions', decisions)};
    }
    public class Tile {
        @AuraEnabled public String label;
        @AuraEnabled public String filterName;
        @AuraEnabled public Integer count;
        public Tile(String label, String filterName, Integer count) {
            this.label = label; this.filterName = filterName; this.count = count == null ? 0 : count;
        }
    }
}
