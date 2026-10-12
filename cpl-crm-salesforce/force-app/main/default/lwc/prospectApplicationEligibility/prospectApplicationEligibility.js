import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchMembers from '@salesforce/apex/ProspectApplicationEligibilityController.searchMembers';
import getMemberContext from '@salesforce/apex/ProspectApplicationEligibilityController.getMemberContext';
import createApplication from '@salesforce/apex/ProspectApplicationEligibilityController.createApplication';

export default class ProspectApplicationEligibility extends NavigationMixin(LightningElement) {
    searchTerm = '';
    searchResults = [];
    selectedMember;
    internships = [];
    collegeYear;
    isSearching = false;
    isLoadingMember = false;
    isSaving = false;

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get hasSelectedMember() {
        return Boolean(this.selectedMember);
    }

    get hasInternships() {
        return this.internships.length > 0;
    }

    get qualifyingCount() {
        return this.internships.filter((internship) => internship.isQualifying).length;
    }

    get classYearComplete() {
        return this.collegeYear === 'Junior' || this.collegeYear === 'Senior';
    }

    get canCreate() {
        return this.hasSelectedMember && this.classYearComplete && this.qualifyingCount > 0 && !this.isSaving;
    }

    get isCreateDisabled() {
        return !this.canCreate;
    }

    get eligibilityMessage() {
        if (!this.hasSelectedMember) return 'Select a CPL member to begin.';
        if (!this.classYearComplete) return 'Select Junior or Senior to meet the class-year requirement.';
        if (this.qualifyingCount === 0) return 'Mark at least one internship as qualifying.';
        return 'Both eligibility requirements are complete.';
    }

    get eligibilityVariant() {
        return this.canCreate ? 'utility:success' : 'utility:warning';
    }

    get classYearOptions() {
        return [
            { label: 'Junior', value: 'Junior' },
            { label: 'Senior', value: 'Senior' }
        ];
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        this.searchResults = [];
    }

    async handleSearch() {
        if (this.searchTerm.trim().length < 2) {
            this.showToast('Enter more detail', 'Search using at least two characters of the member’s name.', 'info');
            return;
        }
        this.isSearching = true;
        try {
            this.searchResults = await searchMembers({ searchTerm: this.searchTerm });
        } catch (error) {
            this.handleError(error, 'Unable to search members');
        } finally {
            this.isSearching = false;
        }
    }

    async handleSelectMember(event) {
        const memberId = event.currentTarget.dataset.id;
        this.isLoadingMember = true;
        try {
            const context = await getMemberContext({ memberId });
            this.selectedMember = { id: context.memberId, name: context.memberName, email: context.memberEmail };
            this.internships = context.internships.map((internship) => ({ ...internship }));
            this.searchResults = [];
            this.searchTerm = '';
        } catch (error) {
            this.handleError(error, 'Unable to load member details');
        } finally {
            this.isLoadingMember = false;
        }
    }

    handleClassYearChange(event) {
        this.collegeYear = event.detail.value;
    }

    handleInternshipChange(event) {
        const internshipId = event.target.dataset.id;
        const isQualifying = event.target.checked;
        this.internships = this.internships.map((internship) =>
            internship.id === internshipId ? { ...internship, isQualifying } : internship
        );
    }

    handleClear() {
        this.selectedMember = undefined;
        this.internships = [];
        this.collegeYear = undefined;
        this.searchResults = [];
        this.searchTerm = '';
    }

    async handleCreate() {
        if (!this.canCreate) return;
        this.isSaving = true;
        try {
            const applicationId = await createApplication({
                memberId: this.selectedMember.id,
                collegeYear: this.collegeYear,
                qualifyingInternshipIds: this.internships
                    .filter((internship) => internship.isQualifying)
                    .map((internship) => internship.id)
            });
            this.showToast('Application created', 'The member is eligible and the prospect application is ready.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: applicationId, objectApiName: 'Prospect_Scholar_Application__c', actionName: 'view' }
            });
        } catch (error) {
            this.handleError(error, 'Unable to create application');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleError(error, title) {
        const message = Array.isArray(error?.body)
            ? error.body.map((item) => item.message).join(', ')
            : error?.body?.message || error?.message || 'An unexpected error occurred.';
        this.showToast(title, message, 'error');
    }
}
