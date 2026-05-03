/**
 * @description Builds a customer insight payload for personalized test-drive journeys.
 * Attempts to read Data Cloud unified profile data first and falls back to CRM data.
 */
public with sharing class CustomerInsightController {

    @AuraEnabled
    public static CustomerProfile getCustomerProfile(String email) {
        CustomerProfile profile = new CustomerProfile();
        profile.email = normalizeEmail(email);

        if (String.isBlank(profile.email)) {
            finalizeProfile(profile, new List<SObject>());
            return profile;
        }

        try {
            CustomerProfile dataCloudProfile = queryDataCloud(profile.email);
            if (dataCloudProfile != null) {
                return dataCloudProfile;
            }
        } catch (Exception e) {
            System.debug('Data Cloud query failed, falling back to CRM data: ' + e.getMessage());
        }

        try {
            return querySalesforceNative(profile.email);
        } catch (Exception e) {
            System.debug('CRM profile lookup failed, returning safe fallback profile: ' + e.getMessage());
            CustomerProfile safeProfile = new CustomerProfile();
            safeProfile.email = profile.email;
            safeProfile.profileSource = 'Salesforce CRM';
            finalizeProfile(safeProfile, new List<SObject>());
            return safeProfile;
        }
    }

    private static CustomerProfile queryDataCloud(String email) {
        CustomerProfile profile = new CustomerProfile();
        profile.email = email;
        profile.profileSource = 'Data Cloud';

        // Step 1: Find the ContactPointEmail record matching this email
        List<SObject> cpeRecords = new List<SObject>();
        try {
            cpeRecords = Database.query(
                'SELECT Id, ssot__EmailAddress__c ' +
                'FROM ssot__ContactPointEmail__dlm ' +
                'WHERE ssot__EmailAddress__c = :email ' +
                'LIMIT 1'
            );
        } catch (Exception e) {
            System.debug('ContactPointEmail query failed: ' + e.getMessage());
            return null;
        }

        if (cpeRecords.isEmpty()) {
            return null;
        }

        // Step 2: Get the ContactPointEmail record Id to find the linked Individual
        String cpeId = String.valueOf(cpeRecords[0].get('Id'));

        // Step 3: Query Individual — try different link field names
        List<SObject> unifiedProfiles = new List<SObject>();
        String individualId = null;

        // Try to find Individual via ssot__Id__c matching the CRM Contact Id
        // The ssot__Id__c on Individual maps to the CRM Contact/Lead Id
        try {
            // Find Contact by email first to get the CRM Id
            List<Contact> contacts = [
                SELECT Id FROM Contact WHERE Email = :email LIMIT 1
            ];
            if (!contacts.isEmpty()) {
                String crmId = contacts[0].Id;
                unifiedProfiles = Database.query(
                    'SELECT Id, ssot__Id__c, ssot__FirstName__c, ssot__LastName__c ' +
                    'FROM ssot__Individual__dlm ' +
                    'WHERE ssot__Id__c = :crmId ' +
                    'LIMIT 1'
                );
            }
        } catch (Exception e) {
            System.debug('Individual lookup via Contact failed: ' + e.getMessage());
        }

        // Fallback: try Lead Id
        if (unifiedProfiles.isEmpty()) {
            try {
                List<Lead> leads = [SELECT Id FROM Lead WHERE Email = :email LIMIT 1];
                if (!leads.isEmpty()) {
                    String leadId = leads[0].Id;
                    unifiedProfiles = Database.query(
                        'SELECT Id, ssot__Id__c, ssot__FirstName__c, ssot__LastName__c ' +
                        'FROM ssot__Individual__dlm ' +
                        'WHERE ssot__Id__c = :leadId ' +
                        'LIMIT 1'
                    );
                }
            } catch (Exception e) {
                System.debug('Individual lookup via Lead failed: ' + e.getMessage());
            }
        }

        if (unifiedProfiles.isEmpty()) {
            System.debug('No unified Individual found for email: ' + email);
            return null;
        }

        SObject unified = unifiedProfiles[0];
        profile.isKnown    = true;
        profile.firstName  = (String) unified.get('ssot__FirstName__c');
        profile.lastName   = (String) unified.get('ssot__LastName__c');
        profile.email      = email;
        individualId       = String.valueOf(unified.get('Id'));

        // Step 4: Query TestDrive DLM for booking history
        List<SObject> drives = new List<SObject>();
        try {
            drives = Database.query(
                'SELECT Id, Name__c, VehicleModel_c__c, Status_c__c, ' +
                'PreferredChannel_c__c, ZipCode_c__c, CustomerPhone_c__c, ' +
                'PreferredDate_c__c ' +
                'FROM TestDrive__dlm ' +
                'WHERE CustomerEmail_c__c = :email ' +
                'ORDER BY PreferredDate_c__c DESC NULLS LAST ' +
                'LIMIT 5'
            );
            System.debug('TestDrive DLM records found: ' + drives.size());
        } catch (Exception e) {
            System.debug('TestDrive DLM query attempt 1 failed: ' + e.getMessage());
            // Fallback without PreferredDate ordering
            try {
                drives = Database.query(
                    'SELECT Id, Name__c, VehicleModel_c__c, Status_c__c, ' +
                    'PreferredChannel_c__c, ZipCode_c__c, CustomerPhone_c__c ' +
                    'FROM TestDrive__dlm ' +
                    'WHERE CustomerEmail_c__c = :email ' +
                    'ORDER BY CreatedDate__c DESC NULLS LAST ' +
                    'LIMIT 5'
                );
            } catch (Exception e2) {
                System.debug('TestDrive DLM query attempt 2 failed: ' + e2.getMessage());
            }
        }

        // Extract profile data from latest booking
        if (!drives.isEmpty()) {
            SObject latest = drives[0];
            profile.phone            = (String) latest.get('CustomerPhone_c__c');
            profile.preferredZipCode = (String) latest.get('ZipCode_c__c');
            profile.preferredChannel = (String) latest.get('PreferredChannel_c__c');
            profile.lastVehicle      = (String) latest.get('VehicleModel_c__c');
            profile.lastBookingRef   = (String) latest.get('Name__c');
            profile.lastBookingStatus = (String) latest.get('Status_c__c');
            profile.hasBooking       = true;
            System.debug('Last vehicle from Data Cloud: ' + profile.lastVehicle);
        }

        // Always override with CRM's most recent booking — CRM is real-time, Data Cloud has lag
        List<TestDrive__c> crmDrives = new List<TestDrive__c>();
        try {
            crmDrives = [
                SELECT Id, Name, VehicleModel__c, Status__c, PreferredChannel__c, ZipCode__c
                FROM TestDrive__c
                WHERE CustomerEmail__c = :email
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];
            if (!crmDrives.isEmpty()) {
                profile.lastVehicle       = crmDrives[0].VehicleModel__c;
                profile.lastBookingRef    = crmDrives[0].Name;
                profile.lastBookingStatus = crmDrives[0].Status__c;
                profile.preferredChannel  = String.isNotBlank(crmDrives[0].PreferredChannel__c) 
                                            ? crmDrives[0].PreferredChannel__c 
                                            : profile.preferredChannel;
                profile.hasBooking        = true;
                System.debug('Last vehicle overridden from CRM: ' + profile.lastVehicle);
            }
        } catch (Exception e) {
            System.debug('CRM override query failed: ' + e.getMessage());
        }

        // Use CRM drives for finalizeProfile so totalBookings and segment signals are accurate.
        // DLM drives may be empty or stale due to sync lag.
        List<SObject> profileDrives = !crmDrives.isEmpty()
            ? convertToSObjects(crmDrives)
            : drives;

        finalizeProfile(profile, profileDrives);
        return profile;
    }

    private static CustomerProfile querySalesforceNative(String email) {
        CustomerProfile profile = new CustomerProfile();
        profile.email = email;
        profile.profileSource = 'Salesforce CRM';
        Contact contactRecord;

        try {
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Email, Phone,
                       MailingPostalCode, MailingCity,
                       Account.BillingCity, Account.BillingPostalCode,
                       PreferredVehicleModel__c
                FROM Contact
                WHERE Email = :email
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];

            if (!contacts.isEmpty()) {
                contactRecord = contacts[0];
                profile.isKnown   = true;
                profile.firstName = contactRecord.FirstName;
                profile.lastName  = contactRecord.LastName;
                profile.phone     = contactRecord.Phone;
                profile.savedPreferredVehicle = contactRecord.PreferredVehicleModel__c;

                // Person Accounts store address on Account.Billing*, not Contact.Mailing*
                // Fall back gracefully: prefer Mailing if populated, else use Account Billing
                profile.preferredZipCode = String.isNotBlank(contactRecord.MailingPostalCode)
                    ? contactRecord.MailingPostalCode
                    : (String) contactRecord.getSObject('Account')?.get('BillingPostalCode');
                profile.city = String.isNotBlank(contactRecord.MailingCity)
                    ? contactRecord.MailingCity
                    : (String) contactRecord.getSObject('Account')?.get('BillingCity');
            }
        } catch (Exception e) {
            System.debug('Contact lookup unavailable for this user context: ' + e.getMessage());
        }

        List<TestDrive__c> drives = new List<TestDrive__c>();
        try {
            drives = [
                SELECT Id, Name, VehicleModel__c, Status__c, PreferredDate__c, PreferredChannel__c,
                       ZipCode__c, CustomerPhone__c
                FROM TestDrive__c
                WHERE CustomerEmail__c = :email
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];
        } catch (Exception e) {
            System.debug('Test drive lookup unavailable for this user context: ' + e.getMessage());
        }

        if (!drives.isEmpty()) {
            TestDrive__c latestDrive = drives[0];
            profile.isKnown = true;
            profile.lastVehicle = latestDrive.VehicleModel__c;
            // Do NOT overwrite phone from TestDrive — it's booking-specific and may be stale.
            // Phone should only come from Contact or Lead records.
            profile.preferredZipCode = latestDrive.ZipCode__c;
            profile.preferredChannel = latestDrive.PreferredChannel__c;
        }

        if (drives.isEmpty()) {
            try {
                List<Lead> leads = [
                    SELECT Id, FirstName, LastName, Email, Phone, Status, PostalCode, City
                    FROM Lead
                    WHERE Email = :email
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];

                if (!leads.isEmpty()) {
                    Lead lead = leads[0];
                    profile.isKnown = true;
                    profile.firstName = lead.FirstName;
                    profile.lastName = lead.LastName;
                    profile.phone = lead.Phone;
                    profile.leadStatus = lead.Status;
                    profile.preferredZipCode = lead.PostalCode;
                    profile.city = lead.City;
                }
            } catch (Exception e) {
                System.debug('Lead lookup unavailable for this user context: ' + e.getMessage());
            }
        }

        finalizeProfile(profile, convertToSObjects(drives));
        return profile;
    }

    private static void finalizeProfile(CustomerProfile profile, List<SObject> drives) {
        profile.totalBookings = drives.size();

        if (!drives.isEmpty()) {
            SObject latestDrive = drives[0];
            profile.hasBooking = true;
            profile.lastVehicle = getFieldValue(latestDrive, new List<String>{ 'VehicleModel__c', 'VehicleModel__c__c' });
            profile.lastBookingRef = getFieldValue(latestDrive, new List<String>{ 'Name', 'Name__c' });
            profile.lastBookingStatus = getFieldValue(latestDrive, new List<String>{ 'Status__c', 'Status__c__c' });
            profile.preferredChannel = firstNonBlank(
                getFieldValue(latestDrive, new List<String>{ 'PreferredChannel__c', 'PreferredChannel__c__c' }),
                profile.preferredChannel
            );
            profile.preferredZipCode = firstNonBlank(
                profile.preferredZipCode,
                getFieldValue(latestDrive, new List<String>{ 'ZipCode__c', 'ZipCode__c__c' })
            );
        }

        if (String.isBlank(profile.preferredChannel)) {
            profile.preferredChannel = 'WhatsApp';
        }

        applyJourneySignals(profile);
        applyVehicleRecommendation(profile);
        applyNudge(profile);
    }

    private static void applyJourneySignals(CustomerProfile profile) {
        if (!profile.isKnown) {
            profile.segmentCode = 'NEW_VISITOR';
            profile.segmentLabel = 'New visitor';
            profile.journeyStage = 'Discover';
            return;
        }

        Boolean hasActiveBooking = profile.hasBooking &&
            (profile.lastBookingStatus == 'Pending' || profile.lastBookingStatus == 'Confirmed');

        if (hasActiveBooking) {
            profile.segmentCode = 'ACTIVE_BOOKING';
            profile.segmentLabel = 'Booked customer';
            profile.journeyStage = 'Manage';
            return;
        }

        if (profile.totalBookings > 1) {
            profile.segmentCode = 'LOYAL_RETURNER';
            profile.segmentLabel = 'Repeat shopper';
            profile.journeyStage = 'Rebook';
            return;
        }

        if (String.isNotBlank(profile.leadStatus) &&
            (profile.leadStatus.contains('Working') || profile.leadStatus.contains('Qualified') || profile.leadStatus.contains('Open'))) {
            profile.segmentCode = 'HIGH_INTENT';
            profile.segmentLabel = 'High-intent prospect';
            profile.journeyStage = 'Convert';
            return;
        }

        profile.segmentCode = 'KNOWN_CUSTOMER';
        profile.segmentLabel = 'Returning visitor';
        profile.journeyStage = 'Consider';
    }

    private static void applyVehicleRecommendation(CustomerProfile profile) {
        // 1. Explicit saved preference on Contact — highest priority
        if (String.isNotBlank(profile.savedPreferredVehicle)) {
            profile.recommendedVehicle = profile.savedPreferredVehicle;
            profile.recommendationReason = 'Based on your saved preferred model.';
            return;
        }

        // 2. Most recently booked vehicle — always prefer real booking history
        //    over segment-based guesses, regardless of segment
        if (String.isNotBlank(profile.lastVehicle)) {
            profile.recommendedVehicle = profile.lastVehicle;
            profile.recommendationReason = profile.segmentCode == 'ACTIVE_BOOKING'
                ? 'Resume the journey for your already-booked model.'
                : 'Based on your most recent Electra interest.';
            return;
        }

        // 3. No booking history at all — use segment-based defaults only for new/unknown visitors
        if (profile.segmentCode == 'HIGH_INTENT') {
            profile.recommendedVehicle = 'Electra Volt';
            profile.recommendationReason = 'A balanced choice for first-time EV shoppers who are close to booking.';
            return;
        }

        // Default starter recommendation for truly new visitors
        profile.recommendedVehicle = 'Electra Breeze';
        profile.recommendationReason = 'A simple starting point for a fast first test drive.';
    }

    private static void applyNudge(CustomerProfile profile) {
        if (!profile.isKnown) {
            profile.nudgeMessage = 'Book your Electra test drive in under a minute.';
            profile.nudgeType = 'NEW_VISITOR';
            return;
        }

        if (profile.segmentCode == 'ACTIVE_BOOKING') {
            profile.nudgeMessage = 'Your ' + profile.lastVehicle + ' booking is already in flight. Need to reschedule or confirm details?';
            profile.nudgeType = 'EXISTING_BOOKING';
            return;
        }

        if (profile.segmentCode == 'LOYAL_RETURNER') {
            profile.nudgeMessage = 'Welcome back' + buildFirstNameSuffix(profile.firstName) + '. Ready for another Electra drive?';
            profile.nudgeType = 'REPEAT_CUSTOMER';
            return;
        }

        if (profile.segmentCode == 'HIGH_INTENT') {
            profile.nudgeMessage = 'Welcome back' + buildFirstNameSuffix(profile.firstName) + '. We can prefill your next test drive and recommend the best-fit model.';
            profile.nudgeType = 'HIGH_INTENT';
            return;
        }

        profile.nudgeMessage = 'Welcome back' + buildFirstNameSuffix(profile.firstName) + '. We saved your preferences so you can book faster.';
        profile.nudgeType = 'RETURNING_VISITOR';
    }

    private static String buildFirstNameSuffix(String firstName) {
        return String.isBlank(firstName) ? '' : ', ' + firstName;
    }

    private static List<SObject> convertToSObjects(List<TestDrive__c> drives) {
        List<SObject> records = new List<SObject>();
        for (TestDrive__c drive : drives) {
            records.add(drive);
        }
        return records;
    }

    private static String normalizeEmail(String email) {
        return String.isBlank(email) ? null : email.trim().toLowerCase();
    }

    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : secondValue;
    }

    private static String getFieldValue(SObject record, List<String> candidateFields) {
        if (record == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : candidateFields) {
            if (fieldMap.containsKey(fieldName)) {
                Object value = record.get(fieldName);
                if (value != null) {
                    String stringValue = String.valueOf(value);
                    if (String.isNotBlank(stringValue)) {
                        return stringValue;
                    }
                }
            }
        }
        return null;
    }

    public class CustomerProfile {
        @AuraEnabled public Boolean isKnown = false;
        @AuraEnabled public Boolean hasBooking = false;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public String lastVehicle;
        @AuraEnabled public String savedPreferredVehicle;
        @AuraEnabled public String lastBookingRef;
        @AuraEnabled public String lastBookingStatus;
        @AuraEnabled public String preferredChannel;
        @AuraEnabled public String preferredZipCode;
        @AuraEnabled public String recommendedVehicle;
        @AuraEnabled public String recommendationReason;
        @AuraEnabled public String segmentCode;
        @AuraEnabled public String segmentLabel;
        @AuraEnabled public String journeyStage;
        @AuraEnabled public String profileSource = 'Salesforce CRM';
        @AuraEnabled public Integer totalBookings = 0;
        @AuraEnabled public String nudgeMessage = 'Book your Electra test drive in under a minute.';
        @AuraEnabled public String nudgeType = 'NEW_VISITOR';
    }
}