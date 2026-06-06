trigger FormSubmissionMaterialsTrigger on Form_Submission__c (after insert, after update) {
    ScholarFinalistMaterialsService.handleSubmissions(Trigger.new, Trigger.oldMap);
}
