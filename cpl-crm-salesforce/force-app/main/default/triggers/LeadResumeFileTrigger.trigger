trigger LeadResumeFileTrigger on Lead (after insert, after update) {
    LeadResumeFileService.enqueueForLeads(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
