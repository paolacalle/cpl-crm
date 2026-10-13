import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class LeadActionPlanFlowModal extends LightningModal {
    @api flowApiName;
    @api recordId;
    @api flowLabel;

    get inputVariables() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }

    handleStatusChange(event) {
        const status = event.detail.status;
        if (status === 'FINISHED' || status === 'FINISHED_SCREEN') {
            this.close('finished');
        }
    }
}