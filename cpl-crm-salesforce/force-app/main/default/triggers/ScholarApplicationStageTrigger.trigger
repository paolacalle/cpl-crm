trigger ScholarApplicationStageTrigger on Prospect_Scholar_Application__c (before insert, before update) {
    ScholarApplicationStageService.synchronize(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
