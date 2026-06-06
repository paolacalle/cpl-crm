import { LightningElement, api, wire } from 'lwc';
import getResume from '@salesforce/apex/LeadResumePreviewController.getResume';

export default class LeadResumePreview extends LightningElement {
    @api recordId;
    resume;

    @wire(getResume, { leadId: '$recordId' })
    wiredResume({ data }) {
        if (data) {
            this.resume = data;
        }
    }

    get hasFile() {
        return !!(this.resume && this.resume.contentDocumentId);
    }

    get hasUrl() {
        return !!(this.resume && this.resume.resumeUrl);
    }

    get hasResume() {
        return this.hasFile || this.hasUrl;
    }

    get fileLabel() {
        return this.resume && this.resume.title ? this.resume.title : 'resume';
    }

    get previewHref() {
        return this.hasFile
            ? `/lightning/r/ContentDocument/${this.resume.contentDocumentId}/view`
            : null;
    }
}
