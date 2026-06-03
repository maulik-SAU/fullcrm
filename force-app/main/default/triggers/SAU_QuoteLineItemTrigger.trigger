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

    // Record the lines touched in this save so the configured bundle can be
    // validated when the save/recalc completes (see SAU_QuoteTriggerHandler).
    // We count the touched (being-saved) lines rather than the deferred
    // ParentQuoteLineItemId links, so the count is accurate at Save & Exit.
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.recordTouched(Trigger.new);
    }
}
