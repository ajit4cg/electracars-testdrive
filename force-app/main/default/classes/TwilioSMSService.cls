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
    public static void sendFromFlow(List<SendRequest> requests) {
        for (SendRequest r : requests) {
            if (String.isNotBlank(r.toPhone) && String.isNotBlank(r.messageBody)) {
                String channel = String.isNotBlank(r.channel) ? r.channel : 'WhatsApp';
                sendMessageAsync(r.toPhone, r.messageBody, channel);
            }
        }
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

            if (!toPhone.startsWith('+')) toPhone = '+91' + toPhone;
            if (!fromPhone.startsWith('+')) fromPhone = '+' + fromPhone;

            Boolean isWhatsApp = channel == 'WhatsApp';
            String toAddress   = isWhatsApp ? 'whatsapp:' + toPhone   : toPhone;
            String fromAddress = isWhatsApp ? 'whatsapp:' + fromPhone  : fromPhone;

            String requestBody = 'To='   + EncodingUtil.urlEncode(toAddress,   'UTF-8')
                + '&From=' + EncodingUtil.urlEncode(fromAddress, 'UTF-8')
                + '&Body=' + EncodingUtil.urlEncode(body, 'UTF-8');

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
            return true;
        } catch (Exception e) {
            System.debug('TwilioSMSService.doCalloutDirect error: ' + e.getMessage());
            return false;
        }
    }

    private static void doCallout(String toPhone, String body, String channel) {
        doCalloutDirect(toPhone, body, channel);
    }

    private static TwilioConfig__mdt getTwilioConfig() {
        List<TwilioConfig__mdt> configs = [
            SELECT AccountSid__c, FromPhoneNumber__c
            FROM TwilioConfig__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (configs.isEmpty()) {
            throw new TwilioException('TwilioConfig__mdt record "Default" not found.');
        }
        return configs[0];
    }

    public class TwilioException extends Exception {}
}