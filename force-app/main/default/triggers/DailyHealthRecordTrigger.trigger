/**
 * @description Trigger for Daily_Health_Record__c object.
 *              Handles before insert and before update events.
 *              - Before Insert: checks for duplicate Contact+Date combinations.
 *              - Before Update: checks for duplicate Contact+Date combinations if Contact or Activity Date changes.
 * @author      Life Activity Companion
 */
trigger DailyHealthRecordTrigger on Daily_Health_Record__c (before insert, before update) {
    DailyHealthRecordTriggerHandler handler = new DailyHealthRecordTriggerHandler();
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            handler.onBeforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
