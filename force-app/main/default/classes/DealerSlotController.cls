public with sharing class DealerSlotController {

    // ─── Inner classes defined first ───────────────────────────────────────────

    @JsonAccess(serializable='always' deserializable='always')
    public class DealerSelectionOutput {
        @InvocableVariable public String  dealerAccountId;
        @InvocableVariable public String  dealerName;
        @InvocableVariable public String  dealerAddress;
        @InvocableVariable public String  dealerPhone;
        @InvocableVariable public String  serviceTerritoryId;
        @InvocableVariable public String  serviceResourceId;
        @InvocableVariable public String  serviceResourceName;
        @InvocableVariable public String  selectedSlotLabel;
        @InvocableVariable public Integer selectedSlotStartHour;
        @InvocableVariable public Integer selectedSlotEndHour;
    }

    @JsonAccess(serializable='always' deserializable='always')
    public class DealerSlotRequest {
        @InvocableVariable(required=true)
        public String selectedModel;
        @InvocableVariable(required=true)
        public String selectedDate;
        @InvocableVariable
        public String userCity;
        @InvocableVariable
        public String userZip;
        @InvocableVariable
        public String userLatitude;
        @InvocableVariable
        public String userLongitude;
        @InvocableVariable
        public String messagingSessionId;
    }

    @JsonAccess(serializable='always' deserializable='always')
    public class DealerSlotResponse {
        @InvocableVariable
        public List<DealerInfo> dealers;
        @InvocableVariable
        public List<TimeSlotInfo> timeSlots;
        @InvocableVariable
        public String selectedDate;
        @InvocableVariable
        public Boolean isHoliday;
        @InvocableVariable
        public String errorMessage;
    }

    @JsonAccess(serializable='always' deserializable='always')
    public class DealerInfo implements Comparable {
        @InvocableVariable public String  dealerAccountId;
        @InvocableVariable public String  dealerName;
        @InvocableVariable public String  dealerAddress;
        @InvocableVariable public String  dealerPhone;
        @InvocableVariable public String  dealerCity;
        @InvocableVariable public String  dealerZip;
        @InvocableVariable public String  serviceTerritoryId;
        @InvocableVariable public String  assetId;
        @InvocableVariable public String  assetName;
        @InvocableVariable public String  serviceResourceId;
        @InvocableVariable public String  serviceResourceName;
        @InvocableVariable public Decimal distanceKm;
        @InvocableVariable public Integer availableSlotCount;

        public Integer compareTo(Object other) {
            DealerInfo o = (DealerInfo) other;
            if (distanceKm < o.distanceKm) return -1;
            if (distanceKm > o.distanceKm) return 1;
            return 0;
        }
    }

    @JsonAccess(serializable='always' deserializable='always')
    public class TimeSlotInfo {
        @InvocableVariable public String  label;
        @InvocableVariable public Integer startHour;
        @InvocableVariable public Integer endHour;
        @InvocableVariable public Boolean isAvailable;
        @InvocableVariable public Integer availableCount;
    }

    private class DealerWithAsset implements Comparable {
        public String  assetId;
        public String  assetName;
        public String  accountId;
        public String  accountName;
        public String  address;
        public String  phone;
        public String  city;
        public String  zip;
        public String  serviceTerritoryId;
        public Decimal distanceKm;

        public Integer compareTo(Object other) {
            DealerWithAsset o = (DealerWithAsset) other;
            if (distanceKm < o.distanceKm) return -1;
            if (distanceKm > o.distanceKm) return 1;
            return 0;
        }
    }

    private class SlotHour {
        Integer startH;
        Integer endH;
        SlotHour(Integer s, Integer e) { startH = s; endH = e; }
    }

    // ─── Invocable Method ──────────────────────────────────────────────────────
    @InvocableMethod(
        label='Get Dealers and Time Slots'
        description='Returns dealers near user location that have the selected model available, with available time slots for the given date.'
    )
    public static List<DealerSlotResponse> getDealersAndSlots(List<DealerSlotRequest> requests) {
        List<DealerSlotResponse> responses = new List<DealerSlotResponse>();

        for (DealerSlotRequest req : requests) {
            DealerSlotResponse res = new DealerSlotResponse();
            res.isHoliday    = false;
            res.errorMessage = '';

            // 1. Validate date
            Date requestedDate;
            try {
                requestedDate = Date.valueOf(req.selectedDate);
            } catch (Exception e) {
                res.errorMessage = 'Invalid date format. Please use YYYY-MM-DD.';
                responses.add(res);
                continue;
            }

            if (requestedDate < Date.today()) {
                res.errorMessage = 'Please select a future date.';
                responses.add(res);
                continue;
            }

            // 2. Check Sunday
            String dayOfWeek = getDayOfWeek(requestedDate);
            if (dayOfWeek == 'Sunday') {
                res.errorMessage = 'We are closed on Sundays. Please select another date.';
                res.isHoliday = true;
                responses.add(res);
                continue;
            }

            // 3. Find dealers with model asset
            Decimal userLat = String.isNotBlank(req.userLatitude)  ? Decimal.valueOf(req.userLatitude)  : null;
            Decimal userLng = String.isNotBlank(req.userLongitude) ? Decimal.valueOf(req.userLongitude) : null;

            List<DealerWithAsset> dealersWithAssets = getDealersWithModelAndAsset(
                req.selectedModel, req.userCity, req.userZip, userLat, userLng
            );

            if (dealersWithAssets.isEmpty()) {
                res.errorMessage = 'No dealers found near ' + req.userCity + ' with ' + req.selectedModel + ' available.';
                responses.add(res);
                continue;
            }

            // 4. Check holidays
            Set<Id> holidayTerritoryIds = getHolidayTerritories(requestedDate);

            // 5. Get booked slots
            Set<Id> allTerritoryIds = new Set<Id>();
            for (DealerWithAsset dwa : dealersWithAssets) {
                if (dwa.serviceTerritoryId != null) allTerritoryIds.add(dwa.serviceTerritoryId);
            }
            Map<Id, Set<Integer>> bookedSlotsByTerritory = getBookedSlots(allTerritoryIds, requestedDate);

            // 6. Build dealer list
            List<DealerInfo> dealerInfos = new List<DealerInfo>();
            for (DealerWithAsset dwa : dealersWithAssets) {
                if (dwa.serviceTerritoryId == null) continue;
                if (holidayTerritoryIds.contains(dwa.serviceTerritoryId)) continue;

                ServiceResource driver = getDriverForTerritory(dwa.serviceTerritoryId);

                DealerInfo di = new DealerInfo();
                di.dealerAccountId     = dwa.accountId;
                di.dealerName          = dwa.accountName;
                di.dealerAddress       = dwa.address;
                di.dealerPhone         = dwa.phone;
                di.dealerCity          = dwa.city;
                di.dealerZip           = dwa.zip;
                di.serviceTerritoryId  = dwa.serviceTerritoryId;
                di.assetId             = dwa.assetId;
                di.assetName           = dwa.assetName;
                di.distanceKm          = dwa.distanceKm;
                di.serviceResourceId   = driver != null ? driver.Id   : null;
                di.serviceResourceName = driver != null ? driver.Name : 'TBD';

                Set<Integer> bookedHours = bookedSlotsByTerritory.containsKey(dwa.serviceTerritoryId)
                    ? bookedSlotsByTerritory.get(dwa.serviceTerritoryId)
                    : new Set<Integer>();

                di.availableSlotCount = 0;
                for (SlotHour sh : getSlotHours()) {
                    if (!bookedHours.contains(sh.startH)) di.availableSlotCount++;
                }

                dealerInfos.add(di);
            }

            if (dealerInfos.isEmpty()) {
                res.errorMessage = 'All dealers are on holiday or unavailable on ' + req.selectedDate + '.';
                responses.add(res);
                continue;
            }

            // 7. Build time slots
            List<TimeSlotInfo> slots = buildTimeSlots(dealerInfos, bookedSlotsByTerritory);

            res.dealers      = dealerInfos;
            res.timeSlots    = slots;
            res.selectedDate = req.selectedDate;

            responses.add(res);
        }

        return responses;
    }

    // ─── AuraEnabled for LWC ───────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static DealerSlotResponse getDealersAndSlotsForLWC(
        String selectedModel,
        String userCity,
        String userZip,
        String userLatitude,
        String userLongitude,
        String selectedDate
    ) {
        DealerSlotRequest req = new DealerSlotRequest();
        req.selectedModel  = selectedModel;
        req.userCity       = userCity;
        req.userZip        = userZip;
        req.userLatitude   = userLatitude;
        req.userLongitude  = userLongitude;
        req.selectedDate   = selectedDate;

        List<DealerSlotResponse> results = getDealersAndSlots(new List<DealerSlotRequest>{ req });
        return results.isEmpty() ? new DealerSlotResponse() : results[0];
    }

    // ─── AuraEnabled — save user selection to MessagingSession ────────────────
    @AuraEnabled
    public static void saveSelection(
        String messagingSessionId,
        String dealerAccountId,
        String dealerName,
        String serviceTerritoryId,
        String serviceResourceId,
        String serviceResourceName,
        String selectedSlotLabel,
        Integer selectedSlotStartHour,
        Integer selectedSlotEndHour
    ) {
        if (String.isBlank(messagingSessionId)) {
            throw new AuraHandledException('Messaging Session ID is required.');
        }

        MessagingSession session = [
            SELECT Id, SelectedDealer__c, SelectedDealerId__c, SelectedSlot__c,
                   ServiceTerritoryId__c, ServiceResourceId__c, ServiceResourceName__c,
                   SelectedSlotStartHour__c
            FROM MessagingSession
            WHERE Id = :messagingSessionId
            LIMIT 1
        ];

        session.SelectedDealer__c        = dealerName;
        session.SelectedDealerId__c      = dealerAccountId;
        session.SelectedSlot__c          = selectedSlotLabel;
        session.ServiceTerritoryId__c    = serviceTerritoryId;
        session.ServiceResourceId__c     = serviceResourceId;
        session.ServiceResourceName__c   = serviceResourceName;
        session.SelectedSlotStartHour__c = selectedSlotStartHour;

        update session;
    }

    // ─── Private helpers ───────────────────────────────────────────────────────

    private static List<DealerWithAsset> getDealersWithModelAndAsset(
        String model, String city, String zip, Decimal userLat, Decimal userLng
    ) {
        List<Asset> assets = [
            SELECT Id, Name, AccountId, Account.Name, Account.BillingStreet,
                   Account.BillingCity, Account.BillingPostalCode, Account.Phone
            FROM Asset
            WHERE Product2.Name = :model
            AND Account.RecordType.Name = 'Dealer'
            LIMIT 20
        ];

        if (assets.isEmpty()) return new List<DealerWithAsset>();

        Map<String, Id> territoryByName = new Map<String, Id>();
        for (ServiceTerritory st : [SELECT Id, Name FROM ServiceTerritory WHERE Name LIKE 'Electra Cars%']) {
            territoryByName.put(st.Name, st.Id);
        }

        List<DealerWithAsset> result = new List<DealerWithAsset>();
        for (Asset a : assets) {
            DealerWithAsset dwa = new DealerWithAsset();
            dwa.assetId     = a.Id;
            dwa.assetName   = a.Name;
            dwa.accountId   = a.AccountId;
            dwa.accountName = a.Account.Name;
            dwa.address     = (a.Account.BillingStreet != null ? a.Account.BillingStreet + ', ' : '')
                            + a.Account.BillingCity + ' ' + a.Account.BillingPostalCode;
            dwa.phone       = a.Account.Phone;
            dwa.city        = a.Account.BillingCity;
            dwa.zip         = a.Account.BillingPostalCode;
            dwa.serviceTerritoryId = territoryByName.containsKey(a.Account.Name)
                ? territoryByName.get(a.Account.Name) : null;
            dwa.distanceKm  = estimateDistance(city, a.Account.BillingCity, zip, a.Account.BillingPostalCode);
            result.add(dwa);
        }

        result.sort();
        return result;
    }

    private static Map<Id, Set<Integer>> getBookedSlots(Set<Id> territoryIds, Date d) {
        Map<Id, Set<Integer>> result = new Map<Id, Set<Integer>>();
        Datetime dayStart = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        Datetime dayEnd   = Datetime.newInstance(d, Time.newInstance(23, 59, 59, 0));

        for (ServiceAppointment sa : [
            SELECT ServiceTerritoryId, SchedStartTime
            FROM ServiceAppointment
            WHERE ServiceTerritoryId IN :territoryIds
            AND SchedStartTime >= :dayStart
            AND SchedStartTime <= :dayEnd
            AND Status NOT IN ('Canceled', 'Cannot Complete')
        ]) {
            if (!result.containsKey(sa.ServiceTerritoryId)) {
                result.put(sa.ServiceTerritoryId, new Set<Integer>());
            }
            result.get(sa.ServiceTerritoryId).add(sa.SchedStartTime.hour());
        }
        return result;
    }

    private static List<TimeSlotInfo> buildTimeSlots(
        List<DealerInfo> dealers,
        Map<Id, Set<Integer>> bookedSlotsByTerritory
    ) {
        List<TimeSlotInfo> slots = new List<TimeSlotInfo>();

        for (SlotHour sh : getSlotHours()) {
            TimeSlotInfo ts = new TimeSlotInfo();
            ts.label     = sh.startH + ':00 – ' + sh.endH + ':00';
            ts.startHour = sh.startH;
            ts.endHour   = sh.endH;

            Integer availableCount = 0;
            for (DealerInfo di : dealers) {
                Set<Integer> booked = bookedSlotsByTerritory.containsKey(di.serviceTerritoryId)
                    ? bookedSlotsByTerritory.get(di.serviceTerritoryId)
                    : new Set<Integer>();
                if (!booked.contains(sh.startH)) availableCount++;
            }

            ts.isAvailable    = availableCount > 0;
            ts.availableCount = availableCount;
            slots.add(ts);
        }
        return slots;
    }

    private static ServiceResource getDriverForTerritory(Id territoryId) {
        List<ServiceTerritoryMember> members = [
            SELECT ServiceResourceId, ServiceResource.Name
            FROM ServiceTerritoryMember
            WHERE ServiceTerritoryId = :territoryId
            AND ServiceResource.ResourceType = 'T'
            AND ServiceResource.IsActive = true
            LIMIT 1
        ];

        if (!members.isEmpty()) {
            return new ServiceResource(
                Id   = members[0].ServiceResourceId,
                Name = members[0].ServiceResource.Name
            );
        }

        List<ServiceResource> fallback = [
            SELECT Id, Name FROM ServiceResource
            WHERE Name = 'Test Drive Accompany'
            AND IsActive = true
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0];
    }

    private static Set<Id> getHolidayTerritories(Date d) {
        Set<Id> holidayOHIds = new Set<Id>();
        for (OperatingHoursHoliday ohh : [
            SELECT OperatingHoursId FROM OperatingHoursHoliday
            WHERE Holiday.ActivityDate = :d
        ]) {
            holidayOHIds.add(ohh.OperatingHoursId);
        }

        Set<Id> territoryIds = new Set<Id>();
        for (ServiceTerritory st : [
            SELECT Id FROM ServiceTerritory WHERE OperatingHoursId IN :holidayOHIds
        ]) {
            territoryIds.add(st.Id);
        }
        return territoryIds;
    }

    private static Decimal estimateDistance(String userCity, String dealerCity, String userZip, String dealerZip) {
        if (userCity != null && userCity.equalsIgnoreCase(dealerCity)) return 2.5;
        if (userZip != null && dealerZip != null && userZip.length() >= 3 && dealerZip.length() >= 3
            && userZip.substring(0, 3) == dealerZip.substring(0, 3)) return 7.0;
        return 25.0;
    }

    private static String getDayOfWeek(Date d) {
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('EEEE');
    }

    private static List<SlotHour> getSlotHours() {
        List<SlotHour> slots = new List<SlotHour>();
        slots.add(new SlotHour(9,  10));
        slots.add(new SlotHour(10, 11));
        slots.add(new SlotHour(11, 12));
        slots.add(new SlotHour(12, 13));
        slots.add(new SlotHour(14, 15));
        slots.add(new SlotHour(15, 16));
        return slots;
    }
}