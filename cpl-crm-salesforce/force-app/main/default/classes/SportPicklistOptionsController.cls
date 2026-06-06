public with sharing class SportPicklistOptionsController {
    public class PicklistOption {
        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLeadPrimarySportOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : Lead.Primary_Sport__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }
}
