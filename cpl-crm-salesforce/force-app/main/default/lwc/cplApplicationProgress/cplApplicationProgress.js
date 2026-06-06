import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Application_Status__c';
import RESUME_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Resume_Received__c';
import ESSAY_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Essay_Received__c';
import COACH_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Coach_Professor_Recommendation_Received__c';
import INTERN_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Internship_Supervisor_Rec_Received__c';
import COMPLETE_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Materials_Complete__c';
import SENT_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Scholarship_Invite_Sent_Date__c';
import CONFIRMED_FIELD from '@salesforce/schema/Prospect_Scholar_Application__c.Scholarship_Invite_Confrimed_Date__c';

const FIELDS = [
    STATUS_FIELD, RESUME_FIELD, ESSAY_FIELD, COACH_FIELD, INTERN_FIELD,
    COMPLETE_FIELD, SENT_FIELD, CONFIRMED_FIELD
];

const STATUS_CLASS = {
    'Invite Sent': 'badge badge-pending',
    'Collecting Documents': 'badge badge-active',
    'In Review': 'badge badge-review',
    'Accepted': 'badge badge-success',
    'Waitlisted': 'badge badge-warning',
    'Rejected': 'badge badge-error',
    'Withdrawn': 'badge badge-neutral'
};

export default class CplApplicationProgress extends LightningElement {
    @api recordId;
    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        if (result.data) {
            this.record = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.record = undefined;
        }
    }

    get status() {
        return this.record ? getFieldValue(this.record, STATUS_FIELD) : null;
    }

    get statusBadgeClass() {
        return STATUS_CLASS[this.status] || 'badge';
    }

    get materialsComplete() {
        return this.record ? getFieldValue(this.record, COMPLETE_FIELD) : false;
    }

    get materials() {
        if (!this.record) return [];
        const items = [
            { key: 'resume', label: 'Resume', received: !!getFieldValue(this.record, RESUME_FIELD) },
            { key: 'essay', label: 'Essay', received: !!getFieldValue(this.record, ESSAY_FIELD) },
            { key: 'coach', label: 'Coach / Professor recommendation', received: !!getFieldValue(this.record, COACH_FIELD) },
            { key: 'intern', label: 'Internship supervisor recommendation', received: !!getFieldValue(this.record, INTERN_FIELD) }
        ];
        return items.map((item) => ({
            ...item,
            iconName: item.received ? 'utility:success' : 'utility:circle',
            cssClass: item.received ? 'material-item material-received' : 'material-item material-missing'
        }));
    }

    get materialsReceivedCount() {
        return this.materials.filter((m) => m.received).length;
    }

    get materialsLabel() {
        return `${this.materialsReceivedCount} of ${this.materials.length} received`;
    }

    get inviteSentLabel() {
        return this.formatDate(getFieldValue(this.record, SENT_FIELD));
    }

    get inviteConfirmedLabel() {
        return this.formatDate(getFieldValue(this.record, CONFIRMED_FIELD));
    }

    get hasSentDate() {
        return !!this.inviteSentLabel;
    }

    get hasConfirmedDate() {
        return !!this.inviteConfirmedLabel;
    }

    get hasAnyDate() {
        return this.hasSentDate || this.hasConfirmedDate;
    }

    get errorMessage() {
        if (!this.error) return null;
        return (this.error.body && this.error.body.message) || 'Could not load application progress.';
    }

    formatDate(iso) {
        if (!iso) return '';
        return new Date(iso).toLocaleDateString();
    }
}
