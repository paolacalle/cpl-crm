import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getLeadPrimarySportOptions from '@salesforce/apex/SportPicklistOptionsController.getLeadPrimarySportOptions';

export default class SearchableSportPicklist extends LightningElement {
    @api label = 'Primary Sport';
    @api placeholder = 'Search sports...';
    @api required = false;

    _value;
    options = [];
    searchTerm = '';
    isOpen = false;
    errorMessage = '';

    @api
    get value() {
        return this._value;
    }

    set value(newValue) {
        this._value = newValue;
        this.searchTerm = this.labelForValue(newValue);
    }

    @wire(getLeadPrimarySportOptions)
    wiredPicklistValues({ data }) {
        if (!data) {
            return;
        }

        this.options = data.map((entry) => ({
            label: entry.label,
            value: entry.value
        }));
        this.searchTerm = this.labelForValue(this._value);
    }

    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isOpen ? ' slds-is-open' : ''}`;
    }

    get filteredOptions() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term || this.searchTerm === this.labelForValue(this._value)) {
            return this.options;
        }

        return this.options
            .filter((option) => option.label.toLowerCase().includes(term));
    }

    get hasOptions() {
        return this.filteredOptions.length > 0;
    }

    openList() {
        this.isOpen = true;
        this.errorMessage = '';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.isOpen = true;
        if (!this.searchTerm) {
            this.setSelectedValue(null);
        }
    }

    handleSelect(event) {
        this.searchTerm = event.currentTarget.dataset.label;
        this.setSelectedValue(event.currentTarget.dataset.value);
        this.isOpen = false;
    }

    handleBlur() {
        window.setTimeout(() => {
            this.isOpen = false;
            this.searchTerm = this.labelForValue(this._value);
        }, 200);
    }

    @api
    validate() {
        if (this.required && !this._value) {
            this.errorMessage = 'Select a primary sport.';
            return {
                isValid: false,
                errorMessage: this.errorMessage
            };
        }

        this.errorMessage = '';
        return { isValid: true };
    }

    setSelectedValue(selectedValue) {
        this._value = selectedValue;
        this.errorMessage = '';
        this.dispatchEvent(new FlowAttributeChangeEvent('value', selectedValue));
    }

    labelForValue(value) {
        if (!value || !this.options.length) {
            return value || '';
        }

        const selectedOption = this.options.find((option) => option.value === value);
        return selectedOption ? selectedOption.label : value;
    }
}
