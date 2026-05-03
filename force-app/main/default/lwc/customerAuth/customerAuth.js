import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import getMyBookings from '@salesforce/apex/CustomerPortalController.getMyBookings';
import getCurrentUserName from '@salesforce/apex/CustomerPortalController.getCurrentUserName';
import loginCustomer from '@salesforce/apex/CustomerPortalController.loginCustomer';
import registerCustomer from '@salesforce/apex/CustomerPortalController.registerCustomer';

export default class CustomerAuth extends NavigationMixin(LightningElement) {

    @track showModal    = false;
    @track activeTab    = 'login';
    @track isLoading    = false;
    @track authError    = '';
    @track showBookings = false;
    @track myBookings   = [];

    @track loginEmail    = '';
    @track loginPassword = '';

    @track regData = {
        firstName: '', lastName: '', email: '', phone: '', password: ''
    };

    @track currentUserName = 'Customer';

    // ─── User state ────────────────────────────────────────────────────────────

    get isLoggedIn()   { return !isGuestUser; }
    get isGuestVisitor() { return isGuestUser; }
    get isLoginTab()   { return this.activeTab === 'login'; }
    get isRegisterTab(){ return this.activeTab === 'register'; }
    get hasBookings()  { return this.myBookings && this.myBookings.length > 0; }

    get loginTabClass()    { return this.activeTab === 'login'    ? 'tab active' : 'tab'; }
    get registerTabClass() { return this.activeTab === 'register' ? 'tab active' : 'tab'; }
    get modalOverlayClass() {
        return this.isGuestVisitor ? 'modal-overlay fullscreen-auth' : 'modal-overlay';
    }

    connectedCallback() {
        if (isGuestUser) {
            this.showModal = true;
            this.activeTab = 'login';
        } else {
            getCurrentUserName()
                .then(name => { this.currentUserName = name || 'Customer'; })
                .catch(() => {});
        }
    }

    // ─── Modal controls ────────────────────────────────────────────────────────

    openLoginModal()  { this.showModal = true; this.authError = ''; }
    closeModal()      { if (!isGuestUser) this.showModal = false; }
    stopPropagation(e){ e.stopPropagation(); }
    showLoginTab()    { this.activeTab = 'login';    this.authError = ''; }
    showRegisterTab() { this.activeTab = 'register'; this.authError = ''; }

    // ─── My Bookings ───────────────────────────────────────────────────────────

    toggleBookings() {
        this.showBookings = !this.showBookings;
        if (this.showBookings && this.myBookings.length === 0) {
            this.loadBookings();
        }
    }

    loadBookings() {
        getMyBookings()
            .then(data => {
                this.myBookings = data.map(b => ({
                    id:          b.Id,
                    ref:         b.Name,
                    vehicle:     b.VehicleModel__c,
                    date:        b.PreferredDate__c,
                    time:        b.PreferredTime__c,
                    status:      b.Status__c,
                    cssClass:    'booking-card',
                    statusClass: this.getStatusClass(b.Status__c)
                }));
            })
            .catch(err => console.error('Failed to load bookings:', err));
    }

    getStatusClass(status) {
        const map = { 'Confirmed': 'status confirmed', 'Pending': 'status pending', 'Completed': 'status completed', 'Cancelled': 'status cancelled' };
        return map[status] || 'status pending';
    }

    // ─── Login ─────────────────────────────────────────────────────────────────

    handleLoginEmailChange(e)    { this.loginEmail    = e.target.value; }
    handleLoginPasswordChange(e) { this.loginPassword = e.target.value; }

    handleLogin() {
        if (!this.loginEmail || !this.loginPassword) {
            this.authError = 'Please enter email and password.';
            return;
        }
        this.isLoading = true;
        this.authError = '';

        loginCustomer({ username: this.loginEmail, password: this.loginPassword })
            .then(result => {
                if (result.success && result.redirectUrl) {
                    window.location.href = result.redirectUrl;
                } else {
                    this.authError = result.errorMessage || 'Login failed.';
                    this.isLoading = false;
                }
            })
            .catch(err => {
                this.authError = err.body?.message || 'Login failed.';
                this.isLoading = false;
            });
    }

    // ─── Register ──────────────────────────────────────────────────────────────

    handleRegChange(e) {
        const field = e.target.dataset.field;
        this.regData = { ...this.regData, [field]: e.target.value };
    }

    handleRegister() {
        const { firstName, lastName, email, phone, password } = this.regData;
        if (!firstName || !lastName || !email || !password) {
            this.authError = 'Please fill in all required fields.';
            return;
        }
        if (password.length < 8) {
            this.authError = 'Password must be at least 8 characters.';
            return;
        }
        this.isLoading = true;
        this.authError = '';

        registerCustomer({ firstName, lastName, email, phone, password })
            .then(result => {
                if (result.success) {
                    // Auto-login after registration
                    this.loginEmail    = email;
                    this.loginPassword = password;
                    this.handleLogin();
                } else {
                    this.authError = result.errorMessage;
                    this.isLoading = false;
                }
            })
            .catch(err => {
                this.authError = err.body?.message || 'Registration failed.';
                this.isLoading = false;
            });
    }

    // ─── Logout ────────────────────────────────────────────────────────────────

    handleLogout() {
        window.location.href = '/electracars/secur/logout.jsp';
    }
}