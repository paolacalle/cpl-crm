// System context is intentional: a hidden application must still count toward the
// stored Account flag. Only this derived flag is written; lifecycle is untouched.
public without sharing class ScholarApplicationMembership {
    public static void refresh(Set<Id> memberIds) {
        memberIds.remove(null);
        if (memberIds.isEmpty()) return;
        // Serialize recalculation on each parent before reading its applications.
        List<Account> members = [
            SELECT Id, Has_Active_Scholarship_Application__c
            FROM Account WHERE Id IN :memberIds FOR UPDATE
        ];
        Set<Id> activeMembers = new Set<Id>();
        Set<String> closedStatuses = new Set<String>{'Accepted', 'Rejected', 'Withdrawn'};
        for (AggregateResult row : [
            SELECT Applicant_Account__c memberId FROM Prospect_Scholar_Application__c
            WHERE Applicant_Account__c IN :memberIds
            AND (Application_Status__c = null OR Application_Status__c NOT IN :closedStatuses)
            GROUP BY Applicant_Account__c
        ]) {
            activeMembers.add((Id) row.get('memberId'));
        }
        List<Account> updates = new List<Account>();
        for (Account member : members) {
            Boolean hasActive = activeMembers.contains(member.Id);
            if (member.Has_Active_Scholarship_Application__c != hasActive) {
                updates.add(new Account(Id = member.Id, Has_Active_Scholarship_Application__c = hasActive));
            }
        }
        if (!updates.isEmpty()) update updates;
    }
}
