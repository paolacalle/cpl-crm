/**
 * @description Utility class for securely retrieving and caching Org-Wide Email Address IDs.
 * Provides central management of organization email identities to prevent hardcoding across codebases.
 * Implements a lazy-loaded static map to ensure each email address is queried at most once per transaction,
 * mitigating SOQL governor limit risks in bulk processing contexts.
 *
 * @group Utilities
 * @see OrgWideEmailAddress
 */
public inherited sharing class OrgWideEmailUtil {

    @TestVisible 
    private static final String INTAKE_EMAIL_ADDRESS = 'crm-intake@climbpauselift.org';

    // Per-transaction cache for queried email addresses
    // Belongs to the class runtime, meaning it persists across the entire single execution transaction
    private static final Map<String, Id> idByAddress = new Map<String, Id>();

    /**
     * @description Retrieves the OrgWideEmailAddress ID for a given email address string.
     * Checks the internal per-transaction cache before executing a database query.
     * @param address The email address string to look up.
     * @return Id The 18-character Salesforce ID of the OrgWideEmailAddress record, or null if blank or not found.
     */
    public static Id getIdByAddress(String address) {
        if (String.isBlank(address)) {
            return null;
        }

        if (!idByAddress.containsKey(address)) {
            List<OrgWideEmailAddress> addresses = [
                SELECT Id FROM OrgWideEmailAddress WHERE Address = :address LIMIT 1
            ];

            idByAddress.put(
                address,
                addresses.size() > 0 ? addresses[0].Id : null
            );
        }

        return idByAddress.get(address);
    }

    /**
     * @description Convenience method specifically for retrieving the Intake sender identity.
     * Safely routes through the cached lookup method to enforce lazy-loading behavior.
     * @return Id The 18-character Salesforce ID of the central intake OrgWideEmailAddress.
     */
    public static Id getIntakeOrgWideEmailId() {
        // Call the query method instead of hitting the map directly to ensure it loads
        return getIdByAddress(INTAKE_EMAIL_ADDRESS);
    }
}
