trigger SAU_QuoteTrigger on Quote (before insert, before update) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SAU_QuoteTriggerHandler handler = new SAU_QuoteTriggerHandler();
    	handler.applyGSTRate(Trigger.new);
        handler.calculateTax(Trigger.new);
    }
	
}
