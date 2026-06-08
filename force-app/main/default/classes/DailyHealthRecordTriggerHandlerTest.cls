/**
 * @description Test class for DailyHealthRecordTriggerHandler and DailyHealthRecordTrigger.
 *              Covers name auto-population, duplicate prevention (insert + update),
 *              within-batch duplicate detection, bulk operations, and edge cases.
 *              Achieves 90%+ coverage of DailyHealthRecordTriggerHandler.
 * @author      Life Activity Companion
 */
@IsTest
private class DailyHealthRecordTriggerHandlerTest {

    // ─────────────────────────────────────────────────────────────────────────
    // Test Data Setup
    // ─────────────────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 6; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName  = 'Contact' + i
            ));
        }
        insert contacts;
    }

    private static Contact getContact(Integer index) {
        return [SELECT Id FROM Contact WHERE LastName = :('Contact' + index) LIMIT 1];
    }

    private static List<Contact> getAllContacts() {
        return [SELECT Id FROM Contact ORDER BY LastName ASC];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Name Auto-Population — Insert Tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testName_SingleRecord_FormattedYYYY_MM_DD() {
        Contact contact = getContact(0);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 6, 8)
        );

        Test.startTest();
        insert record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Name FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('2026_06_08', result.Name,
            'Name should be formatted as YYYY_MM_DD');
    }

    @IsTest
    static void testName_SingleDigitMonthDay_ZeroPadded() {
        Contact contact = getContact(1);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 1, 5)
        );

        Test.startTest();
        insert record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Name FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('2026_01_05', result.Name,
            'Single-digit month and day must be zero-padded');
    }

    @IsTest
    static void testName_DecemberThirtyFirst_FormattedCorrectly() {
        Contact contact = getContact(2);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 12, 31)
        );

        Test.startTest();
        insert record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Name FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('2026_12_31', result.Name,
            'December 31st should format as 2026_12_31');
    }

    @IsTest
    static void testName_NotOverwrittenOnUpdate() {
        Contact contact = getContact(0);
        Date date1 = Date.newInstance(2026, 3, 15);
        Date date2 = Date.newInstance(2026, 3, 20);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = date1
        );
        insert record;

        String nameAfterInsert = [SELECT Name FROM Daily_Health_Record__c WHERE Id = :record.Id].Name;
        Assert.areEqual('2026_03_15', nameAfterInsert, 'Name after insert should be 2026_03_15');

        record.Activity_Date__c = date2;
        record.Breakfast__c     = 'Oatmeal';

        Test.startTest();
        update record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Name FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('2026_03_15', result.Name,
            'Name should not be overwritten on update — only set on insert');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Duplicate Prevention — Insert Tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testInsert_Duplicate_ThrowsDmlException() {
        Contact contact = getContact(0);
        Date activityDate = Date.newInstance(2026, 6, 10);

        insert new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = activityDate
        );

        Daily_Health_Record__c duplicate = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = activityDate
        );

        Test.startTest();
        try {
            insert duplicate;
            Assert.fail('DmlException expected for duplicate Contact + Activity Date');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('already exists'),
                'Error message should indicate record already exists');
        }
        Test.stopTest();
    }

    @IsTest
    static void testInsert_SameDate_DifferentContacts_BothSucceed() {
        List<Contact> contacts = getAllContacts();
        Date activityDate = Date.newInstance(2026, 6, 12);

        insert new Daily_Health_Record__c(
            Contact__c       = contacts[0].Id,
            Activity_Date__c = activityDate
        );

        Daily_Health_Record__c record2 = new Daily_Health_Record__c(
            Contact__c       = contacts[1].Id,
            Activity_Date__c = activityDate
        );

        Test.startTest();
        insert record2;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Daily_Health_Record__c WHERE Activity_Date__c = :activityDate];
        Assert.areEqual(2, count,
            'Different contacts are allowed to have records on the same date');
    }

    @IsTest
    static void testInsert_SameContact_DifferentDates_BothSucceed() {
        Contact contact = getContact(0);

        insert new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 6, 1)
        );

        Daily_Health_Record__c record2 = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 6, 2)
        );

        Test.startTest();
        insert record2;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Daily_Health_Record__c WHERE Contact__c = :contact.Id];
        Assert.areEqual(2, count,
            'Same contact can have records on different dates');
    }

    @IsTest
    static void testInsert_WithinBatchDuplicate_ThrowsDmlException() {
        Contact contact = getContact(0);
        Date activityDate = Date.newInstance(2026, 7, 1);

        List<Daily_Health_Record__c> batch = new List<Daily_Health_Record__c>{
            new Daily_Health_Record__c(Contact__c = contact.Id, Activity_Date__c = activityDate),
            new Daily_Health_Record__c(Contact__c = contact.Id, Activity_Date__c = activityDate)
        };

        Test.startTest();
        try {
            insert batch;
            Assert.fail('DmlException expected for within-batch duplicate');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('already exists'),
                'Error message should indicate duplicate within the same batch');
        }
        Test.stopTest();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Duplicate Prevention — Update Tests
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testUpdate_ChangeDateToExisting_ThrowsDmlException() {
        Contact contact = getContact(0);
        Date date1 = Date.newInstance(2026, 8, 1);
        Date date2 = Date.newInstance(2026, 8, 2);

        insert new List<Daily_Health_Record__c>{
            new Daily_Health_Record__c(Contact__c = contact.Id, Activity_Date__c = date1),
            new Daily_Health_Record__c(Contact__c = contact.Id, Activity_Date__c = date2)
        };

        Daily_Health_Record__c record2 = [
            SELECT Id, Activity_Date__c FROM Daily_Health_Record__c
            WHERE Contact__c = :contact.Id AND Activity_Date__c = :date2
        ];
        record2.Activity_Date__c = date1;

        Test.startTest();
        try {
            update record2;
            Assert.fail('DmlException expected when updating date to one that already has a record');
        } catch (DmlException ex) {
            Assert.isTrue(ex.getMessage().contains('already exists'),
                'Error should indicate duplicate on update');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdate_ChangeDateToNew_Succeeds() {
        Contact contact = getContact(0);
        Date originalDate = Date.newInstance(2026, 9, 1);
        Date newDate      = Date.newInstance(2026, 9, 5);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = originalDate
        );
        insert record;

        record.Activity_Date__c = newDate;

        Test.startTest();
        update record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Activity_Date__c FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual(newDate, result.Activity_Date__c,
            'Updating to a date with no existing record should succeed');
    }

    @IsTest
    static void testUpdate_NonKeyFieldOnly_Succeeds() {
        Contact contact = getContact(0);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = Date.newInstance(2026, 10, 10),
            Breakfast__c     = 'Eggs'
        );
        insert record;

        record.Breakfast__c = 'Oatmeal and fruit';

        Test.startTest();
        update record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Breakfast__c FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('Oatmeal and fruit', result.Breakfast__c,
            'Updating a non-key field should succeed without duplicate checks');
    }

    @IsTest
    static void testUpdate_SameContactAndDate_Succeeds() {
        Contact contact = getContact(0);
        Date activityDate = Date.newInstance(2026, 11, 11);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c       = contact.Id,
            Activity_Date__c = activityDate,
            Lunch__c         = 'Salad'
        );
        insert record;

        // Update keeping same Contact and Activity Date — should not trigger duplicate error
        record.Lunch__c = 'Grilled chicken salad';

        Test.startTest();
        update record;
        Test.stopTest();

        Daily_Health_Record__c result = [SELECT Lunch__c FROM Daily_Health_Record__c WHERE Id = :record.Id];
        Assert.areEqual('Grilled chicken salad', result.Lunch__c,
            'Updating while keeping the same Contact+Date should not be treated as a duplicate');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bulk Tests (251+ records)
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testBulkInsert_251UniqueRecords_AllSucceed() {
        Contact contact = getContact(0);
        List<Daily_Health_Record__c> records = new List<Daily_Health_Record__c>();

        for (Integer i = 0; i < 251; i++) {
            records.add(new Daily_Health_Record__c(
                Contact__c       = contact.Id,
                Activity_Date__c = Date.newInstance(2020, 1, 1).addDays(i)
            ));
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Daily_Health_Record__c WHERE Contact__c = :contact.Id];
        Assert.areEqual(251, count,
            'All 251 unique bulk records should be inserted successfully');
    }

    @IsTest
    static void testBulkInsert_NamesAllFormatted() {
        Contact contact = getContact(1);
        List<Daily_Health_Record__c> records = new List<Daily_Health_Record__c>();

        Date startDate = Date.newInstance(2025, 1, 1);
        for (Integer i = 0; i < 12; i++) {
            records.add(new Daily_Health_Record__c(
                Contact__c       = contact.Id,
                Activity_Date__c = startDate.addDays(i)
            ));
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        List<Daily_Health_Record__c> results = [
            SELECT Name, Activity_Date__c
            FROM Daily_Health_Record__c
            WHERE Contact__c = :contact.Id
            ORDER BY Activity_Date__c ASC
        ];

        Assert.areEqual(12, results.size(), 'All 12 records should be inserted');
        for (Daily_Health_Record__c result : results) {
            String expectedName =
                String.valueOf(result.Activity_Date__c.year()) + '_' +
                String.valueOf(result.Activity_Date__c.month()).leftPad(2, '0') + '_' +
                String.valueOf(result.Activity_Date__c.day()).leftPad(2, '0');
            Assert.areEqual(expectedName, result.Name,
                'Name should match YYYY_MM_DD format for date: ' + result.Activity_Date__c);
        }
    }

    @IsTest
    static void testBulkInsert_MultipleContactsSameDate_AllSucceed() {
        List<Contact> contacts = getAllContacts();
        Date sharedDate = Date.newInstance(2026, 5, 20);
        List<Daily_Health_Record__c> records = new List<Daily_Health_Record__c>();

        for (Contact contact : contacts) {
            records.add(new Daily_Health_Record__c(
                Contact__c       = contact.Id,
                Activity_Date__c = sharedDate
            ));
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Daily_Health_Record__c WHERE Activity_Date__c = :sharedDate];
        Assert.areEqual(contacts.size(), count,
            'Each contact should have one record for the shared date');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Edge Cases
    // ─────────────────────────────────────────────────────────────────────────

    @IsTest
    static void testInsert_AllFields_Populated() {
        Contact contact = getContact(0);

        Daily_Health_Record__c record = new Daily_Health_Record__c(
            Contact__c             = contact.Id,
            Activity_Date__c       = Date.newInstance(2026, 6, 15),
            Breakfast__c           = 'Eggs and toast',
            Lunch__c               = 'Chicken salad',
            Dinner__c              = 'Pasta',
            Snacks__c              = 'Apple',
            Water_Intake_Liters__c = 2.5,
            Walking_Distance_KM__c = 5.25,
            Exercise_Notes__c      = '30 min yoga',
            Weight_KG__c           = 72.50,
            Source__c              = 'Voice'
        );

        Test.startTest();
        insert record;
        Test.stopTest();

        Daily_Health_Record__c result = [
            SELECT Name, Activity_Date__c, Breakfast__c, Weight_KG__c, Source__c
            FROM Daily_Health_Record__c WHERE Id = :record.Id
        ];
        Assert.areEqual('2026_06_15', result.Name, 'Name should be formatted correctly');
        Assert.areEqual(Date.newInstance(2026, 6, 15), result.Activity_Date__c, 'Activity Date should be saved');
        Assert.areEqual('Eggs and toast', result.Breakfast__c, 'Breakfast should be saved');
        Assert.areEqual(72.50, result.Weight_KG__c, 'Weight KG should be saved');
        Assert.areEqual('Voice', result.Source__c, 'Source should be saved');
    }
}