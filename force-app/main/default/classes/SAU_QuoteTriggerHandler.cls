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

    // CalculationStatus values meaning the configurator save/recalc just finished
    // (the Save & Exit moment). We hard-block here using the lines touched in
    // THIS save, so the count is accurate and scoped to the configured bundle.
    private static final Set<String> CALC_COMPLETED_STATUSES = new Set<String>{
        'CompletedWithPricing',
        'CompletedWithTax',
        'CompletedWithoutPricing'
    };

    // Statuses at which a quote is finalized — whole-quote backstop so an invalid
    // bundle can never be carried into a finalized quote even if a save slipped.
    private static final Set<String> FINALIZE_STATUSES = new Set<String>{
        'Presented',
        'Approved',
        'Accepted'
    };

    @TestVisible
    private static Set<Id> calcCompletedQuotes(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        Set<Id> ids = new Set<Id>();
        if (newQuotes == null) return ids;
        for (Quote q : newQuotes) {
            if (q.Id == null) continue;
            String oldCalc = (oldMap != null && oldMap.containsKey(q.Id)) ? oldMap.get(q.Id).CalculationStatus : null;
            if (CALC_COMPLETED_STATUSES.contains(q.CalculationStatus) && q.CalculationStatus != oldCalc) {
                ids.add(q.Id);
            }
        }
        return ids;
    }

    @TestVisible
    private static Set<Id> finalizingQuotes(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
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
     * Hard-block an invalid bundle:
     *  - at Save & Exit (CalculationStatus completed) -> validate the bundle just
     *    saved, counting the lines touched in this transaction (accurate, scoped);
     *  - at finalize (Status -> Presented/Approved/Accepted) -> whole-quote backstop.
     */
    public void validateBundleCardinality(List<Quote> newQuotes, Map<Id, Quote> oldMap) {
        Map<Id, List<String>> violations = new Map<Id, List<String>>();

        // Save & Exit: validate the bundle(s) being saved via the touched lines.
        if (!calcCompletedQuotes(newQuotes, oldMap).isEmpty()) {
            mergeViolations(violations,
                SAU_QuoteLineItemTriggerHandler.getTouchedBundleViolations(
                    SAU_QuoteLineItemTriggerHandler.touchedQliIds));
        }

        // Finalize backstop: validate the whole settled quote.
        Set<Id> finalizing = finalizingQuotes(newQuotes, oldMap);
        if (!finalizing.isEmpty()) {
            mergeViolations(violations,
                SAU_QuoteLineItemTriggerHandler.getBundleCardinalityViolations(finalizing));
        }

        if (violations.isEmpty()) return;
        for (Quote q : newQuotes) {
            if (violations.containsKey(q.Id) && !violations.get(q.Id).isEmpty()) {
                Set<String> uniq = new Set<String>(violations.get(q.Id));
                q.addError(String.join(new List<String>(uniq), ' '));
            }
        }
    }

    private static void mergeViolations(Map<Id, List<String>> target, Map<Id, List<String>> additions) {
        for (Id qId : additions.keySet()) {
            if (!target.containsKey(qId)) target.put(qId, new List<String>());
            target.get(qId).addAll(additions.get(qId));
        }
    }
}