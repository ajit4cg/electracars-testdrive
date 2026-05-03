import { LightningElement, track, api } from 'lwc';
import getCustomerProfile from '@salesforce/apex/CustomerInsightController.getCustomerProfile';

const DEFAULT_NUDGE = 'Hi there! 👋 Book your Electra test drive in 30 seconds — just tell me which model you love.';

export default class AgentChatLauncher extends LightningElement {

    @api nudgeDelaySeconds = 15;
    @api embeddedServiceName = 'Drive_the_Dream';
    @api orgUrl = 'https://orgfarm-37643d5221.my.salesforce.com';

    @track showNudge = false;
    @track nudgeMessage = DEFAULT_NUDGE;
    @track nudgeType = 'NEW_VISITOR';

    _nudgeTimer = null;
    _scriptLoaded = false;
    _prechatPatched = false;
    _prechatPatchTimer = null;
    _boundUserInfoHandler = null;

    connectedCallback() {
        this.initializePrechatGlobals();
        this._boundUserInfoHandler = this.handleUserInfoEvent.bind(this);
        window.addEventListener('userInfo', this._boundUserInfoHandler);
        this.startPrechatPatchWatcher();

        if (!sessionStorage.getItem('electra_nudge_dismissed')) {
            this._nudgeTimer = setTimeout(() => {
                this.loadPersonalizedNudge();
            }, this.nudgeDelaySeconds * 1000);
        }
        this.loadBootstrapScript();
    }

    disconnectedCallback() {
        if (this._nudgeTimer) clearTimeout(this._nudgeTimer);
        if (this._prechatPatchTimer) clearInterval(this._prechatPatchTimer);
        if (this._boundUserInfoHandler) {
            window.removeEventListener('userInfo', this._boundUserInfoHandler);
        }
    }

    // ─── Personalized nudge (Data Cloud simulation via native SOQL) ────────────

    loadPersonalizedNudge() {
        const email = sessionStorage.getItem('electra_visitor_email');
        if (email) {
            getCustomerProfile({ email })
                .then(profile => {
                    this.updatePrechatGlobals({
                        Email: profile.email,
                        FirstName: profile.firstName,
                        LastName: profile.lastName,
                        Phone: profile.phone,
                        zip: profile.preferredZipCode,
                        City: profile.city,
                        preferredModel: profile.recommendedVehicle
                    });
                    this.nudgeMessage = profile.nudgeMessage;
                    this.nudgeType    = profile.nudgeType;
                    this.showNudge    = true;
                })
                .catch(() => {
                    this.nudgeMessage = DEFAULT_NUDGE;
                    this.showNudge    = true;
                });
        } else {
            this.nudgeMessage = DEFAULT_NUDGE;
            this.showNudge    = true;
        }
    }

    // ─── ESW bootstrap ─────────────────────────────────────────────────────────

    loadBootstrapScript() {
        if (this._scriptLoaded || document.querySelector('script[data-esw]')) {
            this._scriptLoaded = true;
            return;
        }
        const script = document.createElement('script');
        script.src = 'https://orgfarm-37643d5221.my.site.com/ESWSampleMessaging1776336637980/assets/js/bootstrap.min.js';
        script.setAttribute('data-esw', 'true');
        script.addEventListener('load', () => {
            this._scriptLoaded = true;
            this.initEmbeddedMessaging();
        });
        document.head.appendChild(script);
    }

    initEmbeddedMessaging() {
        try {
            embeddedservice_bootstrap.settings.language = 'en_US';
            embeddedservice_bootstrap.init(
                '00Dbm00000fmLKH',
                'Drive_the_Dream',
                'https://orgfarm-37643d5221.my.site.com/ESWSampleMessaging1776336637980',
                { scrt2URL: 'https://orgfarm-37643d5221.my.salesforce-scrt.com' }
            );
        } catch (err) {
            console.error('Error loading Embedded Messaging: ', err);
        }
    }

    initializePrechatGlobals() {
        const defaults = {
            FirstName: '',
            LastName: '',
            Email: '',
            Phone: '',
            City: '',
            zip: '',
            latitude: '',
            longitude: '',
            preferredModel: ''
        };

        const existing = window.capturedVars && typeof window.capturedVars === 'object'
            ? window.capturedVars
            : {};

        window.capturedVars = { ...defaults, ...existing };
        this.syncLegacyGlobals(window.capturedVars);
    }

    handleUserInfoEvent(event) {
        this.updatePrechatGlobals(event?.detail || {});
    }

    updatePrechatGlobals(detail) {
        const current = window.capturedVars && typeof window.capturedVars === 'object'
            ? window.capturedVars
            : {};

        const merged = {
            ...current,
            FirstName: detail.FirstName ?? detail.First_Name ?? detail.fname ?? detail.firstName ?? current.FirstName ?? '',
            LastName: detail.LastName ?? detail.lastName ?? detail.lname ?? current.LastName ?? '',
            Email: detail.Email ?? detail.email ?? current.Email ?? '',
            Phone: detail.Phone ?? detail.phone ?? current.Phone ?? '',
            City: detail.City ?? detail.city ?? current.City ?? '',
            zip: detail.zip ?? detail.Zip ?? current.zip ?? '',
            latitude: detail.latitude ?? detail.lat ?? current.latitude ?? '',
            longitude: detail.longitude ?? detail.lon ?? current.longitude ?? '',
            preferredModel: detail.preferredModel ?? detail.Model ?? detail.Vehicle_Model ?? current.preferredModel ?? ''
        };

        window.capturedVars = merged;
        this.syncLegacyGlobals(merged);
    }

    syncLegacyGlobals(vars) {
        window.firstName = vars.FirstName || '';
        window.lastName = vars.LastName || '';
        window.email = vars.Email || '';
        window.phone = vars.Phone || '';
        window.city = vars.City || '';
        window.zip = vars.zip || '';
        window.latitude = vars.latitude ?? '';
        window.longitude = vars.longitude ?? '';
        window.preferredModel = vars.preferredModel || '';
    }

    startPrechatPatchWatcher() {
        if (this._prechatPatchTimer) {
            clearInterval(this._prechatPatchTimer);
        }

        this._prechatPatchTimer = setInterval(() => {
            const prechatApi = window.embeddedservice_bootstrap?.prechatAPI;
            if (!prechatApi || this._prechatPatched) {
                return;
            }

            const original = prechatApi.setHiddenPrechatFields?.bind(prechatApi);
            if (!original) {
                return;
            }

            prechatApi.setHiddenPrechatFields = (fields = {}) => {
                const safeFields = this.buildSafeHiddenPrechatFields(fields);
                return original(safeFields);
            };

            this._prechatPatched = true;
        }, 300);
    }

    buildSafeHiddenPrechatFields(fields) {
        const captured = window.capturedVars && typeof window.capturedVars === 'object'
            ? window.capturedVars
            : {};
        const incoming = fields && typeof fields === 'object' ? fields : {};

        return {
            latitude: String(
                incoming.latitude ??
                captured.latitude ??
                ''
            ),
            longitude: String(
                incoming.longitude ??
                captured.longitude ??
                ''
            ),
            zip: String(
                incoming.zip ??
                incoming.Zip ??
                captured.zip ??
                ''
            )
        };
    }

    openChat() {
        this.showNudge = false;
        try {
            if (window.embeddedservice_bootstrap) {
                window.embeddedservice_bootstrap.utilAPI.launchChat();
            }
        } catch(e) {
            console.log('Chat already launching');
        }
    }

    dismissNudge() {
        this.showNudge = false;
        sessionStorage.setItem('electra_nudge_dismissed', 'true');
    }
}