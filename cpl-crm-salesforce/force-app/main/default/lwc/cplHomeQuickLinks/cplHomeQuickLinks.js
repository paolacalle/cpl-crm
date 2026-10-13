import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const LINKS = [
    {
        key: 'members-with-applications',
        label: 'Members with Active Applications',
        icon: 'standard:person_account',
        objectApiName: 'Account',
        actionName: 'list',
        filterName: 'CPL_Applicant'
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

        this[NavigationMixin.Navigate](ref);
    }
}
