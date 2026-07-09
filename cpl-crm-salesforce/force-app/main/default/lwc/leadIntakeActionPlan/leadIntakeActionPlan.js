import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LeadActionPlanFlowModal from 'c/leadActionPlanFlowModal';
import getTasks from '@salesforce/apex/LeadIntakeActionPlanController.getTasks';
import getLeadState from '@salesforce/apex/LeadIntakeActionPlanController.getLeadState';
import reopenLead from '@salesforce/apex/LeadIntakeActionPlanController.reopenLead';

export default class LeadIntakeActionPlan extends NavigationMixin(LightningElement) {
    @api recordId;
    tasks = [];
    leadState = {};
    wiredResult;
    wiredStateResult;
    reopening = false;

    @wire(getTasks, { leadId: '$recordId' })
    wiredTasks(result) {
        this.wiredResult = result;
        if (result.data) {
            this.tasks = result.data.map((task) => ({
                ...task,
                taskUrl: task.taskId ? `/${task.taskId}` : null,
                ownerLabel: task.ownerName ? `Assigned to ${task.ownerName}` : 'Task not created',
                badgeClass: `step step-${task.stateClass}`,
                statusClass: `status status-${task.stateClass}`,
                showLaunch: task.isCurrent && !!task.flowApiName,
                isUpcoming: task.stateClass === 'upcoming'
            }));
        } else if (result.error) {
            this.tasks = [];
        }
        // While the wire is reloading (no data, no error) keep the current
        // steps on screen so editing the Lead does not flash an empty plan.
    }

    @wire(getLeadState, { leadId: '$recordId' })
    wiredState(result) {
        this.wiredStateResult = result;
        if (result.data) {
            this.leadState = result.data;
        }
    }

    get hasTasks() {
        return this.tasks.length > 0;
    }

    get isConverted() {
        return this.leadState && this.leadState.isConverted === true;
    }

    get isUnqualified() {
        return this.leadState && this.leadState.isUnqualified === true;
    }

    get canViewConverted() {
        return this.isConverted && !!this.leadState.convertedRecordId;
    }

    handleViewConverted() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.leadState.convertedRecordId,
                actionName: 'view'
            }
        });
    }

    async handleReopen() {
        this.reopening = true;
        try {
            await reopenLead({ leadId: this.recordId });
            await Promise.all([
                refreshApex(this.wiredStateResult),
                refreshApex(this.wiredResult)
            ]);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Lead re-opened',
                    message: 'The lead is back in the intake pipeline and the outcome step is active again.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not re-open lead',
                    message: error?.body?.message || 'Unexpected error re-opening the lead.',
                    variant: 'error'
                })
            );
        } finally {
            this.reopening = false;
        }
    }

    async handleLaunch(event) {
        const { flow, subject } = event.currentTarget.dataset;
        const result = await LeadActionPlanFlowModal.open({
            size: 'medium',
            flowApiName: flow,
            flowLabel: subject,
            recordId: this.recordId
        });

        if (result !== 'finished') {
            return;
        }

        await refreshApex(this.wiredResult);
        await refreshApex(this.wiredStateResult);

        const completed = this.tasks.some(
            (task) => task.subject === subject && task.stateClass === 'completed'
        );
        this.dispatchEvent(
            new ShowToastEvent(
                completed
                    ? {
                          title: 'Step completed',
                          message: `${subject} marked complete.`,
                          variant: 'success'
                      }
                    : {
                          title: 'Not completed',
                          message: `${subject} was not marked complete. Re-open the step and finish it.`,
                          variant: 'warning'
                      }
            )
        );
    }
}
