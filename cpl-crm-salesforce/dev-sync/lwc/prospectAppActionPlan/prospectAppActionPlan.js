import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTasks from '@salesforce/apex/ProspectAppActionPlanController.getTasks';
import LeadActionPlanFlowModal from 'c/leadActionPlanFlowModal';

export default class ProspectAppActionPlan extends LightningElement {
    @api recordId;
    tasks = [];
    error;
    wiredResult;

    @wire(getTasks, { applicationId: '$recordId' })
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.tasks = result.data.map((task) => ({
                ...task,
                taskUrl: task.taskId ? `/lightning/r/Task/${task.taskId}/view` : null,
                ownerLabel: task.ownerName ? `Owner: ${task.ownerName}` : 'Owner: Unassigned',
                badgeClass: `step ${task.stateClass}`,
                statusClass: `status status-${task.stateClass}`,
                showLaunch: task.isCurrent && !!task.flowApiName,
                isUpcoming: task.stateClass === 'upcoming',
                dueDate: task.dueDate
            }));
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.tasks = [];
        }
    }

    get hasTasks() {
        return this.tasks.length > 0;
    }

    async handleLaunch(event) {
        const flowApiName = event.currentTarget.dataset.flow;
        const subject = event.currentTarget.dataset.subject;
        if (!flowApiName) return;
        const result = await LeadActionPlanFlowModal.open({
            size: 'medium',
            flowApiName: flowApiName,
            recordId: this.recordId,
            flowLabel: subject
        });
        if (result === 'finished') {
            await refreshApex(this.wiredResult);
            const completedNow = this.tasks.find(
                (t) => t.subject === subject && t.status === 'Completed'
            );
            if (completedNow) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Step completed',
                        message: subject,
                        variant: 'success'
                    })
                );
            }
        }
    }
}