/**
 * @description Sends booking confirmations via SMS (Twilio) or Email.
 */
public without sharing class TestDriveNotificationService {

    public static void sendConfirmation(TestDrive__c td, Lead lead, Account dealership) {
        String channel = td.PreferredChannel__c;
        Boolean smsSent = false;

        if ((channel == 'SMS' || channel == 'WhatsApp') && String.isNotBlank(lead.Phone)) {
            String phone = normalizePhone(lead.Phone);
            String message = buildSMSBody(td, lead, dealership);
            smsSent = TwilioSMSService.sendMessage(phone, message, channel);
        }

        // Always send email as backup, or if SMS not requested
        if (!smsSent && String.isNotBlank(lead.Email)) {
            sendEmailConfirmation(td, lead, dealership);
        }
    }

    /**
     * @description Direct callout version — call this from inside a @future(callout=true) context.
     * Does NOT spawn another @future. Callouts are made inline.
     */
    public static void sendConfirmationDirect(TestDrive__c td, Lead lead, Account dealership) {
        String channel = td.PreferredChannel__c;
        Boolean smsSent = false;

        if ((channel == 'SMS' || channel == 'WhatsApp') && String.isNotBlank(lead.Phone)) {
            String phone = normalizePhone(lead.Phone);
            String message = buildSMSBody(td, lead, dealership);
            // Call doCallout directly — already in async callout context
            smsSent = TwilioSMSService.doCalloutDirect(phone, message, channel);
        }

        // Always send email as backup, or if SMS not requested
        if (!smsSent && String.isNotBlank(lead.Email)) {
            sendEmailConfirmation(td, lead, dealership);
        }
    }

    // ─── SMS body ──────────────────────────────────────────────────────────────

    private static String buildSMSBody(TestDrive__c td, Lead lead, Account dealership) {
        String msg = 'Hi ' + lead.FirstName + '! Your Electra Cars test drive is confirmed.\n'
            + 'Ref: ' + td.Name + '\n'
            + 'Vehicle: ' + td.VehicleModel__c + '\n'
            + 'Date: ' + td.PreferredDate__c.format() + '\n'
            + 'Time: ' + td.PreferredTime__c;
        if (dealership != null) {
            msg += '\nLocation: ' + dealership.Name;
            // Add address if available
            List<String> addrParts = new List<String>();
            if (String.isNotBlank(dealership.BillingStreet)) addrParts.add(dealership.BillingStreet);
            if (String.isNotBlank(dealership.BillingCity))   addrParts.add(dealership.BillingCity);
            if (!addrParts.isEmpty()) {
                msg += ', ' + String.join(addrParts, ', ');
            }
            // Add Google Maps link — prefer coordinates for accuracy
            String mapsUrl;
            if (dealership.BillingLatitude != null && dealership.BillingLongitude != null) {
                mapsUrl = 'https://maps.google.com/?q=' + dealership.BillingLatitude + ',' + dealership.BillingLongitude;
            } else if (String.isNotBlank(dealership.BillingStreet) && String.isNotBlank(dealership.BillingCity)) {
                String fullAddress = dealership.Name + ', ' + dealership.BillingStreet + ', ' + dealership.BillingCity;
                mapsUrl = 'https://maps.google.com/?q=' + EncodingUtil.urlEncode(fullAddress, 'UTF-8');
            } else {
                mapsUrl = 'https://maps.google.com/?q=' + EncodingUtil.urlEncode(dealership.Name, 'UTF-8');
            }
            msg += '\n📍 Directions: ' + mapsUrl;
        }
        msg += '\nSee you soon! - Electra Cars';
        return msg;
    }

    // ─── Email ─────────────────────────────────────────────────────────────────

    private static void sendEmailConfirmation(TestDrive__c td, Lead lead, Account dealership) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ lead.Email });
        mail.setSubject('Your Electra Cars Test Drive is Confirmed - ' + td.Name);
        mail.setHtmlBody(buildEmailBody(td, lead, dealership));
        mail.setSaveAsActivity(true);

        // Use org-wide email address if available so guest-context sends don't fail
        try {
            List<OrgWideEmailAddress> owas = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                LIMIT 1
            ];
            if (!owas.isEmpty()) {
                mail.setOrgWideEmailAddressId(owas[0].Id);
            }
        } catch (Exception ex) {
            System.debug('OrgWideEmailAddress lookup skipped: ' + ex.getMessage());
        }

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Email send failed: ' + e.getMessage());
        }
    }

    private static String buildEmailBody(TestDrive__c td, Lead lead, Account dealership) {
        String dealerInfo = dealership != null
            ? '<tr><td style="padding:8px"><strong>Location</strong></td><td>' + dealership.Name + '</td></tr>'
            : '';
        return '<html><body style="font-family:Arial,sans-serif;max-width:600px;margin:auto">'
            + '<div style="background:#1a1a2e;padding:20px;text-align:center">'
            + '<h1 style="color:#e94560">Electra Cars</h1></div>'
            + '<div style="padding:30px">'
            + '<h2>Test Drive Confirmed!</h2>'
            + '<p>Hi ' + lead.FirstName + ',</p>'
            + '<p>Your booking <strong>' + td.Name + '</strong> is confirmed.</p>'
            + '<table style="width:100%;border-collapse:collapse">'
            + '<tr><td style="padding:8px;border-bottom:1px solid #eee"><strong>Vehicle</strong></td><td>' + td.VehicleModel__c + '</td></tr>'
            + '<tr><td style="padding:8px;border-bottom:1px solid #eee"><strong>Date</strong></td><td>' + td.PreferredDate__c.format() + '</td></tr>'
            + '<tr><td style="padding:8px;border-bottom:1px solid #eee"><strong>Time</strong></td><td>' + td.PreferredTime__c + '</td></tr>'
            + dealerInfo
            + '</table>'
            + '<p style="margin-top:20px">We look forward to seeing you!</p>'
            + '<p style="color:#e94560"><strong>Team Electra Cars</strong></p>'
            + '</div></body></html>';
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    private static String normalizePhone(String phone) {
        String cleaned = phone.replaceAll('[^0-9+]', '');
        if (!cleaned.startsWith('+')) {
            cleaned = '+91' + cleaned; // India default - change if needed
        }
        return cleaned;
    }
}