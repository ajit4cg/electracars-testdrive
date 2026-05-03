/**
 * SendSMSAction
 * ─────────────────────────────────────────────────────────────────────────────
 * Flow-callable Apex action that sends SMS/WhatsApp via Twilio synchronously.
 * Uses Named Credential (TwilioCredential) + TwilioConfig__mdt (DeveloperName = 'Sakshi').
 */
public without sharing class SendSMSAction {

    @InvocableMethod(
        label='Send SMS via Twilio'
        description='Sends an SMS or WhatsApp message via Twilio. Use in flows after test drive booking.'
    )
    public static void sendSMS(List<SMSRequest> requests) {
        for (SMSRequest req : requests) {
            if (String.isBlank(req.toPhone) || String.isBlank(req.message)) continue;
            doCallout(req.toPhone, req.message);
        }
    }

    private static void doCallout(String toPhone, String body) {
        try {
            TwilioConfig__mdt config = [
                SELECT AccountSid__c, FromPhoneNumber__c
                FROM TwilioConfig__mdt
                WHERE DeveloperName = 'Sakshi'
                LIMIT 1
            ];

            String accountSid = config.AccountSid__c;
            String fromPhone  = config.FromPhoneNumber__c;

            if (!toPhone.startsWith('+'))    toPhone   = '+91' + toPhone;
            if (!fromPhone.startsWith('+'))  fromPhone = '+' + fromPhone;

            String requestBody = 'To='   + EncodingUtil.urlEncode(toPhone,   'UTF-8')
                + '&From=' + EncodingUtil.urlEncode(fromPhone, 'UTF-8')
                + '&Body=' + EncodingUtil.urlEncode(body, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:TwilioCredential/2010-04-01/Accounts/' + accountSid + '/Messages.json');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setBody(requestBody);

            HttpResponse res = new Http().send(req);
            System.debug('Twilio SMS status: ' + res.getStatusCode());
            if (res.getStatusCode() != 201) {
                System.debug('Twilio error: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('SendSMSAction.doCallout error: ' + e.getMessage());
        }
    }

    public class SMSRequest {
        @InvocableVariable(label='To Phone' required=true
            description='Recipient phone number e.g. +919513215412')
        public String toPhone;

        @InvocableVariable(label='Message' required=true
            description='SMS message body')
        public String message;
    }
}