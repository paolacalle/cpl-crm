import { LightningElement, api, wire } from 'lwc';
import getSummary from '@salesforce/apex/CplSchoolMemberSummaryController.getSummary';

export default class CplSchoolMemberSummary extends LightningElement {
    @api recordId;
    summary;
    error;

    @wire(getSummary, { schoolId: '$recordId' })
    wiredSummary({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.summary = undefined;
        }
    }

    get hasMembers() {
        return this.summary && this.summary.total > 0;
    }

    get total() {
        return this.summary ? this.summary.total : 0;
    }

    get totalLabel() {
        const n = this.total;
        return n === 1 ? '1 CPL Member' : `${n} CPL Members`;
    }

    get byLifecycle() {
        return this.summary ? this.summary.byLifecycle : [];
    }

    get bySport() {
        return this.summary ? this.summary.bySport : [];
    }

    get byCollegeYear() {
        return this.summary ? this.summary.byCollegeYear : [];
    }

    get errorMessage() {
        if (!this.error) return null;
        return (this.error.body && this.error.body.message) || 'Could not load member summary.';
    }
}