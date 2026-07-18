@isTest
private class OrgWideEmailUtilTest {
    @isTest
    static void blankAddressReturnsNull() {
        System.assertEquals(null, OrgWideEmailUtil.getIdByAddress(null));
        System.assertEquals(null, OrgWideEmailUtil.getIdByAddress('   '));
    }

    @isTest
    static void intakeLookupIsCachedAndStable() {
        Id first = OrgWideEmailUtil.getIntakeOrgWideEmailId();
        Id second = OrgWideEmailUtil.getIntakeOrgWideEmailId(); // 2nd call hits the cache
        System.assertEquals(first, second, 'Cached lookup should return a stable value');
    }
}
