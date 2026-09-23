import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTasks from '@salesforce/apex/ProspectAppActionPlanController.getTasks';
import ensureCurrentStageTasks from '@salesforce/apex/ProspectAppActionPlanController.ensureCurrentStageTasks';
import markScholarshipInviteSent from '@salesforce/apex/ProspectAppActionPlanController.markScholarshipInviteSent';
import markReadyForDecision from '@salesforce/apex/ProspectAppActionPlanController.markReadyForDecision';
import LeadActionPlanFlowModal from 'c/leadActionPlanFlowModal';

export default class ProspectAppActionPlan extends LightningElement {
    @api recordId;
    tasks = [];
    error;
    wiredResult;
    repairedApplicationId;

    connectedCallback() {
        this.ensureTasks();
    }

    renderedCallback() {
        this.ensureTasks();
    }

    async ensureTasks() {
        if (!this.recordId || this.repairedApplicationId === this.recordId) {
            return;
        }

        this.repairedApplicationId = this.recordId;
        try {
            await ensureCurrentStageTasks({ applicationId: this.recordId });
            if (this.wiredResult) {
                await refreshApex(this.wiredResult);
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not prepare action plan',
                    message: error?.body?.message || 'Unexpected error creating missing action plan tasks.',
                    variant: 'error'
                })
            );
        }
    }

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
                showActions: task.isCurrent && this.actionsForTask(task).length > 0,
                isUpcoming: task.stateClass === 'upcoming',
                dueDate: task.dueDate,
                actions: this.actionsForTask(task).map((action) => ({
                    ...action,
                    disabled: !action.enabled,
                    buttonVariant: action.enabled ? 'brand' : 'neutral',
                    buttonClass: action.enabled ? 'slds-m-right_x-small slds-m-top_x-small' : 'slds-m-right_x-small slds-m-top_x-small disabled-action'
                }))
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

    actionsForTask(task) {
        if (task.actions?.length) {
            return task.actions;
        }

        if (task.subject === 'Scholarship invite') {
            return [
                { name: 'sendInvite', label: 'Send invite', type: 'flow', flowApiName: 'App_Send_Invite', enabled: true },
                { name: 'confirmInviteSent', label: 'Confirm invite was sent', type: 'apex', enabled: true },
                { name: 'confirmInviteAcceptance', label: 'Confirm invite acceptance', type: 'flow', flowApiName: 'App_Confirm_Invite_Acceptance', enabled: true }
            ];
        }

        if (task.subject === 'Collecting Material') {
            return [
                { name: 'sendMaterialsLink', label: 'Send materials link', type: 'flow', flowApiName: 'App_Send_Materials_Link', enabled: true },
                { name: 'confirmMaterials', label: 'Confirm materials', type: 'flow', flowApiName: 'App_Confirm_Materials', enabled: true }
            ];
        }

        if (task.subject === 'Interview + Evaluations') {
            return [
                { name: 'googleCalendar', label: 'Google Calendar', type: 'client', enabled: true },
                { name: 'zoom', label: 'Zoom coming soon', type: 'disabled', enabled: false },
                { name: 'genericEmail', label: 'Email applicant', type: 'client', enabled: true },
                { name: 'evaluationLink', label: 'Send evaluation link', type: 'client', enabled: true },
                { name: 'readyForDecision', label: 'Ready for decision', type: 'apex', enabled: true }
            ];
        }

        return [];
    }

    async handleAction(event) {
        const actionName = event.currentTarget.dataset.actionName;
        const actionType = event.currentTarget.dataset.actionType;
        const flowApiName = event.currentTarget.dataset.flow;
        const subject = event.currentTarget.dataset.subject;
        const stage = this.tasks.find((task) => task.subject === subject);

        if (actionType === 'disabled') {
            this.showToast('Coming soon', event.currentTarget.label, 'info');
            return;
        }

        if (actionType === 'flow') {
            await this.launchFlow(flowApiName, subject);
            return;
        }

        if (actionName === 'confirmInviteSent') {
            await this.runApexAction(
                () => markScholarshipInviteSent({ applicationId: this.recordId }),
                'Invite marked sent'
            );
            return;
        }

        if (actionName === 'readyForDecision') {
            await this.runApexAction(
                () => markReadyForDecision({ applicationId: this.recordId }),
                'Decision stage opened'
            );
            return;
        }

        if (actionName === 'googleCalendar') {
            this.openGoogleCalendar(stage);
            return;
        }

        if (actionName === 'genericEmail') {
            this.openMailTo(stage, 'CPL Scholar finalist follow up', this.genericEmailBody(stage));
            return;
        }

        if (actionName === 'evaluationLink') {
            this.openMailTo(stage, 'CPL Scholar evaluation request', this.evaluationEmailBody(stage));
        }
    }

    async launchFlow(flowApiName, subject) {
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

    async runApexAction(callback, successTitle) {
        try {
            await callback();
            await refreshApex(this.wiredResult);
            this.showToast(successTitle, null, 'success');
        } catch (error) {
            this.showToast('Action failed', this.errorMessage(error), 'error');
        }
    }

    openGoogleCalendar(stage) {
        const params = new URLSearchParams({
            action: 'TEMPLATE',
            text: `CPL Scholar interview - ${stage?.applicantName || 'Applicant'}`,
            details: `Salesforce Application: ${window.location.href}`
        });

        if (stage?.applicantEmail) {
            params.set('add', stage.applicantEmail);
        }

        window.open(
            `https://calendar.google.com/calendar/render?${params.toString()}`,
            '_blank',
            'noopener,noreferrer'
        );
    }

    openMailTo(stage, subject, body) {
        if (!stage?.applicantEmail) {
            this.showToast('Email unavailable', 'The applicant does not have an email address.', 'error');
            return;
        }

        const params = new URLSearchParams({
            subject,
            body
        });
        window.location.href = `mailto:${stage.applicantEmail}?${params.toString()}`;
    }

    genericEmailBody(stage) {
        return `Hi ${this.firstName(stage)},\n\nI wanted to follow up on your CPL Scholar finalist application.\n\nBest,\n${this.userName}`;
    }

    evaluationEmailBody(stage) {
        return `Hi ${this.firstName(stage)},\n\nWe are collecting evaluation feedback for your CPL Scholar finalist review. I will send the evaluation collection link shortly.\n\nBest,\n${this.userName}`;
    }

    firstName(stage) {
        return stage?.applicantName?.split(' ')[0] || 'there';
    }

    get userName() {
        return 'CPL Team';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Try again.';
    }
}
