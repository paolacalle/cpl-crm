import { LightningElement, api } from 'lwc';
import sendInvite from '@salesforce/apex/ScholarshipInviteActionCtrl.sendInvite';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SendFinalistMaterialsInvite extends LightningElement {
    @api recordId;
    isSaving = false;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSend() {
        if (!this.recordId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing record',
                    message: 'Open the action from a Prospect Scholar Application record.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isSaving = true;
        try {
            await sendInvite({
                applicationId: this.recordId
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Finalist materials invite sent',
                    message: 'The personalized link was emailed to the applicant.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to send invite',
                    message: this.reduceError(error),
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error.';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).filter(Boolean).join(', ');
        }

        return error.body?.message || error.message || 'Unknown error.';
    }
}
