import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getScholarLead from '@salesforce/apex/CplHomeIntakePipelineController.getScholarLead';

// each of the status leads to a specifc filter
const STATUS_META = {
    'New': { cssClass: 'stat stat-new', objectApiName: 'Lead', filterName: 'CPL_Lead_New' },
    'In Review': { cssClass: 'stat stat-review', objectApiName: 'Lead', filterName: 'CPL_Lead_In_Intake_Review' },
    'Contacted': { cssClass: 'stat stat-contacted', objectApiName: 'Lead', filterName: 'CPL_Lead_Contacted' },
    'Qualified': { cssClass: 'stat stat-qualified', objectApiName: 'Lead', filterName: 'CPL_Lead_Qualified' },
    'Unqualified': { cssClass: 'stat stat-unqualified', objectApiName: 'Lead', filterName: 'CPL_Lead_Unqualified' },
};

export default class CplHomeIntakePipeline extends NavigationMixin(LightningElement) {
    counts;
    error;

    @wire(getScholarLead)
    wiredPipeline({ data, error }) {
        if (data) {
            this.counts = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.counts = undefined;
        }
    }

    get stats() {
        return this.counts ? this.counts.map((c) => {
            const meta = STATUS_META[c.status] || { cssClass: 'stat', objectApiName: 'Lead', filterName: null };
            return {
                ...c,
                cssClass: meta.cssClass,
                objectApiName: meta.objectApiName,
                filterName: meta.filterName
            };
        }) : [];
    }

    get errorMessage() {
        if (!this.error) return null;
        return (this.error.body && this.error.body.message) || 'Could not load pipeline.';
    }

    handleStatClick(event) {
        const filterName = event.currentTarget.dataset.filter;
        const objectApiName = event.currentTarget.dataset.object;
        if (!filterName || !objectApiName) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName,
                actionName: 'list'
            },
            state: { filterName }
        });
    }
}
