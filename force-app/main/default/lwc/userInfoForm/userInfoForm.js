import { LightningElement, api, track } from 'lwc';
import saveUserInfoFromLWC from '@salesforce/apex/AgentInputController.saveUserInfoFromLWC';

export default class userInfoForm extends LightningElement {

    // ── @api props — prefilled by Agentforce from context variables ───────────
    @api messagingSessionId;
    @api firstName    = '';
    @api lastName     = '';
    @api mobile       = '';
    @api emailId      = '';
    @api city         = '';
    @api zip          = '';
    @api vehicleModel = '';

    // ── State ─────────────────────────────────────────────────────────────────
    @track isDisabled   = false;
    @track isSubmitted  = false;
    @track errorMessage = '';

    get showForm()    { return !this.isSubmitted; }
    get readOnly()    { return this.isDisabled; }
    get submitLabel() { return this.isDisabled ? 'Saving…' : 'Confirm & Continue'; }

    // ── lightning-input fires onchange with event.detail.value ────────────────
    handleInputChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    // ── Submit ────────────────────────────────────────────────────────────────
    handleSubmit() {
        this.errorMessage = '';

        if (!this.firstName || !this.lastName || !this.mobile || !this.emailId) {
            this.errorMessage = 'Please fill in First Name, Last Name, Mobile and Email.';
            return;
        }

        this.isDisabled = true;

        saveUserInfoFromLWC({
            messagingSessionId : this.messagingSessionId,
            firstName          : this.firstName,
            lastName           : this.lastName,
            mobile             : this.mobile,
            emailId            : this.emailId,
            city               : this.city,
            zip                : this.zip,
            vehicleModel       : this.vehicleModel
        })
        .then(() => {
            this.isSubmitted = true;

            // Fire event — Agentforce picks this up to move to next subagent
            this.dispatchEvent(new CustomEvent('confirmed', {
                bubbles  : true,
                composed : true,
                detail   : {
                    firstName    : this.firstName,
                    lastName     : this.lastName,
                    mobile       : this.mobile,
                    emailId      : this.emailId,
                    city         : this.city,
                    zip          : this.zip,
                    vehicleModel : this.vehicleModel
                }
            }));
        })
        .catch(error => {
            this.isDisabled   = false;
            this.errorMessage = 'Could not save your details. Please try again.';
            console.error('userInfoForm save error:', error);
        });
    }
}