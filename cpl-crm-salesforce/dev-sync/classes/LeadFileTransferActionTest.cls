@IsTest
private class LeadFileTransferActionTest {
    @IsTest
    static void transfersFilesToTarget() {
        Lead leadRecord = new Lead(
            FirstName = 'File',
            LastName = 'Move',
            Company = 'CPL',
            Status = 'New'
        );
        insert leadRecord;

        ContentVersion version = new ContentVersion(
            Title = 'Resume - File Move.pdf',
            PathOnClient = 'Resume - File Move.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = leadRecord.Id
        );
        insert version;

        // Target is object-agnostic for the relink logic; use a Lead to avoid unrelated
        // Account validation rules in this org.
        Lead target = new Lead(
            FirstName = 'Target',
            LastName = 'Member',
            Company = 'CPL',
            Status = 'New'
        );
        insert target;

        LeadFileTransferAction.Request req = new LeadFileTransferAction.Request();
        req.leadId = leadRecord.Id;
        req.targetId = target.Id;

        Test.startTest();
        LeadFileTransferAction.transfer(new List<LeadFileTransferAction.Request>{ req });
        // Re-run is a no-op (already linked) and must not create duplicates.
        LeadFileTransferAction.transfer(new List<LeadFileTransferAction.Request>{ req });
        Test.stopTest();

        Integer links = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :target.Id
        ];
        System.assertEquals(1, links, 'The lead file should be linked once to the target');
    }
}