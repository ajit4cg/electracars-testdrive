/**
 * @description Routes test drive bookings to the nearest dealership based on zip code.
 */
public with sharing class DealershipRoutingService {

    public static Account routeByZip(String zipCode) {
        List<Account> dealers = queryDealerships(zipCode, 1);
        return dealers.isEmpty() ? null : dealers[0];
    }

    public static List<TestDriveBookingController.DealershipInfo> findNearestDealerships(String zipCode, Integer maxResults) {
        List<TestDriveBookingController.DealershipInfo> results = new List<TestDriveBookingController.DealershipInfo>();
        for (Account a : queryDealerships(zipCode, maxResults)) {
            TestDriveBookingController.DealershipInfo info = new TestDriveBookingController.DealershipInfo();
            info.id      = a.Id;
            info.name    = a.Name;
            info.address = a.BillingStreet;
            info.city    = a.BillingCity + ', ' + a.BillingState;
            info.phone   = a.Phone;
            results.add(info);
        }
        return results;
    }

    private static List<Account> queryDealerships(String zipCode, Integer maxResults) {
        String zipPrefix = zipCode.length() >= 3 ? zipCode.left(3) + '%' : zipCode + '%';

        List<Account> dealers = [
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, 
                   BillingLatitude, BillingLongitude, Phone
            FROM Account
            WHERE BillingPostalCode LIKE :zipPrefix
            ORDER BY BillingPostalCode
            LIMIT :maxResults
        ];

        if (dealers.isEmpty()) {
            dealers = [
                SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, 
                       BillingLatitude, BillingLongitude, Phone
                FROM Account
                ORDER BY Name
                LIMIT :maxResults
            ];
        }
        return dealers;
    }
}