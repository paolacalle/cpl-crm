public with sharing class ProspectApplicationEligibilityController {
    @AuraEnabled(cacheable=true)
    public static List<MemberSearchResult> searchMembers(String searchTerm) {
        List<MemberSearchResult> results = new List<MemberSearchResult>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return results;
        }

        String pattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        for (Account member : [
            SELECT Id, Name, PersonEmail
            FROM Account
            WHERE IsPersonAccount = TRUE
            AND Name LIKE :pattern
            ORDER BY Name
            LIMIT 10
        ]) {
            MemberSearchResult result = new MemberSearchResult();
            result.id = member.Id;
            result.name = member.Name;
            result.email = member.PersonEmail;
            results.add(result);
        }
        return results;
    }

    @AuraEnabled(cacheable=true)
    public static MemberEligibilityContext getMemberContext(Id memberId) {
        if (memberId == null) {
            throw new AuraHandledException('Select a CPL member first.');
        }

        Account member = [
            SELECT Id, Name, PersonEmail, IsPersonAccount
            FROM Account
            WHERE Id = :memberId
            LIMIT 1
        ];
        if (!member.IsPersonAccount) {
            throw new AuraHandledException('The selected applicant must be a Person Account.');
        }

        MemberEligibilityContext context = new MemberEligibilityContext();
        context.memberId = member.Id;
        context.memberName = member.Name;
        context.memberEmail = member.PersonEmail;
        context.internships = new List<InternshipOption>();

        for (Employment__c employment : [
            SELECT Id, Employer__r.Name, Job_Title__c, Internship_Season__c,
                   Start_Date__c, End_Date__c, Is_qualifying__c
            FROM Employment__c
            WHERE CPL_Member__c = :memberId
            AND (RecordType.DeveloperName = 'Internship' OR Employment_Type__c = 'Internship')
            ORDER BY Start_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            InternshipOption option = new InternshipOption();
            option.id = employment.Id;
            option.employerName = employment.Employer__r == null ? 'Employer not specified' : employment.Employer__r.Name;
            option.jobTitle = employment.Job_Title__c;
            option.season = employment.Internship_Season__c;
            option.startDate = employment.Start_Date__c;
            option.endDate = employment.End_Date__c;
            option.isQualifying = employment.Is_qualifying__c;
            context.internships.add(option);
        }
        return context;
    }

    @AuraEnabled
    public static Id createApplication(Id memberId, String collegeYear, List<Id> qualifyingInternshipIds) {
        if (memberId == null) {
            throw new AuraHandledException('Select a CPL member before creating an application.');
        }
        if (collegeYear != 'Junior' && collegeYear != 'Senior') {
            throw new AuraHandledException('Only Junior and Senior CPL members are eligible.');
        }
        if (qualifyingInternshipIds == null || qualifyingInternshipIds.isEmpty()) {
            throw new AuraHandledException('Mark at least one internship as qualifying.');
        }

        Account member = [SELECT Id, IsPersonAccount FROM Account WHERE Id = :memberId LIMIT 1];
        if (!member.IsPersonAccount) {
            throw new AuraHandledException('The selected applicant must be a Person Account.');
        }

        Set<Id> selectedIds = new Set<Id>(qualifyingInternshipIds);
        List<Employment__c> internships = [
            SELECT Id, Is_qualifying__c
            FROM Employment__c
            WHERE CPL_Member__c = :memberId
            AND (RecordType.DeveloperName = 'Internship' OR Employment_Type__c = 'Internship')
        ];
        Set<Id> availableIds = new Map<Id, Employment__c>(internships).keySet();
        if (!availableIds.containsAll(selectedIds)) {
            throw new AuraHandledException('One or more selected internships do not belong to this CPL member.');
        }

        List<Employment__c> updates = new List<Employment__c>();
        for (Employment__c internship : internships) {
            Boolean shouldQualify = selectedIds.contains(internship.Id);
            if (internship.Is_qualifying__c != shouldQualify) {
                updates.add(new Employment__c(Id = internship.Id, Is_qualifying__c = shouldQualify));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }

        try {
            Prospect_Scholar_Application__c application = new Prospect_Scholar_Application__c(
                Applicant_Account__c = memberId,
                College_Year__c = collegeYear,
                Application_Status__c = 'Invite Sent'
            );
            insert application;
            return application.Id;
        } catch (DmlException ex) {
            throw new AuraHandledException(ex.getDmlMessage(0));
        }
    }

    public class MemberSearchResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    public class MemberEligibilityContext {
        @AuraEnabled public Id memberId;
        @AuraEnabled public String memberName;
        @AuraEnabled public String memberEmail;
        @AuraEnabled public List<InternshipOption> internships;
    }

    public class InternshipOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String employerName;
        @AuraEnabled public String jobTitle;
        @AuraEnabled public String season;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean isQualifying;
    }
}
