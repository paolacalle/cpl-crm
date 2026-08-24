import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getPipeline from '@salesforce/apex/CplHomeIntakePipelineController.getPipeline';

const STATUS_META = {
    'New': { 
        cssClass: 'stat stat-new', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_New', 
        toolTip: 'Freshly created leads awaiting initial review.' 
    },
    'Contacting': {
        cssClass: 'stat stat-contacting', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_Contacting',
        toolTip: 'Leads actively being contacted after application review.'
    },
    'Decision': {
        cssClass: 'stat stat-decision', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_Decision',
        toolTip: 'Leads ready for conversion or disqualification.'
    }
};

export default class CplHomeIntakePipeline extends NavigationMixin(LightningElement) {
    counts;
    error;
    isRefreshing = false;
    wiredResult;

    @wire(getPipeline)
    wiredPipeline(result) {
        this.wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.counts = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.counts = undefined;
        }
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.isRefreshing = false;
        }
    }

    get stats() {
        return this.counts ? this.counts.map((c) => {
            const meta = STATUS_META[c.status] || { cssClass: 'stat', objectApiName: 'Lead', filterName: null };
            return {
                ...c,
                cssClass: meta.cssClass,
                objectApiName: meta.objectApiName,
                filterName: meta.filterName,
                toolTip : meta.toolTip
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