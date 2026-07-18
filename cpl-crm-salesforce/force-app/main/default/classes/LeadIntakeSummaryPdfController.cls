// "with sharing" enforces the sharing rules of the current user.
// This prevents unauthorized users from generating summaries of records they cannot access.
public with sharing class LeadIntakeSummaryPdfController { 

    // Constants should use the DeveloperName of the Record Type
    public static final String SCHOLAR_RECORD_TYPE = 'CPL_Scholar_Lead'; 
    public static final String PARTNER_RECORD_TYPE = 'Partner_Lead'; 

    // Private read-only variable holds the record instance for the life of the page
    private final Lead leadRecord; 

    // Standard constructor utilized by the Visualforce Page
    public LeadIntakeSummaryPdfController() { 
        Id leadId = (Id)ApexPages.currentPage().getParameters().get('id'); 
        this.leadRecord = loadLead(leadId); 
    } 

    // Overloaded constructor strictly isolated for Unit Tests
    @TestVisible 
    private LeadIntakeSummaryPdfController(Id leadId) { 
        this.leadRecord = loadLead(leadId); 
    } 

    // Helper method to query the Lead data securely
    private static Lead loadLead(Id leadId) { 
        if (leadId == null) { 
            return null; 
        } 
        
        // safer in case no leads
        List<Lead> currentLeads = [ 
            SELECT Id, FirstName, LastName, Name, Email, LeadSource, 
                   Sport_From_Form__c, School_Name_From_Form__c, Why_CPL_Scholar__c, 
                   Commits_to_CPL_mantra__c, Resume_Uploaded__c, Primary_Resume_URL__c, 
                   Partnership_Interest__c, Partner_Interest_Other__c, Partner_Message__c, 
                   RecordType.DeveloperName 
            FROM Lead 
            WHERE Id = :leadId 
            LIMIT 1 
        ]; 
        
        return currentLeads.isEmpty() ? null : currentLeads[0]; 
    } 

    // Getter methods that expose the data
    public Lead getLead() { 
        return this.leadRecord; 
    } 

    public Boolean getHasLead() {
        return this.leadRecord != null;
    }

    
    public Boolean getIsScholar() {
        return (
            this.leadRecord != null &&
            this.leadRecord.RecordType != null &&
            SCHOLAR_RECORD_TYPE.equals(this.leadRecord.RecordType.DeveloperName)
        );
    }

    public Boolean getIsPartner() {
        return (
            this.leadRecord != null &&
            this.leadRecord.RecordType != null &&
            PARTNER_RECORD_TYPE.equals(this.leadRecord.RecordType.DeveloperName)
        );
    }

    public String getSchoolDisplay() {
        if (this.leadRecord == null) {
            return '';
        }

        return (
            this.leadRecord.School_Name_From_Form__c == null 
            ? ''
            : this.leadRecord.School_Name_From_Form__c
        );
    }

    public String getPartnershipInterestDisplay() {
        if (leadRecord == null) {
            return '';
        }
        
        List<String> interests = new List<String>();
        
        // Add picklist values if they exist
        if (String.isNotBlank(leadRecord.Partnership_Interest__c)) {
            interests.addAll(leadRecord.Partnership_Interest__c.split(';'));
        }
        
        // Add "Other" details if they exist
        if (String.isNotBlank(leadRecord.Partner_Interest_Other__c)) {
            interests.add(leadRecord.Partner_Interest_Other__c);
        }
        
        // Join everything nicely with a comma
        return String.join(interests, ', ');
    }

}
