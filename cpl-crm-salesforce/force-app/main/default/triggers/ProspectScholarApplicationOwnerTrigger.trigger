trigger ProspectScholarApplicationOwnerTrigger on Prospect_Scholar_Application__c (before insert) {
    for (Prospect_Scholar_Application__c application : Trigger.new) {
        if (application.Case_Owner__c == null) {
            application.Case_Owner__c = UserInfo.getUserId();
        }
    }
}
