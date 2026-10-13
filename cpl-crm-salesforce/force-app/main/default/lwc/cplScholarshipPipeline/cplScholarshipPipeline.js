import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPipeline from '@salesforce/apex/ScholarApplicationPipelineController.getPipeline';
export default class CplScholarshipPipeline extends NavigationMixin(LightningElement) {
    result;
    refreshing = false;
    @wire(getPipeline) wiredPipeline(result) { this.result = result; }
    get tiles() { return this.result?.data || []; }
    get error() { return this.result?.error ? 'Unable to load the pipeline. Check application and field access.' : null; }
    async refresh() {
        this.refreshing = true;
        try { await refreshApex(this.result); } finally { this.refreshing = false; }
    }
    openList(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Prospect_Scholar_Application__c', actionName: 'list' },
            state: { filterName: event.currentTarget.dataset.filter }
        });
    }
}
