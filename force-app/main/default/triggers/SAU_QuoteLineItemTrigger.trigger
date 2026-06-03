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

    // Record which lines changed in this save so the Quote-level bundle check
    // (which runs when the save/recalc completes) can validate ONLY the bundle
    // being configured. Bundle cardinality is NOT enforced on this trigger:
    // RLM links bundle children to their parent across deferred steps during a
    // configurator save, so a QuoteLineItem trigger cannot reliably see a
    // bundle's full membership at save time. See
    // SAU_QuoteTriggerHandler.validateBundleCardinality.
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.recordTouched(Trigger.new, false);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        SAU_QuoteLineItemTriggerHandler.recordTouched(Trigger.old, true);
    }
}
