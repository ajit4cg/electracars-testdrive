public with sharing class AgentInputController {

    @InvocableMethod(
        label='Capture User Info from Agent'
        description='Shows a prefilled editable form with user details from MessagingSession. User confirms or edits, then submits.'
    )
    public static List<UserInfoResponse> captureUserInfo(List<UserInfoRequest> requests) {
        List<UserInfoResponse> responses = new List<UserInfoResponse>();

        for (UserInfoRequest req : requests) {
            UserInfoForm f = req.userInfo != null ? req.userInfo : new UserInfoForm();

            if (String.isNotBlank(req.messagingSessionId)) {
                try {
                    MessagingSession session = [
                        SELECT Id, first_name__c, last_name__c, email_id__c,
                               mobile__c, city__c, zip__c, Vehicle_Model__c
                        FROM MessagingSession
                        WHERE Id = :req.messagingSessionId
                        LIMIT 1
                    ];
                    if (String.isNotBlank(f.firstName))    session.first_name__c    = f.firstName;
                    if (String.isNotBlank(f.lastName))     session.last_name__c     = f.lastName;
                    if (String.isNotBlank(f.mobile))       session.mobile__c        = f.mobile;
                    if (String.isNotBlank(f.emailId))      session.email_id__c      = f.emailId;
                    if (String.isNotBlank(f.city))         session.city__c          = f.city;
                    if (String.isNotBlank(f.zip))          session.zip__c           = f.zip;
                    if (String.isNotBlank(f.vehicleModel)) session.Vehicle_Model__c = f.vehicleModel;
                    update session;
                } catch (Exception e) {
                    System.debug('AgentInputController update failed: ' + e.getMessage());
                }
            }

            UserInfoResponse res = new UserInfoResponse();
            res.firstName    = f.firstName;
            res.lastName     = f.lastName;
            res.mobile       = f.mobile;
            res.emailId      = f.emailId;
            res.city         = f.city;
            res.zip          = f.zip;
            res.vehicleModel = f.vehicleModel;
            res.success      = true;
            responses.add(res);
        }

        return responses;
    }

    @AuraEnabled
    public static UserInfoResponse saveUserInfoFromLWC(
        String messagingSessionId,
        String firstName, String lastName, String mobile,
        String emailId, String city, String zip, String vehicleModel
    ) {
        UserInfoForm f   = new UserInfoForm();
        f.firstName      = firstName;
        f.lastName       = lastName;
        f.mobile         = mobile;
        f.emailId        = emailId;
        f.city           = city;
        f.zip            = zip;
        f.vehicleModel   = vehicleModel;

        UserInfoRequest req    = new UserInfoRequest();
        req.messagingSessionId = messagingSessionId;
        req.userInfo           = f;

        return captureUserInfo(new List<UserInfoRequest>{ req })[0];
    }

    public class UserInfoRequest {
        @InvocableVariable(description='Messaging Session Id for the current conversation')
        public String messagingSessionId;

        @InvocableVariable(description='User details to confirm or edit')
        public UserInfoForm userInfo;
    }

    public class UserInfoForm {
        @InvocableVariable(description='First name of the customer')
        public String firstName;

        @InvocableVariable(description='Last name of the customer')
        public String lastName;

        @InvocableVariable(description='Mobile number of the customer')
        public String mobile;

        @InvocableVariable(description='Email address of the customer')
        public String emailId;

        @InvocableVariable(description='City of the customer')
        public String city;

        @InvocableVariable(description='Zip or postal code of the customer')
        public String zip;

        @InvocableVariable(description='Vehicle model the customer wants to test drive')
        public String vehicleModel;
    }

    public class UserInfoResponse {
        @InvocableVariable(description='First name of the customer')
        public String firstName;

        @InvocableVariable(description='Last name of the customer')
        public String lastName;

        @InvocableVariable(description='Mobile number of the customer')
        public String mobile;

        @InvocableVariable(description='Email address of the customer')
        public String emailId;

        @InvocableVariable(description='City of the customer')
        public String city;

        @InvocableVariable(description='Zip or postal code of the customer')
        public String zip;

        @InvocableVariable(description='Vehicle model the customer wants to test drive')
        public String vehicleModel;

        @InvocableVariable(description='Whether the action completed successfully')
        public Boolean success;
    }

    // ─── Legacy AuraEnabled methods ───────────────────────────────────────────

    @AuraEnabled
    public static void updateMessagingSessionByConversationId(
        String conversationId,
        String firstName, String lastName, String email, String phone,
        String city, String zip, String latitude, String longitude
    ) {
        if (String.isBlank(conversationId)) throw new AuraHandledException('Conversation ID is required.');
        List<MessagingSession> sessions = [
            SELECT Id, first_name__c, last_name__c, email_id__c, mobile__c,
                   city__c, zip__c, latitude__c, longitude__c
            FROM MessagingSession WHERE ConversationId = :conversationId LIMIT 1
        ];
        if (sessions.isEmpty()) return;
        MessagingSession s = sessions[0];
        s.first_name__c = firstName; s.last_name__c = lastName;
        s.email_id__c   = email;     s.mobile__c    = phone;
        s.city__c       = city;      s.zip__c       = zip;
        s.latitude__c   = latitude;  s.longitude__c = longitude;
        update s;
    }

    @AuraEnabled
    public static void updateMessagingSession(
        String messagingSessionId,
        String firstName, String lastName, String email, String phone,
        String city, String zip, String latitude, String longitude
    ) {
        if (String.isBlank(messagingSessionId)) throw new AuraHandledException('Messaging Session ID is required.');
        MessagingSession s = [
            SELECT Id, first_name__c, last_name__c, email_id__c, mobile__c,
                   city__c, zip__c, latitude__c, longitude__c
            FROM MessagingSession WHERE Id = :messagingSessionId LIMIT 1
        ];
        s.first_name__c = firstName; s.last_name__c = lastName;
        s.email_id__c   = email;     s.mobile__c    = phone;
        s.city__c       = city;      s.zip__c       = zip;
        s.latitude__c   = latitude;  s.longitude__c = longitude;
        update s;
    }
}