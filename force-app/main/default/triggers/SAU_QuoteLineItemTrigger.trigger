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

    // Record the lines INSERTED in this save (the bundle being added/configured)
    // so it can be validated when the save completes. We deliberately do NOT
    // record on update: a configurator save runs a full-quote recalc that
    // updates EVERY line, which would otherwise pull unrelated/leftover bundles
    // into the check. The configured bundle's lines are always inserted.
    if (Trigger.isAfter && Trigger.isInsert) {
        SAU_QuoteLineItemTriggerHandler.recordTouched(Trigger.new);
    }
}
