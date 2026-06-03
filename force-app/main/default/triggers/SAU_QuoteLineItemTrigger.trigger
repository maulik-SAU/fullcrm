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
    // Bundle component-group cardinality is validated on AFTER UPDATE only.
    // RLM creates the QuoteLineRelationship rows AFTER the initial QuoteLineItem
    // insert, so the relationships (which tell us which child belongs to which
    // bundle instance) only exist by the update pass. Validating on after insert
    // produced false errors for duplicate bundles.
    if (Trigger.isAfter && Trigger.isUpdate) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.new, false);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.old, true);
    }
}