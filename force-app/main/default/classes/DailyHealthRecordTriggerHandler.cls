/**
 * @description Handler class for the DailyHealthRecordTrigger.
 *              Prevents duplicate records: only one Daily Health Record is allowed per Contact per Activity Date.
 *
 *              Bulkified: all SOQL is outside loops; operates on collections throughout.
 * @author      Life Activity Companion
 */
public with sharing class DailyHealthRecordTriggerHandler {

    @TestVisible
    private static final String DUPLICATE_ERROR_MESSAGE =
        'A Daily Health Record for this date already exists. ' +
        'To avoid duplicate entries, only one record is allowed per person per day. ' +
        'Please edit the existing record if you need to add or update information.';

    // ─────────────────────────────────────────────────────────────────────────
    // Public Entry Points
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Handles before-insert logic: checks for duplicates.
     * @param newRecords The list of new Daily_Health_Record__c records being inserted.
     */
    public void onBeforeInsert(List<Daily_Health_Record__c> newRecords) {
        checkDuplicates(newRecords, null);
    }

    /**
     * @description Handles before-update logic: checks for duplicates only when
     *              Contact__c or Activity_Date__c has changed.
     * @param newRecords The updated list of Daily_Health_Record__c records.
     * @param oldRecordMap Map of record Id to old record values.
     */
    public void onBeforeUpdate(
        List<Daily_Health_Record__c> newRecords,
        Map<Id, Daily_Health_Record__c> oldRecordMap
    ) {
        List<Daily_Health_Record__c> changedRecords = new List<Daily_Health_Record__c>();
        for (Daily_Health_Record__c record : newRecords) {
            Daily_Health_Record__c oldRecord = oldRecordMap.get(record.Id);
            if (record.Contact__c != oldRecord.Contact__c ||
                record.Activity_Date__c != oldRecord.Activity_Date__c) {
                changedRecords.add(record);
            }
        }
        if (!changedRecords.isEmpty()) {
            checkDuplicates(changedRecords, oldRecordMap);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Checks the incoming records against existing database records and
     *              other records in the same batch for Contact + Activity Date duplicates.
     *              Adds a field-level error on Activity_Date__c for any duplicate found.
     * @param records    The records to validate.
     * @param oldRecordMap Null on insert; populated on update to allow self-exclusion.
     */
    @TestVisible
    private void checkDuplicates(
        List<Daily_Health_Record__c> records,
        Map<Id, Daily_Health_Record__c> oldRecordMap
    ) {
        // Build key map: "ContactId_ActivityDate" -> list of records with that key
        Map<String, List<Daily_Health_Record__c>> recordsByKey = new Map<String, List<Daily_Health_Record__c>>();
        Set<Id>   contactIds    = new Set<Id>();
        Set<Date> activityDates = new Set<Date>();

        for (Daily_Health_Record__c record : records) {
            if (record.Contact__c == null || record.Activity_Date__c == null) {
                continue;
            }
            String key = buildKey(record.Contact__c, record.Activity_Date__c);
            if (!recordsByKey.containsKey(key)) {
                recordsByKey.put(key, new List<Daily_Health_Record__c>());
            }
            recordsByKey.get(key).add(record);
            contactIds.add(record.Contact__c);
            activityDates.add(record.Activity_Date__c);
        }

        if (recordsByKey.isEmpty()) {
            return;
        }

        // Flag within-batch duplicates (same Contact + Date in same DML operation)
        for (String key : recordsByKey.keySet()) {
            List<Daily_Health_Record__c> batchRecords = recordsByKey.get(key);
            if (batchRecords.size() > 1) {
                for (Integer i = 1; i < batchRecords.size(); i++) {
                    batchRecords[i].Activity_Date__c.addError(DUPLICATE_ERROR_MESSAGE);
                }
            }
        }

        // Query existing database records with overlapping Contact + Date values
        List<Daily_Health_Record__c> existingRecords = [
            SELECT Id, Contact__c, Activity_Date__c
            FROM Daily_Health_Record__c
            WHERE Contact__c IN :contactIds
            AND Activity_Date__c IN :activityDates
        ];

        // Flag database-level duplicates
        for (Daily_Health_Record__c existing : existingRecords) {
            String key = buildKey(existing.Contact__c, existing.Activity_Date__c);
            if (!recordsByKey.containsKey(key)) {
                continue;
            }
            for (Daily_Health_Record__c record : recordsByKey.get(key)) {
                // On update, skip when the existing database record IS the record being updated
                if (oldRecordMap != null && existing.Id == record.Id) {
                    continue;
                }
                record.Activity_Date__c.addError(DUPLICATE_ERROR_MESSAGE);
            }
        }
    }

    /**
     * @description Builds a composite key string from a Contact Id and an Activity Date.
     * @param contactId    The Contact lookup Id.
     * @param activityDate The Activity Date value.
     * @return             A string key in the format "ContactId_YYYY-MM-DD".
     */
    private String buildKey(Id contactId, Date activityDate) {
        return (String) contactId + '_' + String.valueOf(activityDate);
    }
}
