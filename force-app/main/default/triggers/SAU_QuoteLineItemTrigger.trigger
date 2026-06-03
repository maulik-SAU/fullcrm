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

    // Bundle component-group cardinality (min/max) is NOT enforced on this
    // trigger. RLM links bundle children to their parent across deferred steps
    // during a configurator save, so a QuoteLineItem trigger can see an
    // incomplete bundle and false-block a valid one (and a mid-save block leaves
    // the quote in SaveFailedOrIncomplete). It is hard-enforced on the fully
    // settled quote at the finalize checkpoint — see
    // SAU_QuoteTriggerHandler.validateBundleCardinality.
}
