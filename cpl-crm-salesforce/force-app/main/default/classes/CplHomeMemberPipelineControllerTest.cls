@IsTest
private class CplHomeMemberPipelineControllerTest {

    @TestSetup
    static void setup() {
        Id personRt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = TRUE
            LIMIT 1
        ].Id;

        List<Account> people = new List<Account>{
            new Account(LastName = 'Scholar One',   RecordTypeId = personRt, CPL_Student_Lifecycle__c = 'Scholar'),
            new Account(LastName = 'Scholar Two',   RecordTypeId = personRt, CPL_Student_Lifecycle__c = 'Scholar'),
            new Account(LastName = 'Applicant One', RecordTypeId = personRt, CPL_Student_Lifecycle__c = 'Applicant'),
            // person account with no lifecycle -> must be excluded
            new Account(LastName = 'No Lifecycle',  RecordTypeId = personRt)
        };
        insert people;

        // business account -> not a person account, must be excluded
        insert new Account(Name = 'Some Org');
    }

    @IsTest
    static void returnsEveryStageInLifecycleOrderWithCounts() {
        Test.startTest();
        List<CplHomeMemberPipelineController.StatusCount> result =
            CplHomeMemberPipelineController.getPipeline();
        Test.stopTest();

        List<String> expectedOrder = new List<String>{
            'Athlete', 'Prospect', 'Applicant', 'Scholar', 'Scholar Alumni', 'Alumni', 'Inactive'
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
