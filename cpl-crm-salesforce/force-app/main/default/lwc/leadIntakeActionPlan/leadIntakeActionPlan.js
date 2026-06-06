import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LeadActionPlanFlowModal from 'c/leadActionPlanFlowModal';
import getTasks from '@salesforce/apex/LeadIntakeActionPlanController.getTasks';

export default class LeadIntakeActionPlan extends LightningElement {
    @api recordId;
    tasks = [];
    wiredResult;

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

    get hasTasks() {
        return this.tasks.length > 0;
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
