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
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.new, false);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        SAU_QuoteLineItemTriggerHandler.validateBundleProduct(Trigger.old, true);
    }
}