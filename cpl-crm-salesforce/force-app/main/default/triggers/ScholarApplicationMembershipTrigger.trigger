trigger ScholarApplicationMembershipTrigger on Prospect_Scholar_Application__c
    (after insert, after update, after delete, after undelete) {
    Set<Id> memberIds = new Set<Id>();
    if (Trigger.isDelete) {
        for (Prospect_Scholar_Application__c app : Trigger.old) memberIds.add(app.Applicant_Account__c);
    } else {
        for (Prospect_Scholar_Application__c app : Trigger.new) {
            Prospect_Scholar_Application__c prior = Trigger.isUpdate ? Trigger.oldMap.get(app.Id) : null;
            if (prior == null || prior.Applicant_Account__c != app.Applicant_Account__c
                || prior.Application_Status__c != app.Application_Status__c) {
                memberIds.add(app.Applicant_Account__c);
                if (prior != null) memberIds.add(prior.Applicant_Account__c);
            }
        }
    }
    ScholarApplicationMembership.refresh(memberIds);
}
