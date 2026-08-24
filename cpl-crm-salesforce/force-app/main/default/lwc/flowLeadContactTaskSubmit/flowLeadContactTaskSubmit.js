import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createFollowUpTask from '@salesforce/apex/LeadContactingCheckpointAction.createFollowUpTask';

export default class FlowLeadContactTaskSubmit extends LightningElement {
    @api recordId;
    @api taskId;
    @api taskSubmitted = false;

    _subject = 'Follow up with lead';
    _dueDate;
    _notes = '';
    isSaving = false;

    @api
    get subject() {
        return this._subject;
    }

    set subject(value) {
        this._subject = value || '';
    }

    @api
    get dueDate() {
        return this._dueDate;
    }

    set dueDate(value) {
        this._dueDate = value || null;
    }

    @api
    get notes() {
        return this._notes;
    }

    set notes(value) {
        this._notes = value || '';
    }

    handleSubjectChange(event) {
        this._subject = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('subject', this._subject));
    }

    handleDueDateChange(event) {
        this._dueDate = event.target.value || null;
        this.dispatchEvent(new FlowAttributeChangeEvent('dueDate', this._dueDate));
    }

    handleNotesChange(event) {
        this._notes = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('notes', this._notes));
    }

    async handleSubmitTask() {
        if (!this.validateInputs()) {
            return;
        }
        if (!this.recordId) {
            this.showToast('Could not create task', 'Pass a Lead Id into this Flow component.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const taskId = await createFollowUpTask({
                leadId: this.recordId,
                subject: this._subject,
                dueDate: this._dueDate,
                notes: this._notes
            });
            this.taskId = taskId;
            this.taskSubmitted = true;
            this.dispatchEvent(new FlowAttributeChangeEvent('taskId', this.taskId));
            this.dispatchEvent(new FlowAttributeChangeEvent('taskSubmitted', true));
            this.showToast('Task created', null, 'success');
        } catch (error) {
            this.showToast('Could not create task', this.errorMessage(error), 'error');
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

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Try again.';
    }
}
