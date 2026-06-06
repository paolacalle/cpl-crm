trigger ContentDocumentLinkMaterialsTrigger on ContentDocumentLink (after insert) {
    ScholarFinalistMaterialsService.handleFileLinks(Trigger.new);
}
