import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveInteraction from '@salesforce/apex/StructuredInteractionController.saveInteraction';

export default class FlowInteractionNoteInput extends LightningElement {
    @api recordId;
    @api sectionLabel = 'Add Contact Note';
    @api noteLabel = 'Note';
    @api notePlaceholder = '';
    @api required = false;
    @api requiredMessage = 'Enter a note.';
    @api showDetails = false;
    @api showSubmitButton = false;
    @api saveOnSubmit = false;
    @api submitButtonLabel = 'Submit Note';
    @api clearAfterSubmit = false;

    _title = 'Lead Stage : Contacting';
    _topics = 'Automated Note, Contacting, Lead Stage';
    _note = '';
    _interactionId;
    _noteSubmitted = false;
    isSaving = false;

    @api
    get title() {
        return this._title;
    }

    set title(value) {
        this._title = value || '';
    }

    @api
    get topics() {
        return this._topics;
    }

    set topics(value) {
        this._topics = value || '';
    }

    @api
    get note() {
        return this._note;
    }

    set note(value) {
        this._note = value || '';
    }

    @api
    get interactionId() {
        return this._interactionId;
    }

    set interactionId(value) {
        this._interactionId = value || null;
    }

    @api
    get noteSubmitted() {
        return this._noteSubmitted;
    }

    set noteSubmitted(value) {
        this._noteSubmitted = value === true || value === 'true';
    }

    handleNoteChange(event) {
        this._note = event.target.value;
        this.dispatchEvent(new FlowAttributeChangeEvent('note', this._note));
        this.dispatchEvent(new FlowAttributeChangeEvent('title', this._title));
        this.dispatchEvent(new FlowAttributeChangeEvent('topics', this._topics));
    }

    async handleSubmit() {
        if (!this.validate().isValid) {
            return;
        }

        if (!this.saveOnSubmit) {
            this.markSubmitted(null);
            return;
        }

        if (!this.recordId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save note',
                    message: 'Pass a record Id into this Flow component before saving notes.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isSaving = true;

        try {
            const interactionId = await saveInteraction({
                interactionId: null,
                parentRecordId: this.recordId,
                title: this._title,
                interactionDate: new Date().toISOString().slice(0, 10),
                note: this._note,
                topicIds: [],
                newTopicNames: this.parseTopics()
            });

            this.markSubmitted(interactionId);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Note saved',
                    variant: 'success'
                })
            );

            if (this.clearAfterSubmit) {
                this._note = '';
                this.dispatchEvent(new FlowAttributeChangeEvent('note', this._note));
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save note',
                    message: this.errorMessage(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    @api
    validate() {
        const textarea = this.template.querySelector('lightning-textarea');
        if (textarea) {
            textarea.reportValidity();
        }

        const hasNote = Boolean((this._note || '').trim());
        if (this.required && !hasNote && !this._noteSubmitted) {
            return {
                isValid: false,
                errorMessage: this.requiredMessage
            };
        }

        return { isValid: true };
    }

    markSubmitted(interactionId) {
        this._interactionId = interactionId || this._interactionId || null;
        this._noteSubmitted = true;
        this.dispatchEvent(new FlowAttributeChangeEvent('interactionId', this._interactionId));
        this.dispatchEvent(new FlowAttributeChangeEvent('noteSubmitted', this._noteSubmitted));
        this.dispatchEvent(new FlowAttributeChangeEvent('title', this._title));
        this.dispatchEvent(new FlowAttributeChangeEvent('topics', this._topics));
    }

    parseTopics() {
        return (this._topics || '')
            .split(',')
            .map((topic) => topic.trim())
            .filter((topic) => topic);
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Try again.';
    }
}
