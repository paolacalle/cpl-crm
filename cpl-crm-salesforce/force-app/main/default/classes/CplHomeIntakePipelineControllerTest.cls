@IsTest(SeeAllData=true)
private class CplHomeIntakePipelineControllerTest {
    @IsTest
    static void returnsAllSixStatusesInOrder() {
        List<CplHomeIntakePipelineController.StatusCount> counts =
            CplHomeIntakePipelineController.getPipeline();

        System.assertEquals(6, counts.size(), 'Should always return exactly 6 status rows');
        System.assertEquals('New', counts[0].status);
        System.assertEquals('In Intake Review', counts[1].status);
        System.assertEquals('Contacted', counts[2].status);
        System.assertEquals('Qualified', counts[3].status);
        System.assertEquals('Unqualified', counts[4].status);
        System.assertEquals('Converted', counts[5].status);

        for (CplHomeIntakePipelineController.StatusCount c : counts) {
            System.assert(c.count >= 0, 'Counts must be non-negative');
        }
    }
}
