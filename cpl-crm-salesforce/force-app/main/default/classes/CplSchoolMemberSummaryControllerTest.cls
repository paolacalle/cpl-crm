@IsTest(SeeAllData=true)
private class CplSchoolMemberSummaryControllerTest {
    @IsTest
    static void returnsZeroSummaryForNullSchool() {
        CplSchoolMemberSummaryController.SchoolSummary summary =
            CplSchoolMemberSummaryController.getSummary(null);

        System.assertEquals(0, summary.total);
        System.assertNotEquals(null, summary.byLifecycle);
        System.assertNotEquals(null, summary.bySport);
        System.assertNotEquals(null, summary.byCollegeYear);
    }

    @IsTest
    static void returnsEmptySummaryForSchoolWithNoMembers() {
        RecordType schoolRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'School' LIMIT 1
        ];
        Account school = new Account(
            Name = 'Summary Test School ' + System.now().getTime(),
            RecordTypeId = schoolRt.Id
        );
        insert school;

        CplSchoolMemberSummaryController.SchoolSummary summary =
            CplSchoolMemberSummaryController.getSummary(school.Id);

        System.assertEquals(0, summary.total);
        System.assertEquals(0, summary.byLifecycle.size());
        System.assertEquals(0, summary.bySport.size());
        System.assertEquals(0, summary.byCollegeYear.size());
    }
}