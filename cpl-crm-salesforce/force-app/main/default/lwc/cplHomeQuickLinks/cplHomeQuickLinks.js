import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';

const LINKS = [
    {
        key: 'new-lead',
        label: 'New CPL Scholar Lead',
        icon: 'standard:lead',
        objectApiName: 'Lead',
        actionName: 'new',
        useScholarRecordType: true
    },
    {
        key: 'intake-queue',
        label: 'Intake Queue',
        icon: 'standard:lead_insights',
        objectApiName: 'Lead',
        actionName: 'list',
        filterName: 'Intake_Review_Queue_Lead'
    },
    {
        key: 'form-submissions',
        label: 'Form Submissions Needing Review',
        icon: 'standard:form',
        objectApiName: 'Form_Submission__c',
        actionName: 'list',
        filterName: 'Intake_Review_Queue_Form_Submission'
    },
    {
        key: 'applications',
        label: 'Scholar Applications',
        icon: 'standard:scholar',
        objectApiName: 'Prospect_Scholar_Application__c',
        actionName: 'list',
        filterName: 'All'
    },
    {
        key: 'schools',
        label: 'Schools',
        icon: 'standard:account',
        objectApiName: 'Account',
        actionName: 'list',
        filterName: 'Schools'
    }
];

export default class CplHomeQuickLinks extends NavigationMixin(LightningElement) {
    leadInfo;

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredLeadInfo(result) {
        this.leadInfo = result;
    }

    get scholarLeadRecordTypeId() {
        if (!this.leadInfo || !this.leadInfo.data) return null;
        const infos = this.leadInfo.data.recordTypeInfos || {};
        const match = Object.values(infos).find((r) => r.developerName === 'CPL_Scholar_Lead');
        return match ? match.recordTypeId : null;
    }

    get links() {
        return LINKS;
    }

    handleClick(event) {
        const key = event.currentTarget.dataset.key;
        const link = LINKS.find((l) => l.key === key);
        if (!link) return;

        const ref = {
            type: 'standard__objectPage',
            attributes: {
                objectApiName: link.objectApiName,
                actionName: link.actionName
            }
        };

        if (link.actionName === 'list' && link.filterName) {
            ref.state = { filterName: link.filterName };
        }

        if (link.useScholarRecordType && this.scholarLeadRecordTypeId) {
            ref.state = { recordTypeId: this.scholarLeadRecordTypeId };
        }

        this[NavigationMixin.Navigate](ref);
    }
}