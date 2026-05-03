/**
 * @description Controller for Test Drive Booking - used by LWC and Agentforce Agent Actions
 */
public without sharing class TestDriveBookingController {

    @InvocableMethod(label='Create Test Drive Booking' description='Creates a test drive record and routes to nearest dealership')
    public static List<BookingResult> createTestDriveBooking(List<BookingRequest> requests) {
        List<BookingResult> results = new List<BookingResult>();
        for (BookingRequest req : requests) {
            results.add(processBooking(req));
        }
        return results;
    }

    @AuraEnabled
    public static BookingResult bookTestDrive(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Booking payload is required.');
        }

        BookingPayload payload;
        try {
            payload = (BookingPayload) JSON.deserialize(payloadJson, BookingPayload.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Booking payload is invalid.');
        }

        BookingRequest req = new BookingRequest();
        req.firstName        = payload.firstName;
        req.lastName         = payload.lastName;
        req.email            = payload.email;
        req.phone            = payload.phone;
        req.vehicleModel     = payload.vehicleModel;
        req.preferredDate    = parsePreferredDate(payload.preferredDate);
        req.preferredTime    = payload.preferredTime;
        req.zipCode          = payload.zipCode;
        req.preferredChannel = payload.preferredChannel;
        return processBooking(req);
    }

    /**
     * @description Returns hardcoded vehicle options (replace with custom object query if available)
     */
    @AuraEnabled(cacheable=true)
    public static List<VehicleOption> getVehicleModels() {
        return new List<VehicleOption>{
            new VehicleOption('1', 'Electra Apex',   '2025', 45000, ''),
            new VehicleOption('2', 'Electra Volt',   '2025', 38000, ''),
            new VehicleOption('3', 'Electra Storm',  '2025', 62000, ''),
            new VehicleOption('4', 'Electra Breeze', '2025', 32000, '')
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<DealershipInfo> getDealershipsByZip(String zipCode) {
        return DealershipRoutingService.findNearestDealerships(zipCode, 3);
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    private static BookingResult processBooking(BookingRequest req) {
        BookingResult result = new BookingResult();
        try {
            Lead lead = upsertLead(req);
            updateContactPreference(req);
            updatePersonAccountPreference(req.email, req.vehicleModel);
            Account dealership = DealershipRoutingService.routeByZip(req.zipCode);

            TestDrive__c td = new TestDrive__c(
                VehicleModel__c     = req.vehicleModel,
                PreferredDate__c    = req.preferredDate,
                PreferredTime__c    = req.preferredTime,
                ZipCode__c          = req.zipCode,
                CustomerEmail__c    = req.email,
                CustomerPhone__c    = req.phone,
                PreferredChannel__c = req.preferredChannel,
                Status__c           = 'Pending',
                BookingSource__c    = 'Web Form',
                Lead__c             = lead.Id,
                AssignedDealership__c = dealership?.Id,
                Available_Slots__c  = DateTime.newInstance(req.preferredDate, Time.newInstance(9, 0, 0, 0))
            );
            insert td;
            
            // Re-query to get auto-number Name + all fields needed for notification
            List<TestDrive__c> requeried = [
                SELECT Id, Name, VehicleModel__c, PreferredDate__c, PreferredTime__c,
                       CustomerEmail__c, CustomerPhone__c, PreferredChannel__c,
                       Status__c, ZipCode__c, AssignedDealership__c
                FROM TestDrive__c WHERE Id = :td.Id LIMIT 1
            ];
            if (!requeried.isEmpty()) {
                td = requeried[0];
            }

            result.success            = true;
            result.testDriveId        = td.Id;
            result.testDriveName      = td.Name;
            result.dealershipName     = dealership?.Name;
            result.dealershipAddress  = buildDealershipAddress(dealership);
            result.dealershipMapsUrl  = buildMapsUrl(dealership);
            result.confirmationMessage = buildConfirmationMessage(td, lead, dealership);

            // Pass phone explicitly — never rely on Lead.Phone which may be stale
            sendNotificationAsync(td.Id, lead.Id, dealership?.Id, req.phone);

        } catch (Exception e) {
            result.success      = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    private static Lead upsertLead(BookingRequest req) {
        List<Lead> existing = [SELECT Id FROM Lead WHERE Email = :req.email LIMIT 1];
        Lead lead = existing.isEmpty() ? new Lead() : existing[0];
        lead.FirstName  = req.firstName;
        lead.LastName   = req.lastName;
        lead.Email      = req.email;
        lead.Phone      = req.phone;
        lead.PostalCode = req.zipCode;
        lead.Company    = 'Electra Cars Prospect';
        lead.LeadSource = 'Web';
        lead.Status     = 'Open - Not Contacted';
        upsert lead;
        return lead;
    }

    private static void updateContactPreference(BookingRequest req) {
        if (String.isBlank(req.email) || String.isBlank(req.vehicleModel)) {
            return;
        }

        try {
            // First, try to find the Contact linked to the currently logged-in Experience Site user.
            // This ensures the field is updated on the right record even if the email lookup
            // returns a different Contact (e.g. duplicate records).
            Contact customerContact = null;

            try {
                User currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
                if (currentUser.ContactId != null) {
                    List<Contact> loggedInContacts = [
                        SELECT Id, PreferredVehicleModel__c, Phone, MailingPostalCode, AccountId
                        FROM Contact
                        WHERE Id = :currentUser.ContactId
                        LIMIT 1
                    ];
                    if (!loggedInContacts.isEmpty()) {
                        customerContact = loggedInContacts[0];
                    }
                }
            } catch (Exception ex) {
                System.debug('Logged-in user Contact lookup skipped: ' + ex.getMessage());
            }

            // Fall back to email-based lookup (covers guest/unauthenticated bookings and agent-invoked flows)
            // Also checks PersonEmail on Person Accounts (IsPersonAccount = true stores email on Account.PersonEmail)
            if (customerContact == null) {
                List<Contact> contacts = [
                    SELECT Id, PreferredVehicleModel__c, Phone, MailingPostalCode, AccountId
                    FROM Contact
                    WHERE Email = :req.email
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    customerContact = contacts[0];
                }
            }

            // Person Account fallback: if still no Contact found, look up via Account.PersonEmail
            // Person Accounts have a hidden Contact record — find it via the Account
            if (customerContact == null) {
                try {
                    List<Account> personAccounts = [
                        SELECT Id, PersonContactId
                        FROM Account
                        WHERE PersonEmail = :req.email
                        AND IsPersonAccount = true
                        LIMIT 1
                    ];
                    if (!personAccounts.isEmpty() && personAccounts[0].PersonContactId != null) {
                        List<Contact> personContacts = [
                            SELECT Id, PreferredVehicleModel__c, Phone, MailingPostalCode, AccountId
                            FROM Contact
                            WHERE Id = :personAccounts[0].PersonContactId
                            LIMIT 1
                        ];
                        if (!personContacts.isEmpty()) {
                            customerContact = personContacts[0];
                        }
                    }
                } catch (Exception ex) {
                    System.debug('Person Account lookup skipped: ' + ex.getMessage());
                }
            }

            // If no Contact exists yet (e.g. guest booking before registration),
            // create one so the preferred vehicle is persisted for future lookups.
            if (customerContact == null) {
                // Find or create the ElectraCars Customers account to link the new Contact
                Id accountId = null;
                try {
                    List<Account> accs = [
                        SELECT Id FROM Account
                        WHERE Name = 'ElectraCars Customers'
                        LIMIT 1
                    ];
                    if (!accs.isEmpty()) {
                        accountId = accs[0].Id;
                    }
                } catch (Exception ex) {
                    System.debug('Account lookup for new Contact skipped: ' + ex.getMessage());
                }

                String lastName = String.isNotBlank(req.lastName) ? req.lastName : 'Unknown';
                customerContact = new Contact(
                    FirstName             = req.firstName,
                    LastName              = lastName,
                    Email                 = req.email,
                    Phone                 = req.phone,
                    MailingPostalCode     = req.zipCode,
                    PreferredVehicleModel__c = req.vehicleModel,
                    AccountId             = accountId
                );
                insert customerContact;

                // Update Account preferred vehicle if linked
                if (accountId != null) {
                    try {
                        update new Account(Id = accountId, Preferred_Vehicle__c = req.vehicleModel);
                    } catch (Exception ex) {
                        System.debug('Account Preferred_Vehicle__c update skipped: ' + ex.getMessage());
                    }
                }
                return;
            }

            customerContact.PreferredVehicleModel__c = req.vehicleModel;

            if (String.isBlank(customerContact.Phone) && String.isNotBlank(req.phone)) {
                customerContact.Phone = req.phone;
            }

            if (String.isBlank(customerContact.MailingPostalCode) && String.isNotBlank(req.zipCode)) {
                customerContact.MailingPostalCode = req.zipCode;
            }

            update customerContact;

            // Also update Preferred_Vehicle__c on the linked Account so the chat agent
            // can read the customer's preferred vehicle directly from the Account record.
            if (customerContact.AccountId != null) {
                try {
                    Account linkedAccount = new Account(
                        Id = customerContact.AccountId,
                        Preferred_Vehicle__c = req.vehicleModel
                    );
                    update linkedAccount;
                } catch (Exception ex) {
                    System.debug('Account Preferred_Vehicle__c update skipped: ' + ex.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('Contact preference update skipped: ' + e.getMessage());
        }
    }

    /**
     * @description Directly updates Preferred_Vehicle__c on a Person Account matched by PersonEmail.
     * Handles Person Accounts where the email is stored on the Account itself.
     */
    private static void updatePersonAccountPreference(String email, String vehicleModel) {
        if (String.isBlank(email) || String.isBlank(vehicleModel)) {
            return;
        }
        try {
            List<Account> personAccounts = [
                SELECT Id FROM Account
                WHERE PersonEmail = :email
                AND IsPersonAccount = true
                LIMIT 1
            ];
            if (!personAccounts.isEmpty()) {
                update new Account(Id = personAccounts[0].Id, Preferred_Vehicle__c = vehicleModel);
            }
        } catch (Exception ex) {
            System.debug('Person Account direct update skipped: ' + ex.getMessage());
        }
    }

    private static String buildDealershipAddress(Account dealership) {
        if (dealership == null) return '';
        List<String> parts = new List<String>();
        if (String.isNotBlank(dealership.BillingStreet))  parts.add(dealership.BillingStreet);
        if (String.isNotBlank(dealership.BillingCity))    parts.add(dealership.BillingCity);
        if (String.isNotBlank(dealership.BillingState))   parts.add(dealership.BillingState);
        if (String.isNotBlank(dealership.BillingPostalCode)) parts.add(dealership.BillingPostalCode);
        return parts.isEmpty() ? dealership.Name : String.join(parts, ', ');
    }

    private static String buildMapsUrl(Account dealership) {
        if (dealership == null) return '';
        // Prefer coordinates if available
        if (dealership.BillingLatitude != null && dealership.BillingLongitude != null) {
            return 'https://maps.google.com/?q=' + dealership.BillingLatitude + ',' + dealership.BillingLongitude;
        }
        // Fall back to address search
        String address = buildDealershipAddress(dealership);
        if (String.isBlank(address)) {
            address = dealership.Name;
        }
        return 'https://maps.google.com/?q=' + EncodingUtil.urlEncode(address, 'UTF-8');
    }

    private static String buildConfirmationMessage(TestDrive__c td, Lead lead, Account dealership) {
        return 'Hi ' + lead.FirstName + ', your test drive for the ' + td.VehicleModel__c
            + ' is confirmed for ' + td.PreferredDate__c.format()
            + ' (' + td.PreferredTime__c + ')'
            + (dealership != null ? ' at ' + dealership.Name : '')
            + '. Booking ref: ' + td.Name;
    }

    private static Date parsePreferredDate(String preferredDate) {
        if (String.isBlank(preferredDate)) {
            throw new AuraHandledException('Preferred date is required.');
        }

        try {
            return Date.valueOf(preferredDate);
        } catch (Exception ex) {
            throw new AuraHandledException('Preferred date is invalid.');
        }
    }

    /**
     * @description Sends notification asynchronously after booking is committed.
     * NOTE: This runs in a @future context, so callouts are allowed directly.
     * Do NOT call @future methods from here — chain is: @future → direct callout only.
     */
    @future(callout=true)
    private static void sendNotificationAsync(Id testDriveId, Id leadId, Id dealershipId, String phoneOverride) {
        try {
            TestDrive__c td = [
                SELECT Id, Name, VehicleModel__c, PreferredDate__c, PreferredTime__c,
                       CustomerEmail__c, CustomerPhone__c, PreferredChannel__c,
                       Status__c, ZipCode__c, AssignedDealership__c
                FROM TestDrive__c WHERE Id = :testDriveId LIMIT 1
            ];
            
            Lead lead = [SELECT Id, FirstName, LastName, Email, Phone FROM Lead WHERE Id = :leadId LIMIT 1];
            
            // Use explicit phone override > TestDrive phone > Lead phone (in priority order)
            if (String.isNotBlank(phoneOverride)) {
                lead.Phone = phoneOverride;
            } else if (String.isNotBlank(td.CustomerPhone__c)) {
                lead.Phone = td.CustomerPhone__c;
            }

            Account dealership = null;
            if (dealershipId != null) {
                dealership = [
                    SELECT Id, Name, BillingStreet, BillingCity, BillingState, 
                           BillingPostalCode, BillingLatitude, BillingLongitude, Phone
                    FROM Account WHERE Id = :dealershipId LIMIT 1
                ];
            }
            
            TestDriveNotificationService.sendConfirmationDirect(td, lead, dealership);
        } catch (Exception e) {
            System.debug('Notification failed (non-critical): ' + e.getMessage());
        }
    }

    // ─── Inner classes ─────────────────────────────────────────────────────────

    public class BookingRequest {
        @InvocableVariable(label='First Name' required=true)    public String firstName;
        @InvocableVariable(label='Last Name' required=true)     public String lastName;
        @InvocableVariable(label='Email' required=true)         public String email;
        @InvocableVariable(label='Phone')                       public String phone;
        @InvocableVariable(label='Vehicle Model' required=true) public String vehicleModel;
        @InvocableVariable(label='Preferred Date' required=true) public Date preferredDate;
        @InvocableVariable(label='Preferred Time' required=true) public String preferredTime;
        @InvocableVariable(label='Zip Code' required=true)      public String zipCode;
        @InvocableVariable(label='Preferred Channel')           public String preferredChannel;
    }

    public class BookingPayload {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String vehicleModel;
        @AuraEnabled public String preferredDate;
        @AuraEnabled public String preferredTime;
        @AuraEnabled public String zipCode;
        @AuraEnabled public String preferredChannel;
    }

    public class BookingResult {
        @AuraEnabled @InvocableVariable public Boolean success;
        @AuraEnabled @InvocableVariable public String  testDriveId;
        @AuraEnabled @InvocableVariable public String  testDriveName;
        @AuraEnabled @InvocableVariable public String  dealershipName;
        @AuraEnabled @InvocableVariable public String  dealershipAddress;
        @AuraEnabled @InvocableVariable public String  dealershipMapsUrl;
        @AuraEnabled @InvocableVariable public String  confirmationMessage;
        @AuraEnabled @InvocableVariable public String  errorMessage;
    }

    public class VehicleOption {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  year;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String  imageUrl;

        public VehicleOption(String id, String name, String year, Decimal price, String imageUrl) {
            this.id       = id;
            this.name     = name;
            this.year     = year;
            this.price    = price;
            this.imageUrl = imageUrl;
        }
    }

    public class DealershipInfo {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  address;
        @AuraEnabled public String  city;
        @AuraEnabled public String  phone;
        @AuraEnabled public Decimal distance;
    }
}