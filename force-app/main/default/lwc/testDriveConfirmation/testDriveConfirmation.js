import { LightningElement, api } from 'lwc';

export default class TestDriveConfirmation extends LightningElement {
    @api bookingRef;
    @api vehicle;
    @api preferredDate;
    @api preferredTime;
    @api dealershipName;
    @api dealershipAddress;
    @api dealershipMapsUrl;
    @api channel;
    @api customerName;

    addToCalendar() {
        // Build a Google Calendar URL as a universal fallback
        const title = encodeURIComponent(`Electra Cars Test Drive - ${this.vehicle}`);
        const details = encodeURIComponent(`Booking: ${this.bookingRef}\nDealership: ${this.dealershipName || ''}`);
        const location = encodeURIComponent(this.dealershipAddress || '');
        const date = this.preferredDate?.replace(/-/g, '') || '';
        const url = `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${title}&details=${details}&location=${location}&dates=${date}/${date}`;
        window.open(url, '_blank');
    }

    bookAnother() {
        this.dispatchEvent(new CustomEvent('bookanother', { bubbles: true, composed: true }));
        // Reload the page to reset the booking flow
        window.location.reload();
    }
}