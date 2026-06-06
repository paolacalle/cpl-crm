@IsTest(SeeAllData=true)
private class CplSchoolRecentActivityControllerTest {
    @IsTest
    static void returnsEmptyActivityForNullSchool() {
        CplSchoolRecentActivityController.SchoolActivity activity =
            CplSchoolRecentActivityController.getActivity(null);

        System.assertNotEquals(null, activity.recentLeads);
        System.assertNotEquals(null, activity.recentApps);
        System.assertEquals(0, activity.recentLeads.size());
        System.assertEquals(0, activity.recentApps.size());
    }

    @IsTest
    static void returnsEmptyActivityForSchoolWithNoLeadsOrApps() {
        RecordType schoolRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'School' LIMIT 1
        ];
        Account school = new Account(
            Name = 'Activity Test School ' + System.now().getTime(),
            RecordTypeId = schoolRt.Id
        );
        insert school;

        CplSchoolRecentActivityController.SchoolActivity activity =
            CplSchoolRecentActivityController.getActivity(school.Id);

        System.assertEquals(0, activity.recentLeads.size());
        System.assertEquals(0, activity.recentApps.size());
    }
}
