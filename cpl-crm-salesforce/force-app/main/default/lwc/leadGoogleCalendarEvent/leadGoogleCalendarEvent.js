import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Lead.Name';
import EMAIL_FIELD from '@salesforce/schema/Lead.Email';

export default class LeadGoogleCalendarEvent extends NavigationMixin(
    LightningElement
) {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [NAME_FIELD, EMAIL_FIELD] }) lead;

    get leadName() {
        return this.lead?.data ? getFieldValue(this.lead.data, NAME_FIELD) : null;
    }

    get leadEmail() {
        return this.lead?.data ? getFieldValue(this.lead.data, EMAIL_FIELD) : null;
    }

    get hasLeadRecord() {
        return !!this.lead?.data;
    }

    async handleSchedule() {
        try {
            if (!this.recordId) {
                throw new Error('Lead record ID is missing.');
            }

            // Generate the Salesforce record URL through the supported
            // Lightning navigation service.
            const recordUrl = await this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });

            const absoluteRecordUrl = `${window.location.origin}${recordUrl}`;

            const params = new URLSearchParams({
                action: 'TEMPLATE',
                text: `CPL — ${this.leadName || 'Lead'}`,
                details: `Salesforce Lead: ${absoluteRecordUrl}`
            });

            if (this.leadEmail) {
                params.set('add', this.leadEmail);
            }

            window.open(
                `https://calendar.google.com/calendar/render?${params.toString()}`,
                '_blank',
                'noopener,noreferrer'
            );
        } catch (error) {
            console.error('Unable to open Google Calendar:', error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to schedule call',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'An unexpected error occurred.',
                    variant: 'error'
                })
            );
        }
    }
}
