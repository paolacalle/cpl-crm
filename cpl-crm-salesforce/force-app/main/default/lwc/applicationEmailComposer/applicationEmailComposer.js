import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendEmail from '@salesforce/apex/ApplicationEmailComposerController.sendEmail';
import markSent from '@salesforce/apex/ApplicationEmailComposerController.markSent';

export default class ApplicationEmailComposer extends LightningElement {
    @api applicationId;
    @api emailType;
    @api subjectLabel = 'Email subject';
    @api bodyLabel = 'Email message';
    @api alreadySent = false;
    @api emailSubmitted = false;
    @api materialsUrl;

    _subject = '';
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

    get emailAlreadySubmitted() {
        return this.alreadySent === true || this.alreadySent === 'true' || this.emailSubmitted;
    }

    get submittedLabel() {
        return this.emailType === 'Invite'
            ? 'Scholarship invite email has been sent or marked sent.'
            : 'This email has been sent or marked sent.';
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
            await sendEmail({
                applicationId: this.applicationId,
                emailType: this.emailType,
                subject: this._subject,
                body: this._body,
                materialsUrl: this.materialsUrl
            });
            this.markSubmitted('Email sent');
        }, 'Could not send email');
    }

    async handleMarkSent() {
        await this.save(async () => {
            await markSent({
                applicationId: this.applicationId,
                emailType: this.emailType,
                materialsUrl: this.materialsUrl
            });
            this.markSubmitted('Email marked sent');
        }, 'Could not mark email sent');
    }

    async save(callback, errorTitle) {
        if (!this.applicationId) {
            this.showToast(errorTitle, 'Pass an Application Id into this Flow component.', 'error');
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
        this.dispatchEvent(new FlowAttributeChangeEvent('emailSubmitted', true));
        this.showToast(title, null, 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Try again.';
    }
}
