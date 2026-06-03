trigger SAU_QuoteLineItemTrigger on QuoteLineItem (
    before insert, before update,
    after insert, after update,
    after delete, after undelete
) {
    // Per-line quantity limits are reliable at line level and stay here.
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.validateQuantityLimits(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUndelete) {
        SAU_QuoteLineItemTriggerHandler.validateQuantityLimits(Trigger.new);
    }

    // NOTE: bundle component-group cardinality (min/max) is intentionally NOT
    // enforced here. RLM links bundle children to their parent across deferred
    // steps during a configurator save, so a QuoteLineItem trigger cannot
    // reliably see a bundle's full membership at save time (it produced
    // inconsistent false positives/negatives). That check now runs on the Quote
    // at the finalize checkpoint — see SAU_QuoteTriggerHandler.validateBundleCardinality.
}
