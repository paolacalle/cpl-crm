@IsTest(SeeAllData=true)
private class CplHomeRecentActivityControllerTest {
    @IsTest
    static void returnsBoundedActivityList() {
        List<CplHomeRecentActivityController.ActivityItem> items =
            CplHomeRecentActivityController.getActivity();

        System.assertNotEquals(null, items);
        System.assert(items.size() <= 8, 'Activity list should be capped at 8 items');

        for (CplHomeRecentActivityController.ActivityItem item : items) {
            System.assertNotEquals(null, item.id);
            System.assertNotEquals(null, item.title);
            System.assert(item.objectApiName == 'Lead' || item.objectApiName == 'Prospect_Scholar_Application__c');
        }
    }
}