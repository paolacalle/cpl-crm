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
    'In Intake Review': { 
        cssClass: 'stat stat-review', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_In_Intake_Review', 
        toolTip: 'Leads currently undergoing initial review.' 
    },
    'Contacted': { 
        cssClass: 'stat stat-contacted', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_Contacted', 
        toolTip: 'Outreach has been made to the student.' 
    },
    'Qualified': { 
        cssClass: 'stat stat-qualified', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_Qualified', 
        toolTip: 'Leads we intend to advance into mentorship.' 
    },
    'Unqualified': { 
        cssClass: 'stat stat-unqualified', 
        objectApiName: 'Lead', 
        filterName: 'CPL_Lead_Unqualified', 
        toolTip: 'Leads that do not meet standard criteria.' 
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