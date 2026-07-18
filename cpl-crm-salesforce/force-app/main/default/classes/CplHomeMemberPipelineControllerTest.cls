@IsTest
private class CplHomeMemberPipelineControllerTest {

    @TestSetup
    static void setup() {
        // Pick a person-type record type that is actually assigned to the running
        // user's profile. Grabbing an arbitrary one (LIMIT 1) can return a record
        // type the user can't use -> INVALID_CROSS_REFERENCE_KEY on insert.
        Set<Id> personTypeRtIds = new Map<Id, RecordType>([
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = TRUE
        ]).keySet();

        Id personRt = null;
        for (Schema.RecordTypeInfo rti : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (personTypeRtIds.contains(rti.getRecordTypeId()) && rti.isAvailable()) {
                personRt = rti.getRecordTypeId();
                break;
            }
        }
        System.assertNotEquals(null, personRt, 'No person-account record type is available to the running user');

        List<Account> people = new List<Account>{
            new Account(LastName = 'Scholar One',   RecordTypeId = personRt, PersonEmail = 'scholar.one@example.com',   CPL_Student_Lifecycle__c = 'Scholar'),
            new Account(LastName = 'Scholar Two',   RecordTypeId = personRt, PersonEmail = 'scholar.two@example.com',   CPL_Student_Lifecycle__c = 'Scholar'),
            new Account(LastName = 'Applicant One', RecordTypeId = personRt, PersonEmail = 'applicant.one@example.com', CPL_Student_Lifecycle__c = 'Applicant'),
            // person account with no lifecycle -> must be excluded (CPL_Student_Lifecycle__c != null).
            // Set null explicitly: the field defaults to 'Athlete', so omitting it would
            // let the platform apply that default and wrongly count this as an Athlete.
            new Account(LastName = 'No Lifecycle',  RecordTypeId = personRt, PersonEmail = 'no.lifecycle@example.com', CPL_Student_Lifecycle__c = null)
        };
        insert people;
        // Note: business accounts are excluded structurally by the controller's
        // IsPersonAccount = TRUE filter, so we don't insert one here -- doing so only
        // trips unrelated Company/Employer validation rules with no added coverage.
    }

    @IsTest
    static void returnsEveryStageInLifecycleOrderWithCounts() {
        Test.startTest();
        List<CplHomeMemberPipelineController.StatusCount> result =
            CplHomeMemberPipelineController.getPipeline();
        Test.stopTest();

        // Must match CplHomeMemberPipelineController.STATUS_ORDER (Prospect and
        // Inactive are intentionally excluded there).
        List<String> expectedOrder = new List<String>{
            'Athlete', 'Applicant', 'Scholar', 'Scholar Alumni', 'Alumni'
        };
        System.assertEquals(expectedOrder.size(), result.size(), 'One entry per lifecycle stage');

        Map<String, Integer> countByStatus = new Map<String, Integer>();
        for (Integer i = 0; i < result.size(); i++) {
            System.assertEquals(expectedOrder[i], result[i].status, 'Stages must be returned in lifecycle order');
            countByStatus.put(result[i].status, result[i].count);
        }

        System.assertEquals(2, countByStatus.get('Scholar'),   'Two scholars inserted');
        System.assertEquals(1, countByStatus.get('Applicant'), 'One applicant inserted');
        System.assertEquals(0, countByStatus.get('Athlete'),   'Empty stage reports zero');
    }
}
