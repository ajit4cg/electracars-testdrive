import { LightningElement, api, track } from 'lwc';
import bookTestDrive from '@salesforce/apex/TestDriveBookingController.bookTestDrive';
import getVehicleModels from '@salesforce/apex/TestDriveBookingController.getVehicleModels';
import getCustomerProfile from '@salesforce/apex/CustomerInsightController.getCustomerProfile';
import ELECTRA_LOGO from '@salesforce/resourceUrl/electra_logo';

export default class TestDriveBooking extends LightningElement {

    logoUrl = ELECTRA_LOGO;
    userInfoListenerRegistered = false;
    userInfoListener = null;

    @api heroTitle = 'Experience the Future';
    @api heroSubtitle = 'Book your test drive in under 60 seconds';

    @track currentStep = 1;
    @track vehicleModels = [];
    @track selectedVehicle = null;
    @track selectedVehicleName = '';
    @track bookingConfirmed = false;
    @track confirmedBooking = {};
    @track isSubmitting = false;
    @track errorMessage = '';
    @track personalization = null;

    @track formData = {
        firstName: '',
        lastName: '',
        email: '',
        phone: '',
        vehicleModel: '',
        preferredDate: '',
        preferredTime: '',
        zipCode: '',
        preferredChannel: 'WhatsApp'
    };

    @track channelOptions = [
        { value: 'WhatsApp', label: 'WhatsApp', icon: '💬', checked: true,  cssClass: 'channel-option selected' },
        { value: 'SMS',      label: 'SMS',       icon: '📱', checked: false, cssClass: 'channel-option' },
        { value: 'Email',    label: 'Email',     icon: '📧', checked: false, cssClass: 'channel-option' }
    ];

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this.registerUserInfoListener();
        this.loadVehicleModels();
        this.loadPersonalization();
        this.hydrateFromCapturedContext();
    }

    disconnectedCallback() {
        if (this.userInfoListenerRegistered && this.userInfoListener) {
            window.removeEventListener('userInfo', this.userInfoListener);
            this.userInfoListenerRegistered = false;
        }
    }

    loadVehicleModels() {
        getVehicleModels()
            .then(data => {
                // Map static resource names to public car images
                const images = {
                    'Electra Apex':    'https://images.unsplash.com/photo-1617788138017-80ad40651399?w=400&q=80',
                    'Electra Volt':    'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=400&q=80',
                    'Electra Storm':   'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?w=400&q=80',
                    'Electra Breeze':  'https://images.unsplash.com/photo-1502877338535-766e1452684a?w=400&q=80',
                    'Electra Phantom': 'https://images.unsplash.com/photo-1555215695-3004980ad54e?w=400&q=80',
                    'Electra Nova':    'https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=400&q=80'
                };
                this.vehicleModels = data.map(v => ({
                    ...v,
                    imageUrl: images[v.name] || 'https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=400&q=80',
                    isRecommended: false,
                    selected: false,
                    cssClass: 'vehicle-card'
                }));
                // Add 2 extra premium models
                this.vehicleModels = [
                    ...this.vehicleModels,
                    { id: '5', name: 'Electra Phantom', year: '2025', price: 89000, imageUrl: images['Electra Phantom'], isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '6', name: 'Electra Nova',    year: '2025', price: 72000, imageUrl: images['Electra Nova'],    isRecommended: false, selected: false, cssClass: 'vehicle-card' }
                ];
                this.applyRecommendationToVehicles();
            })
            .catch(() => {
                this.vehicleModels = [
                    { id: '1', name: 'Electra Apex',    year: '2025', price: 45000, imageUrl: 'https://images.unsplash.com/photo-1617788138017-80ad40651399?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '2', name: 'Electra Volt',    year: '2025', price: 38000, imageUrl: 'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '3', name: 'Electra Storm',   year: '2025', price: 62000, imageUrl: 'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '4', name: 'Electra Breeze',  year: '2025', price: 32000, imageUrl: 'https://images.unsplash.com/photo-1502877338535-766e1452684a?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '5', name: 'Electra Phantom', year: '2025', price: 89000, imageUrl: 'https://images.unsplash.com/photo-1555215695-3004980ad54e?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' },
                    { id: '6', name: 'Electra Nova',    year: '2025', price: 72000, imageUrl: 'https://images.unsplash.com/photo-1606664515524-ed2f786a0bd6?w=400&q=80', isRecommended: false, selected: false, cssClass: 'vehicle-card' }
                ];
                this.applyRecommendationToVehicles();
            });
    }

    loadPersonalization() {
        const email = sessionStorage.getItem('electra_visitor_email');
        if (!email) {
            return;
        }

        this.loadProfileByEmail(email);
    }

    hydrateFromCapturedContext() {
        const detail = this.normalizeUserInfoDetail(window.capturedVars);
        if (!detail.email && !detail.firstName && !detail.phone && !detail.zipCode && !detail.recommendedVehicle) {
            return;
        }

        this.formData = {
            ...this.formData,
            firstName: this.formData.firstName || detail.firstName || '',
            lastName:  this.formData.lastName  || detail.lastName  || '',
            email:     this.formData.email     || detail.email     || '',
            zipCode:   this.formData.zipCode   || detail.zipCode   || ''
        };

        if (detail.email) {
            sessionStorage.setItem('electra_visitor_email', detail.email);
            this.loadProfileByEmail(detail.email, detail);
            return;
        }

        this.applyFallbackPersonalization(detail);
    }

    registerUserInfoListener() {
        if (this.userInfoListenerRegistered) {
            return;
        }

        this.userInfoListener = (event) => {
            const detail = this.normalizeUserInfoDetail(event.detail);
            if (!detail.email) {
                return;
            }

            // Pre-fill identity fields only — never pre-fill phone (user must type it)
            this.formData = {
                ...this.formData,
                firstName: this.formData.firstName || detail.firstName || '',
                lastName:  this.formData.lastName  || detail.lastName  || '',
                email:     this.formData.email     || detail.email     || '',
                zipCode:   this.formData.zipCode   || detail.zipCode   || ''
            };

            sessionStorage.setItem('electra_visitor_email', detail.email);
            this.loadProfileByEmail(detail.email, detail);
        };

        window.addEventListener('userInfo', this.userInfoListener);
        this.userInfoListenerRegistered = true;
    }

    normalizeUserInfoDetail(detail) {
        const d = detail || {};
        return {
            firstName: d.firstName || d.FirstName || d.fname || d.First_Name || '',
            lastName: d.lastName || d.LastName || d.lname || d.Last_Name || '',
            email: d.email || d.Email || '',
            phone: d.phone || d.Phone || d.mobile || '',
            zipCode: d.zip || d.Zip || d.zipCode || '',
            preferredChannel: d.preferredChannel || d.channel || 'WhatsApp',
            recommendedVehicle: d.preferredModel || d.preferredVehicle || d.vehicleModel || d.Vehicle_Model || '',
            city: d.city || d.City || ''
        };
    }

    loadProfileByEmail(email, fallbackDetail = null) {
        getCustomerProfile({ email })
            .then(profile => {
                const resolvedProfile = this.mergeProfileWithFallback(profile, fallbackDetail);
                this.applyResolvedPersonalization(resolvedProfile);
            })
            .catch(() => {
                if (fallbackDetail) {
                    this.applyFallbackPersonalization(fallbackDetail);
                } else {
                    this.personalization = null;
                }
            });
    }

    mergeProfileWithFallback(profile, fallbackDetail) {
        if (!fallbackDetail) {
            return profile;
        }

        return {
            ...profile,
            isKnown: profile?.isKnown || !!fallbackDetail.email,
            firstName: profile?.firstName || fallbackDetail.firstName,
            lastName: profile?.lastName || fallbackDetail.lastName,
            email: profile?.email || fallbackDetail.email,
            phone: profile?.phone || fallbackDetail.phone,
            preferredZipCode: profile?.preferredZipCode || fallbackDetail.zipCode,
            preferredChannel: profile?.preferredChannel || fallbackDetail.preferredChannel,
            recommendedVehicle: profile?.recommendedVehicle || fallbackDetail.recommendedVehicle,
            recommendationReason: profile?.recommendationReason || 'Based on your saved customer context and recent Electra interest.',
            segmentCode: profile?.segmentCode || 'KNOWN_CUSTOMER',
            segmentLabel: profile?.segmentLabel || 'Returning visitor',
            journeyStage: profile?.journeyStage || 'Consider',
            profileSource: profile?.profileSource || 'Salesforce CRM',
            nudgeMessage: profile?.nudgeMessage || 'Welcome back. We saved your preferences so you can book faster.'
        };
    }

    applyFallbackPersonalization(detail) {
        this.applyResolvedPersonalization({
            isKnown: true,
            firstName: detail.firstName,
            lastName: detail.lastName,
            email: detail.email,
            phone: detail.phone,
            preferredZipCode: detail.zipCode,
            preferredChannel: detail.preferredChannel,
            recommendedVehicle: detail.recommendedVehicle || 'Electra Breeze',
            recommendationReason: detail.recommendedVehicle
                ? 'Based on your saved customer context and recent Electra interest.'
                : 'Based on your saved customer context, we picked a model to get you started faster.',
            segmentCode: 'KNOWN_CUSTOMER',
            segmentLabel: 'Returning visitor',
            journeyStage: 'Consider',
            profileSource: 'Salesforce CRM',
            nudgeMessage: 'Welcome back. We saved your preferences so you can book faster.'
        });
    }

    applyResolvedPersonalization(profile) {
        this.personalization = profile;
        // Pre-fill identity fields only — never pre-fill phone (user must type it)
        this.formData = {
            ...this.formData,
            email:            this.formData.email            || profile.email            || '',
            firstName:        this.formData.firstName        || profile.firstName        || '',
            lastName:         this.formData.lastName         || profile.lastName         || '',
            zipCode:          this.formData.zipCode          || profile.preferredZipCode || '',
            preferredChannel: this.formData.preferredChannel || profile.preferredChannel || 'WhatsApp'
        };
        this.channelOptions = this.channelOptions.map(channel => ({
            ...channel,
            checked: channel.value === this.formData.preferredChannel,
            cssClass: channel.value === this.formData.preferredChannel ? 'channel-option selected' : 'channel-option'
        }));
        this.applyRecommendationToVehicles();
    }

    // ─── Step navigation ───────────────────────────────────────────────────────

    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get noVehicleSelected() { return !this.selectedVehicle; }
    get step2Invalid() { return !this.isStep2Valid; }
    get hasPersonalization() { return this.personalization && this.personalization.isKnown; }
    get personalizationTitle() {
        if (!this.hasPersonalization) {
            return '';
        }

        const p = this.personalization;
        if (p.segmentCode === 'ACTIVE_BOOKING') {
            return `Resume ${p.lastVehicle || 'your booking'}`;
        }
        if (p.segmentCode === 'LOYAL_RETURNER') {
            return `Welcome back${p.firstName ? ', ' + p.firstName : ''} — your next Electra awaits`;
        }
        if (p.segmentCode === 'HIGH_INTENT') {
            return `Pick up where you left off${p.firstName ? ', ' + p.firstName : ''}`;
        }
        return `Good to see you again${p.firstName ? ', ' + p.firstName : ''}`;
    }
    get personalizationMeta() {
        if (!this.hasPersonalization) {
            return '';
        }

        return `${this.personalization.profileSource || 'Salesforce CRM'}`;
    }

    get steps() {
        return [
            { id: 1, number: '1', label: 'Vehicle',  cssClass: this.stepClass(1) },
            { id: 2, number: '2', label: 'Schedule', cssClass: this.stepClass(2) },
            { id: 3, number: '3', label: 'Details',  cssClass: this.stepClass(3) }
        ];
    }

    stepClass(n) {
        if (n < this.currentStep)  return 'step completed';
        if (n === this.currentStep) return 'step active';
        return 'step';
    }

    get minDate() {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        return tomorrow.toISOString().split('T')[0];
    }

    get isStep2Valid() {
        return this.formData.preferredDate && this.formData.preferredTime && this.formData.zipCode.length >= 5;
    }

    goToStep1() { this.currentStep = 1; }
    goToStep2() { this.currentStep = 2; }
    goToStep3() { if (this.isStep2Valid) this.currentStep = 3; }

    // ─── Vehicle selection ─────────────────────────────────────────────────────

    selectVehicle(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.selectedVehicle = id;
        this.selectedVehicleName = name;
        this.formData = { ...this.formData, vehicleModel: name };
        this.refreshVehicleCards();
    }

    applyRecommendationToVehicles() {
        if (!this.vehicleModels.length) {
            return;
        }

        const recommendedVehicle = this.personalization?.recommendedVehicle;
        let selectedVehicleId = this.selectedVehicle;
        let selectedVehicleName = this.selectedVehicleName;

        if (!selectedVehicleId && recommendedVehicle) {
            const match = this.vehicleModels.find(vehicle => vehicle.name === recommendedVehicle);
            if (match) {
                selectedVehicleId = match.id;
                selectedVehicleName = match.name;
                this.formData = { ...this.formData, vehicleModel: match.name };
            }
        }

        this.selectedVehicle = selectedVehicleId;
        this.selectedVehicleName = selectedVehicleName;
        this.refreshVehicleCards();
    }

    refreshVehicleCards() {
        const recommendedVehicle = this.personalization?.recommendedVehicle;
        this.vehicleModels = this.vehicleModels.map(vehicle => {
            const isSelected = vehicle.id === this.selectedVehicle;
            const isRecommended = vehicle.name === recommendedVehicle;
            let cssClass = 'vehicle-card';

            if (isSelected) {
                cssClass += ' selected';
            } else if (isRecommended) {
                cssClass += ' recommended';
            }

            return {
                ...vehicle,
                selected: isSelected,
                isRecommended,
                cssClass
            };
        });

        // Sort: recommended first, then rest in original order
        this.vehicleModels = [
            ...this.vehicleModels.filter(v => v.isRecommended),
            ...this.vehicleModels.filter(v => !v.isRecommended)
        ];
    }

    // ─── Form handlers ─────────────────────────────────────────────────────────

    handleInputChange(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.value };
    }

    handleDateClick(event) {
        try {
            event.target.showPicker();
        } catch(e) {
            // showPicker not supported in all browsers — fallback is manual entry
        }
    }

    handleChannelChange(event) {
        const val = event.target.value;
        this.formData = { ...this.formData, preferredChannel: val };
        this.channelOptions = this.channelOptions.map(c => ({
            ...c,
            checked: c.value === val,
            cssClass: c.value === val ? 'channel-option selected' : 'channel-option'
        }));
    }

    // ─── Submission ────────────────────────────────────────────────────────────

    submitBooking() {
        if (!this.validateStep3()) return;
        this.isSubmitting = true;
        this.errorMessage = '';

        bookTestDrive({
            payloadJson: JSON.stringify({
                firstName: this.formData.firstName,
                lastName: this.formData.lastName,
                email: this.formData.email,
                phone: this.formData.phone,
                vehicleModel: this.formData.vehicleModel,
                preferredDate: this.formData.preferredDate,
                preferredTime: this.formData.preferredTime,
                zipCode: this.formData.zipCode,
                preferredChannel: this.formData.preferredChannel
            })
        })
        .then(result => {
            if (result.success) {
                this.confirmedBooking = result;
                this.bookingConfirmed = true;
                // Store email for personalized nudge on return visits (Data Cloud simulation)
                sessionStorage.setItem('electra_visitor_email', this.formData.email);
            } else {
                this.errorMessage = result.errorMessage || 'Booking failed. Please try again.';
            }
        })
        .catch(err => {
            this.errorMessage = err.body?.message || 'An unexpected error occurred.';
        })
        .finally(() => {
            this.isSubmitting = false;
        });
    }

    validateStep3() {
        const { firstName, lastName, email } = this.formData;
        if (!firstName || !lastName || !email) {
            this.errorMessage = 'Please fill in all required fields.';
            return false;
        }
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }
        return true;
    }

    // ─── Agentforce chat launcher ──────────────────────────────────────────────

    launchAgentChat() {
        const isExpSite = window.location.hostname.includes('my.site.com');
        if (isExpSite && window.embeddedservice_bootstrap) {
            // On Experience Site - open chat directly
            try {
                window.embeddedservice_bootstrap.utilAPI.launchChat();
            } catch(e) {
                console.log('Chat already launching');
            }
        } else {
            // On Lightning App Page - navigate to Experience Site same tab
            window.location.href = 'https://orgfarm-37643d5221.my.site.com/electracars';
        }
    }
}