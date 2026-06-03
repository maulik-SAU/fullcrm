trigger SAU_QuoteLineItemTrigger on QuoteLineItem (
    before insert, before update,
    after insert, after update,
    after delete, after undelete
) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.validateQuantityLimits(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUndelete) {
        SAU_QuoteLineItemTriggerHandler.validateQuantityLimits(Trigger.new);
    }
    // Bundle component-group cardinality is validated on AFTER INSERT and
    // AFTER UPDATE. The configurator commits a bundle's children with their
    // ParentQuoteLineItemId already populated, so the per-instance counting in
    // the handler works at insert time. Validating on insert (not just update)
    // is required because a bundle can be created in a transaction that never
    // fires a follow-up update.
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.new, false);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.old, true);
    }
}