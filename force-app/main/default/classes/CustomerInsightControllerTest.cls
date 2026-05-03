@IsTest
private class CustomerInsightControllerTest {

    @IsTest
    static void returnsPersonalizedProfileForKnownCustomer() {
        Contact contact = new Contact(
            FirstName = 'Ava',
            LastName = 'Stone',
            Email = 'ava@example.com',
            Phone = '9999999999',
            MailingPostalCode = '560001',
            PreferredVehicleModel__c = 'Electra Storm'
        );
        insert contact;

        Lead lead = new Lead(
            FirstName = 'Ava',
            LastName = 'Stone',
            Email = 'ava@example.com',
            Phone = '9999999999',
            Company = 'Electra Prospect',
            Status = 'Open - Not Contacted',
            PostalCode = '560001'
        );
        insert lead;

        TestDrive__c drive = new TestDrive__c(
            VehicleModel__c = 'Electra Apex',
            PreferredDate__c = Date.today().addDays(5),
            PreferredTime__c = 'Morning (9AM-12PM)',
            ZipCode__c = '560001',
            Available_Slots__c = System.now().addDays(5),
            Status__c = 'Pending',
            PreferredChannel__c = 'WhatsApp',
            CustomerEmail__c = 'ava@example.com',
            Lead__c = lead.Id
        );
        insert drive;

        Test.startTest();
        CustomerInsightController.CustomerProfile profile =
            CustomerInsightController.getCustomerProfile('ava@example.com');
        Test.stopTest();

        System.assertEquals(true, profile.isKnown);
        System.assertEquals(true, profile.hasBooking);
        System.assertEquals('Electra Storm', profile.recommendedVehicle);
        System.assertEquals('Based on your saved preferred model.', profile.recommendationReason);
        System.assertEquals('ACTIVE_BOOKING', profile.segmentCode);
        System.assertEquals('WhatsApp', profile.preferredChannel);
        System.assertEquals('560001', profile.preferredZipCode);
    }

    @IsTest
    static void returnsDefaultProfileForUnknownVisitor() {
        Test.startTest();
        CustomerInsightController.CustomerProfile profile =
            CustomerInsightController.getCustomerProfile('newvisitor@example.com');
        Test.stopTest();

        System.assertEquals(false, profile.isKnown);
        System.assertEquals('NEW_VISITOR', profile.segmentCode);
        System.assertEquals('Electra Breeze', profile.recommendedVehicle);
        System.assertEquals('WhatsApp', profile.preferredChannel);
    }
}
