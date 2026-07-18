/**
 * @description Utility class for retrieving distinct active User email addresses 
 * associated with specific Salesforce Public Groups or Queues.
 * Supports up to one level of nested public group structures.
 *
 * @group Utilities
 */

public inherited sharing class GetGroupTeamEmailsUtils {

    /**
     * @description Retrieves active user email addresses belonging to specified groups or queues.
     * @param groupNames Set of Group DeveloperNames to evaluate.
     * @param type The type of group (e.g., 'Regular' for Public Groups, 'Queue' for Queues).
     * @return Set<String> A unique set of active user email addresses. Returns an empty set if none found.
     */
    public static Set<String> getTeamEmails(Set<String> groupNames, String type) {
        if (groupNames == null || groupNames.isEmpty() || String.isBlank(type)) {
            return new Set<String>();
        }

        Set<Id> groupIds = new Set<Id>();
        Set<Id> nestedGroupIds = new Set<Id>();

        List<GroupMember> primaryMembers = [
            SELECT UserOrGroupId 
            FROM GroupMember 
            WHERE Group.DeveloperName IN :groupNames AND Group.Type = :type
        ];

        for (GroupMember gm : primaryMembers) {
            if (gm.UserOrGroupId.getSObjectType() == User.SObjectType) {
                userIds.add(gm.UserOrGroupId);
            } else {
                nestedGroupIds.add(gm.UserOrGroupId);
            }
        }

        // Evaluate one level of nested public groups
        if (!nestedGroupIds.isEmpty()) {
            List<GroupMember> nestedMembers = [
                SELECT UserOrGroupId 
                FROM GroupMember 
                WHERE GroupId IN :nestedGroupIds
            ];

            for (GroupMember gm : nestedMembers) {
                if (gm.UserOrGroupId.getSObjectType() == User.SObjectType) {
                    userIds.add(gm.UserOrGroupId);
                }
            }
        }

        if (userIds.isEmpty()) {
            return new Set<String>();
        }

        // Fetch distinct, valid email addresses for all active users found
        Set<String> emails = new Set<String>();
        List<User> activeUsers = [
            SELECT Email 
            FROM User 
            WHERE Id IN :userIds AND IsActive = true AND Email != null
        ];

        for (User u : activeUsers) {
            emails.add(u.Email);
        }

        return emails;
    }
}