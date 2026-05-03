/**
 * GetNearbyDealersAction
 * ─────────────────────────────────────────────────────────────────────────────
 * Invocable Apex Action for Agentforce.
 * Returns a formatted Markdown table of up to 5 nearby dealers + available
 * time slots for the requested model and date.
 *
 * Differences from FindAndFormatDealersAction:
 *  - Standalone (no dependency on DealerSlotController) — avoids CLT issues
 *  - Always returns at least 5 dealers (falls back to all dealers if fewer
 *    are near the user's location)
 *  - Graceful fallback when lat/lng are missing
 *  - Cleaner error messages surfaced to the agent
 */
public without sharing class GetNearbyDealersAction {

    // ─── Request / Response ───────────────────────────────────────────────────

    public class ActionRequest {
        @InvocableVariable(required=true  label='Vehicle Model'   description='e.g. Electra Apex')
        public String selectedModel;

        @InvocableVariable(required=true  label='Selected Date'   description='YYYY-MM-DD')
        public String selectedDate;

        @InvocableVariable(label='User City')
        public String userCity;

        @InvocableVariable(label='User Zip')
        public String userZip;

        @InvocableVariable(label='User Latitude')
        public String userLatitude;

        @InvocableVariable(label='User Longitude')
        public String userLongitude;
    }

    public class DealerInfo {
        @InvocableVariable(label='Dealer Name')
        public String name;
        @InvocableVariable(label='Dealer Address')
        public String address;
        @InvocableVariable(label='Distance (km)')
        public Decimal distance;
        @InvocableVariable(label='Available Slot Labels')
        public List<String> slots;
        @InvocableVariable(label='Showroom Id')
        public String showroomId;
    }

    public class ActionResponse {
        @InvocableVariable(label='Showroom Names')
        public List<String> showroomNames;

        @InvocableVariable(label='Showroom IDs')
        public List<String> showroomIds;

        @InvocableVariable(label='Showroom Slot Options')
        public List<String> showroomSlots;

        @InvocableVariable(label='Showroom Distances')
        public List<String> showroomDistances;

        @InvocableVariable(label='Showroom Addresses')
        public List<String> showroomAddresses;

        @InvocableVariable(label='Showroom Asset Resource IDs'
            description='Pipe-separated ServiceResource IDs of the demo car asset at each dealer')
        public List<String> showroomAssetResourceIds;

        @InvocableVariable(label='Showroom Latitudes')
        public List<String> showroomLatitudes;

        @InvocableVariable(label='Showroom Longitudes')
        public List<String> showroomLongitudes;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    // ─── Entry Point ──────────────────────────────────────────────────────────

    @InvocableMethod(
        label='Get Nearby Dealers and Time Slots'
        description='Returns structured dealer and slot data for the selected model and date.'
    )
    public static List<ActionResponse> execute(List<ActionRequest> requests) {
        List<ActionResponse> responses = new List<ActionResponse>();
        for (ActionRequest req : requests) {
            responses.add(buildResponse(req));
        }
        return responses;
    }

    // ─── Core Logic ───────────────────────────────────────────────────────────

    private static ActionResponse buildResponse(ActionRequest req) {
        ActionResponse res = new ActionResponse();

        // 1. Validate date
        Date requestedDate;
        try {
            requestedDate = Date.valueOf(req.selectedDate);
        } catch (Exception e) {
            res.errorMessage = '❌ Invalid date format. Please use YYYY-MM-DD.';
            return res;
        }

        if (requestedDate < Date.today()) {
            res.errorMessage = '❌ The selected date is in the past. Please choose a future date.';
            return res;
        }

        String dayName = Datetime.newInstance(requestedDate, Time.newInstance(0,0,0,0)).format('EEEE');
        if (dayName == 'Sunday') {
            res.errorMessage = '❌ Our showrooms are closed on Sundays. Please choose another day.';
            return res;
        }

        // 2. Parse coordinates
        Decimal userLat = parseDecimal(req.userLatitude);
        Decimal userLng = parseDecimal(req.userLongitude);

        // 3. Query dealers with the requested model as an Asset
        List<Asset> assets = [
            SELECT Id, Name,
                   Account.Id, Account.Name,
                   Account.BillingStreet, Account.BillingCity,
                   Account.BillingState,  Account.BillingPostalCode,
                   Account.Phone,
                   Account.BillingLatitude, Account.BillingLongitude
            FROM Asset
            WHERE Product2.Name = :req.selectedModel
            AND   Account.RecordType.Name = 'Dealer'
            AND   Account.Id != null
            LIMIT 50
        ];

        if (assets.isEmpty()) {
            assets = [
                SELECT Id, Name,
                       Account.Id, Account.Name,
                       Account.BillingStreet, Account.BillingCity,
                       Account.BillingState,  Account.BillingPostalCode,
                       Account.Phone,
                       Account.BillingLatitude, Account.BillingLongitude
                FROM Asset
                WHERE Account.RecordType.Name = 'Dealer'
                AND   Account.Id != null
                LIMIT 50
            ];
        }

        if (assets.isEmpty()) {
            res.errorMessage = '❌ No dealers found. Please try a different location or model.';
            return res;
        }

        // 4. Deduplicate, compute distance, sort
        Map<Id, DealerRow> dealerMap = new Map<Id, DealerRow>();
        for (Asset a : assets) {
            if (dealerMap.containsKey(a.Account.Id)) continue;
            DealerRow row = new DealerRow();
            row.accountId  = a.Account.Id;
            row.name       = a.Account.Name;
            row.address    = buildAddress(a.Account.BillingStreet, a.Account.BillingCity,
                                          a.Account.BillingState,  a.Account.BillingPostalCode);
            row.phone      = a.Account.Phone != null ? a.Account.Phone : 'N/A';
            row.distanceKm = haversine(userLat, userLng,
                                       a.Account.BillingLatitude, a.Account.BillingLongitude,
                                       req.userCity, a.Account.BillingCity,
                                       req.userZip,  a.Account.BillingPostalCode);
            row.latitude   = a.Account.BillingLatitude;
            row.longitude  = a.Account.BillingLongitude;
            dealerMap.put(a.Account.Id, row);
        }

        List<DealerRow> dealers = dealerMap.values();
        dealers.sort();

        // 5. Resolve service territories + their OperatingHours
        Map<String, Id> territoryByAccountName = new Map<String, Id>();
        Map<Id, Id> ohIdByTerritoryId = new Map<Id, Id>();
        for (ServiceTerritory st : [
            SELECT Id, Name, OperatingHoursId FROM ServiceTerritory WHERE IsActive = true
        ]) {
            territoryByAccountName.put(st.Name.toLowerCase(), st.Id);
            if (st.OperatingHoursId != null) ohIdByTerritoryId.put(st.Id, st.OperatingHoursId);
        }

        Set<Id> territoryIds = new Set<Id>();
        for (DealerRow dr : dealers) {
            String key = dr.name.toLowerCase();
            if (territoryByAccountName.containsKey(key)) {
                dr.serviceTerritoryId = territoryByAccountName.get(key);
                territoryIds.add(dr.serviceTerritoryId);
            }
        }

        // 6. Load TimeSlot records for the day of week across all relevant OH
        String targetDow = dayName; // e.g. 'Thursday'
        Set<Id> ohIds = new Set<Id>();
        for (Id tid : territoryIds) {
            if (ohIdByTerritoryId.containsKey(tid)) ohIds.add(ohIdByTerritoryId.get(tid));
        }

        // Map: ohId → List of TimeSlotInfo (hour + maxAppointments)
        // Primary: query TimeSlot directly
        // Fallback 1: query via AppointmentTopicTimeSlot → WorkTypeGroup "Test Drive"
        // Fallback 2: default 9 hours with capacity 4
        Map<Id, List<SlotInfo>> slotInfoByOH = new Map<Id, List<SlotInfo>>();
        try {
            for (TimeSlot ts : [
                SELECT OperatingHoursId, StartTime, MaxAppointments
                FROM TimeSlot
                WHERE OperatingHoursId IN :ohIds
                AND   DayOfWeek = :targetDow
                AND   Type = 'Normal'
                ORDER BY StartTime ASC
            ]) {
                Id ohId = ts.OperatingHoursId;
                if (!slotInfoByOH.containsKey(ohId)) slotInfoByOH.put(ohId, new List<SlotInfo>());
                slotInfoByOH.get(ohId).add(new SlotInfo(ts.StartTime.hour(), ts.MaxAppointments));
            }
        } catch (Exception e) {
            System.debug('TimeSlot direct query failed: ' + e.getMessage());
        }

        // Fallback 1: AppointmentTopicTimeSlot if TimeSlot returned nothing
        if (slotInfoByOH.isEmpty()) {
            try {
                for (AppointmentTopicTimeSlot atts : [
                    SELECT TimeSlot.OperatingHoursId, TimeSlot.StartTime, TimeSlot.MaxAppointments
                    FROM AppointmentTopicTimeSlot
                    WHERE TimeSlot.OperatingHoursId IN :ohIds
                    AND   TimeSlot.DayOfWeek = :targetDow
                    AND   TimeSlot.Type = 'Normal'
                    AND   WorkTypeGroup.Name = 'Test Drive'
                    ORDER BY TimeSlot.StartTime ASC
                ]) {
                    Id ohId = atts.TimeSlot.OperatingHoursId;
                    if (!slotInfoByOH.containsKey(ohId)) slotInfoByOH.put(ohId, new List<SlotInfo>());
                    slotInfoByOH.get(ohId).add(new SlotInfo(atts.TimeSlot.StartTime.hour(), atts.TimeSlot.MaxAppointments));
                }
                System.debug('AppointmentTopicTimeSlot fallback returned: ' + slotInfoByOH.size() + ' OH entries');
            } catch (Exception e) {
                System.debug('AppointmentTopicTimeSlot fallback failed: ' + e.getMessage());
            }
        }

        // Default slot hours used as final fallback
        List<Integer> defaultHours = new List<Integer>{9,10,11,12,13,14,15,16,17};

        // 6. Holiday + booked slot counts per territory per hour
        Set<Id> holidayTerritoryIds = getHolidayTerritories(requestedDate);
        Map<Id, Set<Integer>> booked = getBookedSlots(territoryIds, requestedDate);

        for (DealerRow dr : dealers) {
            if (dr.serviceTerritoryId != null && holidayTerritoryIds.contains(dr.serviceTerritoryId)) {
                dr.isHoliday = true;
            }
        }

        // 7. Top 5
        List<DealerRow> top5 = new List<DealerRow>();
        for (DealerRow dr : dealers) { if (!dr.isHoliday && top5.size() < 5) top5.add(dr); }
        if (top5.size() < 5) {
            for (DealerRow dr : dealers) { if (dr.isHoliday && top5.size() < 5) top5.add(dr); }
        }

        // 8. Load asset ServiceResource IDs for the requested model at each dealer
        // Map: accountId → ServiceResource Id of the matching demo car
        Set<Id> top5AccountIds = new Set<Id>();
        for (DealerRow dr : top5) top5AccountIds.add(dr.accountId);

        Map<Id, Id> assetSRIdByAccountId = new Map<Id, Id>();
        for (ServiceResource sr : [
            SELECT Id, Asset.AccountId
            FROM ServiceResource
            WHERE ResourceType = 'S'
            AND   IsActive = true
            AND   Asset.AccountId IN :top5AccountIds
            AND   (Asset.Product2.Name = :req.selectedModel
                   OR Asset.Product2.Name LIKE :('%' + req.selectedModel + '%'))
        ]) {
            if (sr.Asset?.AccountId != null && !assetSRIdByAccountId.containsKey(sr.Asset.AccountId)) {
                assetSRIdByAccountId.put(sr.Asset.AccountId, sr.Id);
            }
        }

        List<String> names     = new List<String>();
        List<String> ids       = new List<String>();
        List<String> slotList  = new List<String>();
        List<String> dists     = new List<String>();
        List<String> addrs     = new List<String>();
        List<String> assetSRIds = new List<String>();
        List<String> lats      = new List<String>();
        List<String> lngs      = new List<String>();

        // Use org's timezone (not UTC) so past-slot filtering works correctly
        TimeZone tz = UserInfo.getTimeZone();
        Datetime nowLocal = Datetime.now();
        Integer currentHour = nowLocal.hour() + (tz.getOffset(nowLocal) / 3600000);
        if (currentHour < 0) currentHour += 24;
        if (currentHour >= 24) currentHour -= 24;
        Boolean isToday = requestedDate == Date.today();

        for (DealerRow dr : top5) {
            names.add(dr.name);
            ids.add(dr.accountId);
            addrs.add(dr.address);
            dists.add(String.valueOf(dr.distanceKm));
            lats.add(dr.latitude != null ? String.valueOf(dr.latitude) : '');
            lngs.add(dr.longitude != null ? String.valueOf(dr.longitude) : '');
            // Asset ServiceResource ID for this dealer's demo car
            Id assetSRId = assetSRIdByAccountId.get(dr.accountId);
            assetSRIds.add(assetSRId != null ? assetSRId : '');

            if (dr.isHoliday) {
                slotList.add('CLOSED');
            } else {
                Id tid = dr.serviceTerritoryId;
                Id ohId = ohIdByTerritoryId.containsKey(tid) ? ohIdByTerritoryId.get(tid) : null;
                List<SlotInfo> slotInfos = (ohId != null && slotInfoByOH.containsKey(ohId))
                    ? slotInfoByOH.get(ohId) : new List<SlotInfo>();

                // Fallback: if no TimeSlot records found, use default hours with capacity 4
                if (slotInfos.isEmpty()) {
                    for (Integer h : defaultHours) {
                        slotInfos.add(new SlotInfo(h, 4));
                    }
                }

                Map<Integer, Integer> bookedCountByHour = new Map<Integer, Integer>();
                if (booked.containsKey(tid)) {
                    for (Integer h : booked.get(tid)) {
                        bookedCountByHour.put(h, (bookedCountByHour.containsKey(h) ? bookedCountByHour.get(h) : 0) + 1);
                    }
                }

                List<String> subSlots = new List<String>();
                for (SlotInfo si : slotInfos) {
                    if (isToday && si.hour <= currentHour) continue;
                    Integer bookedCount = bookedCountByHour.containsKey(si.hour) ? bookedCountByHour.get(si.hour) : 0;
                    Integer remaining   = si.maxAppointments - bookedCount;
                    if (remaining > 0) {
                        subSlots.add(formatHour(si.hour) + ' – ' + formatHour(si.hour + 1) + ' (' + remaining + ' left)');
                    }
                }
                slotList.add(subSlots.isEmpty() ? 'FULL' : String.join(subSlots, ';'));
            }
        }

        res.showroomNames           = names;
        res.showroomIds             = ids;
        res.showroomSlots           = slotList;
        res.showroomDistances       = dists;
        res.showroomAddresses       = addrs;
        res.showroomAssetResourceIds = assetSRIds;
        res.showroomLatitudes       = lats;
        res.showroomLongitudes      = lngs;
        return res;
    }

    // ─── Helper Classes ───────────────────────────────────────────────────────

    private class DealerRow implements Comparable {
        String  accountId;
        String  name;
        public String  address;
        public String  phone;
        public Decimal distanceKm;
        public Decimal latitude;
        public Decimal longitude;
        public Id      serviceTerritoryId;
        public Boolean isHoliday = false;

        public Integer compareTo(Object other) {
            DealerRow o = (DealerRow) other;
            if (distanceKm < o.distanceKm) return -1;
            if (distanceKm > o.distanceKm) return  1;
            return 0;
        }
    }

    private class SlotInfo {
        Integer hour;
        Integer maxAppointments;
        SlotInfo(Integer h, Integer m) { hour = h; maxAppointments = m; }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    private static Decimal parseDecimal(String val) {
        if (String.isBlank(val)) return null;
        try { return Decimal.valueOf(val); } catch (Exception e) { return null; }
    }

    private static String buildAddress(String street, String city, String state, String zip) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) parts.add(street);
        if (String.isNotBlank(city))   parts.add(city);
        if (String.isNotBlank(state))  parts.add(state);
        if (String.isNotBlank(zip))    parts.add(zip);
        return parts.isEmpty() ? 'Address not available' : String.join(parts, ', ');
    }

    private static String formatHour(Integer h) {
        if (h < 10) return '0' + h + ':00';
        return h + ':00';
    }

    private static Decimal haversine(
        Decimal uLat, Decimal uLng,
        Decimal dLat, Decimal dLng,
        String  uCity, String dCity,
        String  uZip,  String dZip
    ) {
        if (uLat != null && uLng != null && dLat != null && dLng != null) {
            Double R        = 6371.0;
            Double deltaLat = (dLat - uLat) * Math.PI / 180.0;
            Double deltaLng = (dLng - uLng) * Math.PI / 180.0;
            Double a = Math.sin(deltaLat/2) * Math.sin(deltaLat/2)
                     + Math.cos(uLat * Math.PI / 180.0) * Math.cos(dLat * Math.PI / 180.0)
                     * Math.sin(deltaLng/2) * Math.sin(deltaLng/2);
            Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
            return ((Decimal)(R * c)).setScale(1);
        }
        if (String.isNotBlank(uCity) && String.isNotBlank(dCity)
            && uCity.equalsIgnoreCase(dCity)) return 2.5;
        if (String.isNotBlank(uZip) && String.isNotBlank(dZip)
            && uZip.length() >= 3 && dZip.length() >= 3
            && uZip.substring(0,3) == dZip.substring(0,3)) return 7.0;
        return 25.0;
    }

    private static Set<Id> getHolidayTerritories(Date d) {
        Set<Id> ohIds = new Set<Id>();
        for (OperatingHoursHoliday ohh : [
            SELECT OperatingHoursId FROM OperatingHoursHoliday
            WHERE Holiday.ActivityDate = :d
        ]) {
            ohIds.add(ohh.OperatingHoursId);
        }
        Set<Id> result = new Set<Id>();
        for (ServiceTerritory st : [
            SELECT Id FROM ServiceTerritory WHERE OperatingHoursId IN :ohIds
        ]) {
            result.add(st.Id);
        }
        return result;
    }

    private static Map<Id, Set<Integer>> getBookedSlots(Set<Id> territoryIds, Date d) {
        Map<Id, Set<Integer>> result = new Map<Id, Set<Integer>>();
        if (territoryIds.isEmpty()) return result;
        Datetime dayStart = Datetime.newInstance(d, Time.newInstance(0,0,0,0));
        Datetime dayEnd   = Datetime.newInstance(d, Time.newInstance(23,59,59,0));
        for (ServiceAppointment sa : [
            SELECT ServiceTerritoryId, SchedStartTime
            FROM ServiceAppointment
            WHERE ServiceTerritoryId IN :territoryIds
            AND   SchedStartTime >= :dayStart
            AND   SchedStartTime <= :dayEnd
            AND   Status NOT IN ('Canceled','Cannot Complete')
        ]) {
            if (!result.containsKey(sa.ServiceTerritoryId)) {
                result.put(sa.ServiceTerritoryId, new Set<Integer>());
            }
            result.get(sa.ServiceTerritoryId).add(sa.SchedStartTime.hour());
        }
        return result;
    }
}