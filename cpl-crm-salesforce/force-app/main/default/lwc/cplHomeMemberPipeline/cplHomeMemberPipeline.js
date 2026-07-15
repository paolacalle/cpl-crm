import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import getPipeline from '@salesforce/apex/CplHomeMemberPipelineController.getPipeline';

const OBJECT_NAME = 'Account';
const BASE_CLASS = 'stat stat';

export const STATUS_META = Object.freeze({
    Athlete: { 
        cssClass: `${BASE_CLASS}-athlete`, 
        objectApiName: OBJECT_NAME, 
        filterName: 'CPL_Athlete', 
        toolTip: 'Students who we actively mentor.' 
    },
    Applicant: { 
        cssClass: `${BASE_CLASS}-applicant`, 
        objectApiName: OBJECT_NAME, 
        filterName: 'CPL_Applicant', 
        toolTip: 'Students who we actively mentor & have an active scholarship application.' 
    },
    Scholar: { 
        cssClass: `${BASE_CLASS}-scholar`, 
        objectApiName: OBJECT_NAME, 
        filterName: 'CPL_Scholar', 
        toolTip: 'Students who we actively mentor & have been granted scholarship.' 
    },
    'Scholar Alumni': { 
        cssClass: `${BASE_CLASS}-scholar-alumni`, 
        objectApiName: OBJECT_NAME, 
        filterName: 'CPL_Scholar_Alumni', 
        toolTip: 'Graduated & we granted scholarship.' 
    },
    Alumni: { 
        cssClass: `${BASE_CLASS}-alumni`, 
        objectApiName: OBJECT_NAME, 
        filterName: 'CPL_Alumni', 
        toolTip: 'Graduated & we did not grant a scholarship.' 
    }
});

export default class CplHomeMemberPipeline extends NavigationMixin(LightningElement) {
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
            const meta = STATUS_META[c.status] || { cssClass: 'stat', objectApiName: OBJECT_NAME, filterName: null };
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