@IsTest
private class SportPicklistOptionsControllerTest {
    @IsTest
    static void returnsLeadPrimarySportOptions() {
        List<SportPicklistOptionsController.PicklistOption> options =
            SportPicklistOptionsController.getLeadPrimarySportOptions();

        System.assert(!options.isEmpty(), 'Expected active Lead Primary Sport picklist options.');
        System.assertNotEquals(null, options[0].label, 'Expected option label.');
        System.assertNotEquals(null, options[0].value, 'Expected option value.');
    }
}