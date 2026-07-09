import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMemberPerson from '@salesforce/apex/CplHomeIntakePipelineController.getMemberPerson';

const ACCOUNT_OBJECT = 'Account';

// Each lifecycle opens its matching CPL Members list view.
const STATUS_META = {
    'Athlete': { cssClass: 'stat stat-new', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Athlete' },
    'Prospect': { cssClass: 'stat stat-review', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Prospect' },
    'Applicant': { cssClass: 'stat stat-contacted', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Applicant' },
    'Scholar': { cssClass: 'stat stat-qualified', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Scholar' },
    'Scholar Alumni': { cssClass: 'stat stat-converted', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Scholar_Alumni' },
    'Alumni': { cssClass: 'stat stat-unqualified', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Alumni' },
    'Inactive': { cssClass: 'stat stat-unqualified', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members_Inactive' }
};

export default class CplHomeMemberPipeline extends NavigationMixin(LightningElement) {
    counts;
    error;

    @wire(getMemberPerson)
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
            const meta = STATUS_META[c.status] || { cssClass: 'stat', objectApiName: ACCOUNT_OBJECT, filterName: 'CPL_Members' };
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
