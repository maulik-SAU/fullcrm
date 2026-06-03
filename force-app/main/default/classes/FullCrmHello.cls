/**
 * Placeholder Apex class for the fullcrm package.
 *
 * Confirms the SFDX project deploys cleanly to a connected Salesforce org.
 * Replace with real CRM logic as the project grows.
 */
public with sharing class FullCrmHello {
    /**
     * @return A greeting string used to verify deployment to the org.
     */
    public static String greeting() {
        return 'fullcrm connected to ' + UserInfo.getOrganizationName();
    }
}
