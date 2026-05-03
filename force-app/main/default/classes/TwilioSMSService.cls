/**
 * @description Sends SMS via Twilio REST API.
 * Uses @future to avoid "uncommitted work pending" error when called after DML.
 */
public without sharing class TwilioSMSService {

    private static final String NAMED_CREDENTIAL = 'callout:TwilioCredential';

    /**
     * @description Invocable entry point for Flows and Agent Actions.
     * Accepts a list of SendRequest and dispatches each asynchronously.
     */
    @InvocableMethod(label='Send WhatsApp or SMS via Twilio' description='Sends a WhatsApp or SMS message via Twilio. Set channel to WhatsApp or SMS.')
    public static List<SendResponse> sendFromFlow(List<SendRequest> requests) {
        List<SendResponse> responses = new List<SendResponse>();
        for (SendRequest r : requests) {
            SendResponse resp = new SendResponse();
            if (String.isNotBlank(r.toPhone) && String.isNotBlank(r.messageBody)) {
                String channel = String.isNotBlank(r.channel) ? r.channel : 'WhatsApp';
                // Try synchronous send first
                Boolean success = doCalloutDirect(r.toPhone, r.messageBody, channel);
                if (success) {
                    resp.success = true;
                    resp.message = 'SMS sent successfully to ' + r.toPhone;
                } else {
                    resp.success = false;
                    resp.message = 'Failed to send SMS to ' + r.toPhone + '. Check debug logs.';
                }
            } else {
                resp.success = false;
                resp.message = 'Missing phone number or message body';
            }
            responses.add(resp);
        }
        return responses;
    }

    public class SendResponse {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    public class SendRequest {
        @InvocableVariable(label='To Phone Number' description='E.164 format e.g. +919876543210' required=true)
        public String toPhone;

        @InvocableVariable(label='Message Body' required=true)
        public String messageBody;

        @InvocableVariable(label='Channel' description='WhatsApp or SMS (default: WhatsApp)')
        public String channel;
    }

    /**
     * @description Entry point - schedules async SMS/WhatsApp send
     * Safe to call after DML operations
     */
    public static Boolean sendMessage(String toPhone, String body, String channel) {
        // Queue the message send asynchronously to avoid "uncommitted work" error
        sendMessageAsync(toPhone, body, channel);
        return true;
    }

    public static Boolean sendSMS(String toPhone, String body) {
        sendMessageAsync(toPhone, body, 'SMS');
        return true;
    }

    @future(callout=true)
    public static void sendSMSAsync(String toPhone, String body) {
        doCallout(toPhone, body, 'SMS');
    }

    @future(callout=true)
    public static void sendMessageAsync(String toPhone, String body, String channel) {
        doCallout(toPhone, body, channel);
    }

    /**
     * @description Direct callout — use this when already inside a @future(callout=true) context.
     * Returns true if message was sent successfully.
     */
    public static Boolean doCalloutDirect(String toPhone, String body, String channel) {
        try {
            TwilioConfig__mdt config = getTwilioConfig();
            String accountSid = config.AccountSid__c;
            String fromPhone  = config.FromPhoneNumber__c;

            if (String.isBlank(toPhone) || String.isBlank(body)) {
                System.debug('TwilioSMSService: Missing phone or body');
                return false;
            }

            if (!toPhone.startsWith('+')) toPhone = '+91' + toPhone;
            if (!fromPhone.startsWith('+')) fromPhone = '+' + fromPhone;

            Boolean isWhatsApp = channel == 'WhatsApp';
            String toAddress   = isWhatsApp ? 'whatsapp:' + toPhone   : toPhone;
            String fromAddress = isWhatsApp ? 'whatsapp:' + fromPhone  : fromPhone;

            String requestBody = 'To='   + EncodingUtil.urlEncode(toAddress,   'UTF-8')
                + '&From=' + EncodingUtil.urlEncode(fromAddress, 'UTF-8')
                + '&Body=' + EncodingUtil.urlEncode(body, 'UTF-8');

            System.debug('TwilioSMSService: Sending ' + channel + ' to ' + toPhone);
            System.debug('TwilioSMSService: Request body: ' + requestBody);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + '/2010-04-01/Accounts/' + accountSid + '/Messages.json');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(requestBody);

            HttpResponse res = new Http().send(req);
            System.debug('Twilio ' + channel + ' to ' + toPhone + ' status: ' + res.getStatusCode());
            if (res.getStatusCode() != 201) {
                System.debug('Twilio error body: ' + res.getBody());
                return false;
            }
            System.debug('Twilio ' + channel + ' sent successfully');
            return true;
        } catch (Exception e) {
            System.debug('TwilioSMSService.doCalloutDirect error: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return false;
        }
    }

    private static void doCallout(String toPhone, String body, String channel) {
        doCalloutDirect(toPhone, body, channel);
    }

    private static TwilioConfig__mdt getTwilioConfig() {
        List<TwilioConfig__mdt> configs = [
            SELECT DeveloperName, AccountSid__c, FromPhoneNumber__c
            FROM TwilioConfig__mdt
            ORDER BY DeveloperName ASC
            LIMIT 10
        ];
        if (configs.isEmpty()) {
            throw new TwilioException('No TwilioConfig__mdt records found.');
        }
        
        // Prioritize Default config first
        for (TwilioConfig__mdt config : configs) {
            if (config.DeveloperName == 'Default') {
                return config;  // Use Default config
            }
        }
        
        return configs[0];  // Fallback to first config
    }

    public class TwilioException extends Exception {}
}