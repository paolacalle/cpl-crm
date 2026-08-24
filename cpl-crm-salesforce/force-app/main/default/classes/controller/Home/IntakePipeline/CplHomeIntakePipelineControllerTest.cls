@IsTest(SeeAllData=true)
private class CplHomeIntakePipelineControllerTest {
    @IsTest
    static void returnsPipelineStatusesInOrder() {
        List<CplHomeIntakePipelineController.StatusCount> counts =
            CplHomeIntakePipelineController.getPipeline();

        System.assertEquals(3, counts.size(), 'Should always return exactly 3 active pipeline rows');
        System.assertEquals('New', counts[0].status);
        System.assertEquals('Contacting', counts[1].status);
        System.assertEquals('Decision', counts[2].status);

        for (CplHomeIntakePipelineController.StatusCount c : counts) {
            System.assert(c.count >= 0, 'Counts must be non-negative');
        }
    }
}