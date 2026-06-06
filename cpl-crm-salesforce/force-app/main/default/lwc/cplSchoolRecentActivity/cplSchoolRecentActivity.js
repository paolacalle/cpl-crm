import { LightningElement, api, wire } from 'lwc';
import getActivity from '@salesforce/apex/CplSchoolRecentActivityController.getActivity';

export default class CplSchoolRecentActivity extends LightningElement {
    @api recordId;
    activity;
    error;

    @wire(getActivity, { schoolId: '$recordId' })
    wiredActivity({ data, error }) {
        if (data) {
            this.activity = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.activity = undefined;
        }
    }

    get recentLeads() {
        return this.activity ? this.activity.recentLeads.map((l) => ({
            ...l,
            url: `/lightning/r/Lead/${l.id}/view`,
            createdLabel: this.formatDate(l.createdDate)
        })) : [];
    }

    get recentApps() {
        return this.activity ? this.activity.recentApps.map((a) => ({
            ...a,
            url: `/lightning/r/Prospect_Scholar_Application__c/${a.id}/view`,
            createdLabel: this.formatDate(a.createdDate)
        })) : [];
    }

    get hasLeads() {
        return this.recentLeads.length > 0;
    }

    get hasApps() {
        return this.recentApps.length > 0;
    }

    get errorMessage() {
        if (!this.error) return null;
        return (this.error.body && this.error.body.message) || 'Could not load recent activity.';
    }

    formatDate(iso) {
        if (!iso) return '';
        return new Date(iso).toLocaleDateString();
    }
}
