import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendInitialContactEmail from '@salesforce/apex/LeadContactingCheckpointAction.sendInitialContactEmail';
import markInitialContactEmailSent from '@salesforce/apex/LeadContactingCheckpointAction.markInitialContactEmailSent';

export default class FlowLeadContactEmailSubmit extends LightningElement {
    @api recordId;
    @api initialContactEmailSent = false;
    @api emailSubmitted = false;

    _subject = 'Following up on your CPL Scholar Interest Form';
    _body = '';
    isSaving = false;

    @api
    get subject() {
        return this._subject;
    }

    set subject(value) {
        this._subject = value || '';
    }

    @api
    get body() {
        return this._body;
    }

    set body(value) {
        this._body = value || '';
    }

    get emailAlreadySent() {
        return this.initialContactEmailSent === true || this.initialContactEmailSent === 'true' || this.emailSubmitted;
    }

    handleSubjectChange(event) {
        this._subject = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('subject', this._subject));
    }

    handleBodyChange(event) {
        this._body = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('body', this._body));
    }

    async handleSendEmail() {
        if (!this.validateInputs()) {
            return;
        }

        await this.save(async () => {
            await sendInitialContactEmail({
                leadId: this.recordId,
                subject: this._subject,
                body: this._body
            });
            this.markSubmitted('Email sent');
        }, 'Could not send email');
    }

    async handleMarkSent() {
        await this.save(async () => {
            await markInitialContactEmailSent({ leadId: this.recordId });
            this.markSubmitted('Email marked sent');
        }, 'Could not mark email sent');
    }

    async save(callback, errorTitle) {
        if (!this.recordId) {
            this.showToast(errorTitle, 'Pass a Lead Id into this Flow component.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            await callback();
        } catch (error) {
            this.showToast(errorTitle, this.errorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateInputs() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-textarea')];
        return inputs.reduce((isValid, input) => {
            input.reportValidity();
            return isValid && input.checkValidity();
        }, true);
    }

    markSubmitted(title) {
        this.emailSubmitted = true;
        this.initialContactEmailSent = true;
        this.dispatchEvent(new FlowAttributeChangeEvent('emailSubmitted', true));
        this.dispatchEvent(new FlowAttributeChangeEvent('initialContactEmailSent', true));
        this.showToast(title, null, 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Try again.';
    }
}
