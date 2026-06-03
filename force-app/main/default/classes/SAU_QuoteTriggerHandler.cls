public class SAU_QuoteTriggerHandler {

    private static final Set<String> EDITABLE_STATUSES = new Set<String>{
        'Draft',
        'Needs Review',
        'In Review'
    };

    public void applyGSTRate(List<Quote> newQuotes) {

        Map<String, SAU_Revenue_Cloud_Setting__c> allSettings =
            SAU_Revenue_Cloud_Setting__c.getAll();

        if (allSettings.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'No GST setting records found. Skipping GST application.');
            return;
        }

        SAU_Revenue_Cloud_Setting__c gstSetting = allSettings.values()[0];

        if (gstSetting.SAU_GST_Rate__c == null) {
            System.debug(LoggingLevel.WARN,
                'GST rate is blank on the setting record. Skipping.');
            return;
        }

        Decimal gstRate = gstSetting.SAU_GST_Rate__c;

        Set<Id> accountIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        for (Quote q : newQuotes) {
            if (!EDITABLE_STATUSES.contains(q.Status)) {
                continue;
            }
            if (q.OpportunityId != null) {
                opportunityIds.add(q.OpportunityId);
            }
        }

        Map<Id, Id> oppIdToAccountId = new Map<Id, Id>();
        if (!opportunityIds.isEmpty()) {
            for (Opportunity opp : [
                SELECT Id, AccountId
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]) {
                if (opp.AccountId != null) {
                    oppIdToAccountId.put(opp.Id, opp.AccountId);
                    accountIds.add(opp.AccountId);
                }
            }
        }

        Map<Id, Account> accountsById = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountsById = new Map<Id, Account>([
                SELECT Id, BillingCountry
                FROM Account
                WHERE Id IN :accountIds
            ]);
        }

        for (Quote q : newQuotes) {

            if (!EDITABLE_STATUSES.contains(q.Status)) {
                continue;
            }

            Id effectiveAccountId = oppIdToAccountId.get(q.OpportunityId);

            Boolean isAustralia = false;
            if (effectiveAccountId != null && accountsById.containsKey(effectiveAccountId)) {
                Account acct = accountsById.get(effectiveAccountId);
                String country = (acct.BillingCountry != null) ? acct.BillingCountry.trim() : null;
                // String countryCode = (acct.BillingCountryCode != null) ? acct.BillingCountryCode.trim() : null;

                if ((country != null &&
                        (country.equalsIgnoreCase('Australia')
                         || country.equalsIgnoreCase('AU')
                         || country.equalsIgnoreCase('AUS')))) {
                    // || (countryCode != null && countryCode.equalsIgnoreCase('AU'))) {
                    isAustralia = true;
                }
            }

            q.SAU_GST_Applied__c = isAustralia ? gstRate : 0;
        }
    }

    public void calculateTax(List<Quote> newQuotes) {
        for (Quote q : newQuotes) {
            Decimal subtotal = (q.Subtotal != null) ? q.Subtotal : 0;
            Decimal rate = (q.SAU_GST_Applied__c != null) ? q.SAU_GST_Applied__c : 0;

            q.Tax = ((subtotal * rate) / 100).setScale(2);
        }
    }

    // Statuses at which a quote is finalized. Bundle component-group min/max is
    // hard-enforced when a quote moves INTO one of these. This runs on the
    // fully-settled quote (a deliberate status change, not the RLM configurator
    // save), so every bundle is completely linked and the counts are exact — and
    // it does NOT interfere with the configurator save (no false blocks / no
    // SaveFailedOrIncomplete). The configurator itself shows RLM's native
    // "select at least N" soft warning while building.
    private static final Set<String> FINALIZE_STATUSES = new Set<String>{
        'Presented',
        'Approved',
        'Accepted'
    };

    @TestVisible
    private static Set<Id> quotesToValidate(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (newQuotes == null) return ids;
        for (Quote q : newQuotes) {
            if (q.Id == null) continue;
            String oldStatus = (oldMap != null && oldMap.containsKey(q.Id)) ? oldMap.get(q.Id).Status : null;
            if (FINALIZE_STATUSES.contains(q.Status) && q.Status != oldStatus) {
                ids.add(q.Id);
            }
        }
        return ids;
    }

    /**
     * Hard-block finalizing a quote that has any bundle breaching a component
     * group min/max. Runs on the settled quote at the status checkpoint.
     */
    public void validateBundleCardinality(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        Set<Id> quoteIdsToCheck = quotesToValidate(newQuotes, oldMap);
        if (quoteIdsToCheck.isEmpty()) return;

        Map<Id, List<String>> violations =
            SAU_QuoteLineItemTriggerHandler.getBundleCardinalityViolations(quoteIdsToCheck);
        if (violations.isEmpty()) return;

        for (Quote q : newQuotes) {
            if (violations.containsKey(q.Id) && !violations.get(q.Id).isEmpty()) {
                q.addError(String.join(violations.get(q.Id), ' '));
            }
        }
    }
}