/**
 * BookTestDriveAction
 * ─────────────────────────────────────────────────────────────────────────────
 * Minimal inputs — everything is derived from dealerName internally.
 *
 * Does:
 *   1. Creates ServiceAppointment (Test Drive record type)
 *   2. Assigns ServiceResource (driver)
 *   3. Creates/upserts Opportunity
 *   4. Triggers Send_Confirmation_SMS_Mail Flow (handles SMS + Email)
 */
public without sharing class BookTestDriveAction {

    @InvocableMethod(
        label='Book Test Drive Appointment'
        description='Creates a ServiceAppointment and Opportunity for the test drive using the dealer name and time slot.'
    )
    public static List<BookingResponse> bookAppointment(List<BookingRequest> requests) {
        List<BookingResponse> responses = new List<BookingResponse>();
        for (BookingRequest req : requests) {
            responses.add(processBooking(req));
        }
        return responses;
    }

    private static BookingResponse processBooking(BookingRequest req) {
        BookingResponse res = new BookingResponse();

        try {
            Date bookingDate = Date.valueOf(req.selectedDate);
            if (bookingDate < Date.today()) {
                res.success = false;
                res.errorMessage = 'Cannot book a test drive for a past date.';
                return res;
            }

            Integer startHour = parseStartHour(req.slotLabel);
            Datetime startDT = Datetime.newInstance(bookingDate, Time.newInstance(startHour, 0, 0, 0));
            Datetime endDT = Datetime.newInstance(bookingDate, Time.newInstance(startHour + 1, 0, 0, 0));

            // ── 1. Look up dealer Account ─────────────────────────────────────
            List<Account> dealers = [
                SELECT Id, Name, Phone, DealerEmail__c, OwnerId,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode,
                       BillingLatitude, BillingLongitude
                FROM Account
                WHERE Id = :req.showroomId
                LIMIT 1
            ];

            if (dealers.isEmpty()) {
                res.success = false;
                res.errorMessage = 'Showroom not found.';
                return res;
            }
            Account dealer = dealers[0];
            String dealerAddress = buildAddress(dealer.BillingStreet, dealer.BillingCity,
                                                dealer.BillingState, dealer.BillingPostalCode);

            // ── 2. Look up ServiceTerritory ────────────────────
            List<ServiceTerritory> territories = [
                SELECT Id FROM ServiceTerritory
                WHERE Name = :dealer.Name AND IsActive = true
                LIMIT 1
            ];
            Id serviceTerritoryId = territories.isEmpty() ? null : territories[0].Id;

            // ── 3. Look up ServiceResource (driver) ───────────────────────────
            Id serviceResourceId = null;
            String serviceResourceName = 'TBD';
            String driverPhone = null;
            String driverEmail = null;

            if (serviceTerritoryId != null) {
                List<ServiceTerritoryMember> members = [
                    SELECT ServiceResourceId, ServiceResource.Name,
                           ServiceResource.RelatedRecord.MobilePhone,
                           ServiceResource.RelatedRecord.Email
                    FROM ServiceTerritoryMember
                    WHERE ServiceTerritoryId = :serviceTerritoryId
                    AND ServiceResource.ResourceType = 'T'
                    AND ServiceResource.IsActive = true
                    LIMIT 1
                ];
                if (!members.isEmpty()) {
                    serviceResourceId = members[0].ServiceResourceId;
                    serviceResourceName = members[0].ServiceResource.Name;
                    driverPhone = members[0].ServiceResource.RelatedRecord?.MobilePhone;
                    driverEmail = members[0].ServiceResource.RelatedRecord?.Email;
                }
            }

            // ── 4. Resolve Record Type + WorkType ──────────────────
            Id saRecordTypeId = getRecordTypeId('ServiceAppointment', 'Test_Drive_Appointment');
            List<WorkType> workTypes = [SELECT Id FROM WorkType WHERE Name = 'Test Drive' LIMIT 1];
            Id workTypeId = workTypes.isEmpty() ? null : workTypes[0].Id;

            // ── 5. Lead Handling ────────────────────────────────────────────────
            List<Lead> existingLeads = [
                SELECT Id FROM Lead
                WHERE Email = :req.emailId AND IsConverted = false
                LIMIT 1
            ];

            Lead lead;
            if (!existingLeads.isEmpty()) {
                lead = existingLeads[0];
            } else {
                lead = new Lead(
                    FirstName = req.firstName,
                    LastName = String.isNotBlank(req.lastName) ? req.lastName : req.firstName,
                    Email = req.emailId,
                    Phone = req.mobile,
                    Company = dealer.Name,
                    OwnerId = dealer.OwnerId,
                    LeadSource = 'Agentforce Chat',
                    Status = 'Open - Not Contacted'
                );
                insert lead;
            }

            // ── 6. Create ServiceAppointment ─────────────────
            ServiceAppointment sa = new ServiceAppointment(
                Subject = 'Test Drive — ' + req.vehicleModel + ' — ' + req.firstName + ' ' + req.lastName,
                Description = buildDescription(req, dealer, dealerAddress, serviceResourceName),
                SchedStartTime = startDT,
                SchedEndTime = endDT,
                Status = 'Scheduled',
                Phone = req.mobile,
                Email = req.emailId,
                ServiceTerritoryId = serviceTerritoryId,
                ParentRecordId = lead.Id,
                WorkTypeId = workTypeId
            );
            if (saRecordTypeId != null) sa.RecordTypeId = saRecordTypeId;
            insert sa;

            // ── 7. Assign Resource ────────────────────────────
            if (serviceResourceId != null) {
                insert new AssignedResource(
                    ServiceAppointmentId = sa.Id,
                    ServiceResourceId = serviceResourceId,
                    IsRequiredResource = true
                );
            }

            // Assign the demo car asset as a resource if provided
            if (String.isNotBlank(req.assetResourceId)) {
                try {
                    insert new AssignedResource(
                        ServiceAppointmentId = sa.Id,
                        ServiceResourceId    = req.assetResourceId,
                        IsRequiredResource   = false
                    );
                } catch (Exception assetEx) {
                    System.debug('Asset resource assignment (non-fatal): ' + assetEx.getMessage());
                }
            }

            // ── 8. Opportunity ────────────────────────────────
            Opportunity opp = upsertOpportunity(req, dealer.Id, sa.Id, bookingDate);

            // ── 9. Notification Flow ───────────────────
            try {
                String mapsLink = 'https://www.google.com/maps/search/?api=1&query=' + EncodingUtil.urlEncode(dealer.Name + ' ' + dealerAddress, 'UTF-8');
                String calStartStr = startDT.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
                String calEndStr = endDT.formatGmt('yyyyMMdd\'T\'HHmmss\'Z\'');
                String calLink = 'https://www.google.com/calendar/render?action=TEMPLATE&text=' + EncodingUtil.urlEncode('Test Drive: ' + req.vehicleModel, 'UTF-8') + '&dates=' + calStartStr + '/' + calEndStr + '&location=' + EncodingUtil.urlEncode(dealerAddress, 'UTF-8');

                Map<String, Object> flowInputs = new Map<String, Object>{
                    'customerName' => req.firstName + ' ' + (String.isNotBlank(req.lastName) ? req.lastName : ''),
                    'emailAddress' => req.emailId,
                    'CustomerPhone' => req.mobile,
                    'vehicleModel' => req.vehicleModel,
                    'appointmentDate' => bookingDate,
                    'appointmentTime' => req.slotLabel,
                    'DealerName' => dealer.Name,
                    'DealerAddress' => dealerAddress,
                    'DealerContactPhone' => dealer.Phone,
                    'DealerContactEmail' => dealer.DealerEmail__c,
                    'TestDriveAccompanyName' => serviceResourceName,
                    'TestDriveAccompanyPhone' => driverPhone != null ? driverPhone : '',
                    'TestDriveAccompanyEmail' => driverEmail != null ? driverEmail : '',
                    'GoogleMapsLink' => mapsLink,
                    'GoogleCalendarLink' => calLink
                };
                Flow.Interview.Send_Confirmation_SMS_Mail confirmFlow = new Flow.Interview.Send_Confirmation_SMS_Mail(flowInputs);
                confirmFlow.start();
            } catch (Exception e) {}

            res.success = true;
            res.serviceAppointmentId = sa.Id;
            res.leadId = lead.Id;
            res.opportunityId = opp?.Id;
            res.dealerPhone = dealer.Phone;
            res.dealerEmail = dealer.DealerEmail__c;
            res.serviceResourceName = serviceResourceName;
            res.driverPhone = driverPhone;
            res.driverEmail = driverEmail;
            res.confirmationMessage = buildConfirmationMessage(req, sa, dealer.Name, dealerAddress, serviceResourceName);

        } catch (Exception e) {
            res.success = false;
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    private static Opportunity upsertOpportunity(BookingRequest req, Id dealerAccountId, Id saId, Date bookingDate) {
        List<Opportunity> existing = [
            SELECT Id FROM Opportunity
            WHERE CustomerEmail__c = :req.emailId AND Name LIKE :('%' + req.vehicleModel + '%') AND IsClosed = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];

        Opportunity opp = new Opportunity(
            Name = req.firstName + ' ' + req.lastName + ' — ' + req.vehicleModel + ' Test Drive',
            StageName = 'Test Drive Scheduled',
            CloseDate = bookingDate.addDays(30),
            AccountId = dealerAccountId,
            CustomerEmail__c = req.emailId
        );
        insert opp;
        return opp;
    }

    private static String buildDescription(BookingRequest req, Account dealer, String address, String driverName) {
        return 'Customer: ' + req.firstName + ' ' + req.lastName + '\nMobile: ' + req.mobile + '\nVehicle: ' + req.vehicleModel;
    }

    private static String buildConfirmationMessage(BookingRequest req, ServiceAppointment sa, String dealerName, String dealerAddress, String driverName) {
        return '✅ Confirmed!\nVehicle: ' + req.vehicleModel + '\nShowroom: ' + dealerName;
    }

    private static Integer parseStartHour(String slotLabel) {
        try { return Integer.valueOf(slotLabel.trim().substring(0, 2)); } catch (Exception e) { return 10; }
    }

    private static Id getRecordTypeId(String sObjectName, String devName) {
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = :sObjectName AND DeveloperName = :devName LIMIT 1];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static String buildAddress(String street, String city, String state, String zip) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) parts.add(street);
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(zip)) parts.add(zip);
        return String.join(parts, ', ');
    }

    public class BookingRequest {
        @InvocableVariable(label='First Name' required=true) public String firstName;
        @InvocableVariable(label='Last Name') public String lastName;
        @InvocableVariable(label='Mobile') public String mobile;
        @InvocableVariable(label='Email') public String emailId;
        @InvocableVariable(label='Vehicle Model' required=true) public String vehicleModel;
        @InvocableVariable(label='Selected Date' required=true) public String selectedDate;
        @InvocableVariable(label='Dealer Name') public String dealerName;
        @InvocableVariable(label='Showroom Id' required=true) public String showroomId;
        @InvocableVariable(label='Asset Resource Id') public String assetResourceId;
        @InvocableVariable(label='Slot Label' required=true) public String slotLabel;
    }

    public class BookingResponse {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String serviceAppointmentId;
        @InvocableVariable public String leadId;
        @InvocableVariable public String opportunityId;
        @InvocableVariable public String dealerPhone;
        @InvocableVariable public String dealerEmail;
        @InvocableVariable public String serviceResourceName;
        @InvocableVariable public String driverPhone;
        @InvocableVariable public String driverEmail;
        @InvocableVariable public String confirmationMessage;
        @InvocableVariable public String errorMessage;
    }
}