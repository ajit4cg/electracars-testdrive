import { LightningElement, api, track } from 'lwc';
import getDealersAndSlotsForLWC from '@salesforce/apex/DealerSlotController.getDealersAndSlotsForLWC';
import saveSelection from '@salesforce/apex/DealerSlotController.saveSelection';

const MONTH_NAMES = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
];

export default class DealerSlotPicker extends LightningElement {

    // ── Props passed from parent / agent context ──────────────────────────────
    @api selectedModel;
    @api userCity;
    @api userZip;
    @api userLatitude;
    @api userLongitude;
    @api messagingSessionId;

    // selectedDate is now internal — driven by calendar pick
    @track selectedDate = null;

    // ── UI state ──────────────────────────────────────────────────────────────
    @track showDatePicker  = true;   // Phase 1
    @track showPickerPhase = false;  // Phase 2+3
    @track isLoading       = false;
    @track isDisabled      = false;
    @track errorMessage    = '';
    @track showPicker      = false;

    // ── Calendar state ────────────────────────────────────────────────────────
    @track _calYear;
    @track _calMonth;   // 0-indexed

    // ── Dealer / slot data ────────────────────────────────────────────────────
    @track dealers   = [];
    @track timeSlots = [];

    // ── Selection state ───────────────────────────────────────────────────────
    _selectedDealerId            = null;
    _selectedDealerName          = null;
    _selectedDealerAccountId     = null;
    _selectedServiceTerritoryId  = null;
    _selectedServiceResourceId   = null;
    _selectedServiceResourceName = null;
    _selectedSlotLabel           = null;
    _selectedSlotStart           = null;
    _selectedSlotEnd             = null;

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        const today = new Date();
        this._calYear  = today.getFullYear();
        this._calMonth = today.getMonth();
    }

    // ── Calendar computed properties ──────────────────────────────────────────

    get calMonthLabel() {
        return MONTH_NAMES[this._calMonth] + ' ' + this._calYear;
    }

    get isPrevDisabled() {
        const today = new Date();
        return this._calYear === today.getFullYear() && this._calMonth === today.getMonth();
    }

    // Build the leading blank cells so day 1 falls on the right weekday
    get leadingBlanks() {
        const firstDay = new Date(this._calYear, this._calMonth, 1).getDay(); // 0=Sun
        const blanks = [];
        for (let i = 0; i < firstDay; i++) blanks.push(i);
        return blanks;
    }

    // Build each day cell with its CSS class
    get calDays() {
        const today     = new Date();
        today.setHours(0, 0, 0, 0);
        const daysInMonth = new Date(this._calYear, this._calMonth + 1, 0).getDate();
        const days = [];

        for (let d = 1; d <= daysInMonth; d++) {
            const date    = new Date(this._calYear, this._calMonth, d);
            const iso     = this._toISO(date);
            const isPast  = date < today;
            const isSun   = date.getDay() === 0;
            const isToday = date.getTime() === today.getTime();
            const disabled = isPast || isSun;

            let cellClass = 'cal-cell';
            if (disabled)              cellClass += ' cal-disabled';
            else if (iso === this.selectedDate) cellClass += ' cal-selected';
            else if (isToday)          cellClass += ' cal-today';
            else                       cellClass += ' cal-available';

            days.push({ num: d, iso, cellClass, disabled });
        }
        return days;
    }

    // ── Calendar navigation ───────────────────────────────────────────────────

    prevMonth() {
        if (this.isPrevDisabled) return;
        if (this._calMonth === 0) {
            this._calMonth = 11;
            this._calYear--;
        } else {
            this._calMonth--;
        }
    }

    nextMonth() {
        if (this._calMonth === 11) {
            this._calMonth = 0;
            this._calYear++;
        } else {
            this._calMonth++;
        }
    }

    // ── Day click → transition to Phase 2 ────────────────────────────────────

    handleDayClick(event) {
        const iso = event.currentTarget.dataset.iso;
        // Find the day object to check if disabled
        const day = this.calDays.find(d => d.iso === iso);
        if (!day || day.disabled) return;

        this.selectedDate    = iso;
        this.showDatePicker  = false;
        this.showPickerPhase = true;
        this.loadDealers();
    }

    handleChangeDate() {
        // Go back to calendar, reset dealer/slot state
        this.showDatePicker  = true;
        this.showPickerPhase = false;
        this.showPicker      = false;
        this.errorMessage    = '';
        this.dealers         = [];
        this.timeSlots       = [];
        this._clearSelection();
    }

    // ── Load dealers for selected date ────────────────────────────────────────

    loadDealers() {
        this.isLoading    = true;
        this.showPicker   = false;
        this.errorMessage = '';

        getDealersAndSlotsForLWC({
            selectedModel : this.selectedModel,
            userCity      : this.userCity,
            userZip       : this.userZip,
            userLatitude  : this.userLatitude,
            userLongitude : this.userLongitude,
            selectedDate  : this.selectedDate
        })
        .then(result => {
            this.isLoading = false;

            if (result.errorMessage) {
                this.errorMessage = result.errorMessage;
                this.showPicker   = false;
                return;
            }

            this.dealers = (result.dealers || []).map(d => ({
                ...d,
                isSelected: false
            }));

            this.timeSlots = (result.timeSlots || [])
                .filter(s => s.isAvailable)
                .map(s => ({
                    ...s,
                    isSelected: false
                }));

            this.showPicker = this.dealers.length > 0;
            if (!this.showPicker) {
                this.errorMessage = 'No dealers available for the selected date and model.';
            }
        })
        .catch(error => {
            this.isLoading    = false;
            this.errorMessage = 'Error loading dealers. Please try again.';
            console.error('dealerSlotPicker error:', error);
        });
    }

    // ── Dealer selection ──────────────────────────────────────────────────────

    handleDealerSelect(event) {
        const selectedId = event.target.dataset.id;
        this.dealers = this.dealers.map(d => ({
            ...d,
            isSelected: d.dealerAccountId === selectedId ? event.target.checked : false
        }));

        const selected = this.dealers.find(d => d.dealerAccountId === selectedId && d.isSelected);
        if (selected) {
            this._selectedDealerId             = selected.dealerAccountId;
            this._selectedDealerName           = selected.dealerName;
            this._selectedDealerAccountId      = selected.dealerAccountId;
            this._selectedServiceTerritoryId   = selected.serviceTerritoryId;
            this._selectedServiceResourceId    = selected.serviceResourceId;
            this._selectedServiceResourceName  = selected.serviceResourceName;
        } else {
            this._selectedDealerId   = null;
            this._selectedDealerName = null;
        }
    }

    // ── Slot selection ────────────────────────────────────────────────────────

    handleSlotSelect(event) {
        const selectedLabel = event.target.dataset.label;
        this.timeSlots = this.timeSlots.map(s => ({
            ...s,
            isSelected: s.label === selectedLabel ? event.target.checked : false
        }));

        const selected = this.timeSlots.find(s => s.label === selectedLabel && s.isSelected);
        if (selected) {
            this._selectedSlotLabel = selected.label;
            this._selectedSlotStart = selected.startHour;
            this._selectedSlotEnd   = selected.endHour;
        } else {
            this._selectedSlotLabel = null;
        }
    }

    // ── Submit → save + fire event to next subagent ───────────────────────────

    handleSubmit() {
        if (!this.hasSelection) return;
        this.isDisabled = true;

        saveSelection({
            messagingSessionId   : this.messagingSessionId,
            dealerAccountId      : this._selectedDealerAccountId,
            dealerName           : this._selectedDealerName,
            serviceTerritoryId   : this._selectedServiceTerritoryId,
            serviceResourceId    : this._selectedServiceResourceId,
            serviceResourceName  : this._selectedServiceResourceName,
            selectedSlotLabel    : this._selectedSlotLabel,
            selectedSlotStartHour: this._selectedSlotStart,
            selectedSlotEndHour  : this._selectedSlotEnd
        })
        .then(() => {
            // Fire event — parent / agent picks this up to move to next subagent
            this.dispatchEvent(new CustomEvent('submit', {
                bubbles: true,
                composed: true,
                detail: {
                    selectedDate          : this.selectedDate,
                    selectedModel         : this.selectedModel,
                    dealerAccountId       : this._selectedDealerAccountId,
                    dealerName            : this._selectedDealerName,
                    serviceTerritoryId    : this._selectedServiceTerritoryId,
                    serviceResourceId     : this._selectedServiceResourceId,
                    serviceResourceName   : this._selectedServiceResourceName,
                    selectedSlotLabel     : this._selectedSlotLabel,
                    selectedSlotStartHour : this._selectedSlotStart,
                    selectedSlotEndHour   : this._selectedSlotEnd
                }
            }));
        })
        .catch(error => {
            this.isDisabled = false;
            console.error('dealerSlotPicker: error saving selection', error);
        });
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get hasSelection() {
        return this._selectedDealerName && this._selectedSlotLabel;
    }

    get selectedDealerName() { return this._selectedDealerName; }
    get selectedSlotLabel()  { return this._selectedSlotLabel; }

    get submitLabel() {
        return this.isDisabled ? 'Confirmed ✓' : 'Confirm Selection';
    }

    get submitDisabled() {
        return this.isDisabled || !this.hasSelection;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _toISO(date) {
        const y  = date.getFullYear();
        const m  = String(date.getMonth() + 1).padStart(2, '0');
        const d  = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    _clearSelection() {
        this._selectedDealerId            = null;
        this._selectedDealerName          = null;
        this._selectedDealerAccountId     = null;
        this._selectedServiceTerritoryId  = null;
        this._selectedServiceResourceId   = null;
        this._selectedServiceResourceName = null;
        this._selectedSlotLabel           = null;
        this._selectedSlotStart           = null;
        this._selectedSlotEnd             = null;
        this.isDisabled                   = false;
    }
}