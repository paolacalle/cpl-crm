import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import LIFECYCLE_FIELD from '@salesforce/schema/Account.CPL_Student_Lifecycle__c';
import GRADUATION_FIELD from '@salesforce/schema/Account.Graduation_Date__c';

const ENTRY_VALUES = ['Athlete', 'Lifter', 'Community', 'Applicant'];
const GRADUATED_VALUES = ['Alumni', 'Scholar Alumni'];

export default class CplMemberJourney extends LightningElement {
    @api recordId;
    record;
    error;

    @wire(getRecord, { recordId: '$recordId', fields: [LIFECYCLE_FIELD, GRADUATION_FIELD] })
    wiredRecord(result) {
        if (result.data) {
            this.record = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.record = undefined;
        }
    }

    get lifecycle() {
        return this.record ? getFieldValue(this.record, LIFECYCLE_FIELD) : null;
    }

    get graduationDate() {
        return this.record ? getFieldValue(this.record, GRADUATION_FIELD) : null;
    }

    get hasLifecycle() {
        return !!this.lifecycle;
    }

    get isInactive() {
        return this.lifecycle === 'Inactive';
    }

    get showJourney() {
        return this.hasLifecycle && !this.isInactive;
    }

    get stages() {
        const lc = this.lifecycle;
        const isEntry = ENTRY_VALUES.includes(lc);
        const isScholar = lc === 'Scholar';
        const wasScholar = lc === 'Scholar Alumni';
        const isGraduated = GRADUATED_VALUES.includes(lc);
        const gradLabel = this.graduationDate ? `Graduated ${this.formatDate(this.graduationDate)}.` : 'Alumni if no scholarship; Scholar Alumni if they received one.';

        return [
            {
                key: 'entry',
                number: '1',
                label: 'Entry',
                sublabel: isEntry ? lc : '',
                description: 'Joined CPL as Athlete, Lifter, Community, or Applicant.',
                stateClass: isEntry ? 'step step-current' : 'step step-completed'
            },
            {
                key: 'scholar',
                number: '2',
                label: 'Scholar',
                sublabel: isScholar ? 'Active Scholar' : '',
                description: 'Completed a successful scholarship application.',
                stateClass: isScholar
                    ? 'step step-current'
                    : wasScholar
                        ? 'step step-completed'
                        : 'step step-upcoming'
            },
            {
                key: 'graduated',
                number: '3',
                label: 'Graduated',
                sublabel: isGraduated ? lc : '',
                description: gradLabel,
                stateClass: isGraduated ? 'step step-current' : 'step step-upcoming'
            }
        ];
    }

    formatDate(iso) {
        if (!iso) return '';
        return new Date(`${iso}T00:00:00`).toLocaleDateString();
    }
}
