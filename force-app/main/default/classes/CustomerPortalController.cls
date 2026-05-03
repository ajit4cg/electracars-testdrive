/**
 * @description Handles customer self-registration and portal operations
 * for the ElectraCars Experience Site.
 */
public without sharing class CustomerPortalController {

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserName() {
        User u = [SELECT FirstName, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return String.isNotBlank(u.FirstName) ? u.FirstName : u.Name;
    }

    @AuraEnabled
    public static LoginResult loginCustomer(String username, String password) {
        LoginResult result = new LoginResult();
        try {
            PageReference nextPage = Site.login(username, password, null);
            result.success = nextPage != null;
            result.redirectUrl = nextPage != null ? nextPage.getUrl() : '/electracars/';
            if (!result.success) {
                result.errorMessage = 'Login failed. Please verify your credentials and try again.';
            }
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    @AuraEnabled
    public static RegistrationResult registerCustomer(
        String firstName, String lastName, String email,
        String phone, String password
    ) {
        RegistrationResult result = new RegistrationResult();
        try {
            // Check if user already exists
            List<User> existingUsers = [SELECT Id FROM User WHERE Email = :email LIMIT 1];
            if (!existingUsers.isEmpty()) {
                result.success = false;
                result.errorMessage = 'An account with this email already exists. Please sign in.';
                return result;
            }

            // Find or create Contact
            List<Contact> existing = [
                SELECT Id, AccountId, Account.OwnerId, Account.Owner.UserRoleId
                FROM Contact
                WHERE Email = :email
                LIMIT 1
            ];
            Contact contact;
            if (existing.isEmpty()) {
                // Use existing ElectraCars Customers account or create without record type
                List<Account> accs = [
                    SELECT Id, OwnerId, Owner.UserRoleId FROM Account 
                    WHERE Name = 'ElectraCars Customers' 
                    AND RecordTypeId = null
                    LIMIT 1
                ];
                Account acc;
                if (accs.isEmpty()) {
                    accs = [
                        SELECT Id, OwnerId, Owner.UserRoleId
                        FROM Account
                        WHERE Name = 'ElectraCars Customers'
                        LIMIT 1
                    ];
                }
                if (accs.isEmpty()) {
                    List<RecordType> rtList = [
                        SELECT Id FROM RecordType
                        WHERE SObjectType = 'Account' AND Name = 'Business Account'
                        AND IsActive = true LIMIT 1
                    ];
                    acc = new Account(
                        Name = 'ElectraCars Customers',
                        OwnerId = getPortalAccountOwnerId()
                    );
                    if (!rtList.isEmpty()) acc.RecordTypeId = rtList[0].Id;
                    insert acc;
                } else {
                    acc = accs[0];
                    if (acc.Owner == null || acc.Owner.UserRoleId == null) {
                        acc.OwnerId = getPortalAccountOwnerId();
                        update acc;
                    }
                }
                contact = new Contact(
                    FirstName = firstName,
                    LastName  = lastName,
                    Email     = email,
                    Phone     = phone,
                    AccountId = acc.Id
                );
                insert contact;
            } else {
                contact = existing[0];
                if (
                    contact.AccountId != null &&
                    (contact.Account == null || contact.Account.Owner == null || contact.Account.Owner.UserRoleId == null)
                ) {
                    update new Account(
                        Id = contact.AccountId,
                        OwnerId = getPortalAccountOwnerId()
                    );
                }
            }

            // Get Customer Community Login profile
            Profile communityProfile = [
                SELECT Id FROM Profile
                WHERE Name = 'Customer Community Login User'
                LIMIT 1
            ];

            String alias    = (firstName.left(1) + lastName.left(4)).toLowerCase().left(8);
            String nickname = (firstName + String.valueOf(System.currentTimeMillis()).right(4)).left(40);

            User newUser = new User(
                FirstName         = firstName,
                LastName          = lastName,
                Email             = email,
                Phone             = phone,
                Username          = email,
                Alias             = alias,
                CommunityNickname = nickname,
                ProfileId         = communityProfile.Id,
                ContactId         = contact.Id,
                TimeZoneSidKey    = 'Asia/Kolkata',
                LocaleSidKey      = 'en_IN',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                IsActive          = true
            );

            String newUserId = Site.createExternalUser(newUser, contact.Id, password, false);
            result.success = String.isNotBlank(newUserId);
            result.userId  = newUserId;
            if (!result.success) {
                result.errorMessage = 'Registration failed. Please try again.';
            }

        } catch (Site.ExternalUserCreateException ex) {
            result.success = false;
            List<String> displayMessages = ex.getDisplayMessages();
            result.errorMessage = !displayMessages.isEmpty()
                ? String.join(displayMessages, ' ')
                : ex.getMessage();
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<TestDrive__c> getMyBookings() {
        User currentUser = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (currentUser.ContactId == null) return new List<TestDrive__c>();

        Contact contact = [SELECT Email FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1];

        return [
            SELECT Id, Name, VehicleModel__c, PreferredDate__c, PreferredTime__c,
                   Status__c, AssignedDealership__r.Name, CreatedDate
            FROM TestDrive__c
            WHERE CustomerEmail__c = :contact.Email
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
    }

    public class RegistrationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  userId;
        @AuraEnabled public String  errorMessage;
    }

    public class LoginResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  redirectUrl;
        @AuraEnabled public String  errorMessage;
    }

    private static Id getPortalAccountOwnerId() {
        List<User> ownerCandidates = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRoleId != null
            AND UserType = 'Standard'
            ORDER BY LastLoginDate DESC NULLS LAST, CreatedDate ASC
            LIMIT 1
        ];

        if (ownerCandidates.isEmpty()) {
            throw new AuraHandledException(
                'No active internal user with a role is available to own customer accounts.'
            );
        }

        return ownerCandidates[0].Id;
    }
}