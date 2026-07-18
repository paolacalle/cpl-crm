@isTest
private class LeadIntakeSummaryPdfControllerTest {
    private static Id rt(String dev) {
        return [SELECT Id FROM RecordType
                WHERE SobjectType = 'Lead' AND DeveloperName = :dev LIMIT 1].Id;
    }

    private static LeadIntakeSummaryPdfController controllerFor(Id leadId) {
        Test.setCurrentPage(Page.LeadIntakeSummaryPdf);
        ApexPages.currentPage().getParameters().put('id', leadId);
        return new LeadIntakeSummaryPdfController();
    }

    @isTest
    static void scholarBranchAndSchoolFallback() {
        Lead ld = new Lead(
            FirstName = 'Ada', LastName = 'Scholar', Company = 'N/A',
            Email = 'a@e.com', Status = 'New', RecordTypeId = rt('CPL_Scholar_Lead'),
            School_Name_From_Form__c = 'Central High'
        );
        insert ld;

        LeadIntakeSummaryPdfController c = controllerFor(ld.Id);
        System.assert(c.getHasLead(), 'Lead should load');
        System.assert(c.getIsScholar(), 'Should detect scholar record type');
        System.assert(!c.getIsPartner(), 'Should not be partner');
        System.assertEquals('Central High', c.getSchoolDisplay(),
            'School should fall back to the raw form value');
    }

    @isTest
    static void partnerBranchAndMultiselect() {
        // Derive two real, active values from the picklist so the test is org-agnostic.
        List<String> vals = new List<String>();
        for (Schema.PicklistEntry e : Lead.Partnership_Interest__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                vals.add(e.getValue());
            }
            if (vals.size() == 2) {
                break;
            }
        }

        Lead ld = new Lead(
            FirstName = 'Nia', LastName = 'Partner', Company = 'Acme',
            Email = 'n@e.com', Status = 'New', RecordTypeId = rt('Partner_Lead'),
            Partnership_Interest__c = String.join(vals, ';')
        );
        insert ld;

        LeadIntakeSummaryPdfController c = controllerFor(ld.Id);
        System.assert(c.getIsPartner(), 'Should detect partner record type');
        System.assertEquals(String.join(vals, ', '),
            c.getPartnershipInterestDisplay(),
            'Multiselect values should render as a comma list');
    }

    @isTest
    static void nullIdIsSafe() {
        LeadIntakeSummaryPdfController c = controllerFor(null);
        System.assert(!c.getHasLead(), 'No lead should load for a null id');
        System.assert(!c.getIsScholar());
        System.assert(!c.getIsPartner());
        System.assertEquals('', c.getSchoolDisplay());
        System.assertEquals('', c.getPartnershipInterestDisplay());
    }
}
