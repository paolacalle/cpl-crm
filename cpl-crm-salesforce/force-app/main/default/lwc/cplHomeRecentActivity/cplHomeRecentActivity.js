import { LightningElement, wire } from 'lwc';
import getActivity from '@salesforce/apex/CplHomeRecentActivityController.getActivity';

export default class CplHomeRecentActivity extends LightningElement {
    items;
    error;

    @wire(getActivity)
    wiredActivity({ data, error }) {
        if (data) {
            this.items = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.items = undefined;
        }
    }

    get rows() {
        return this.items ? this.items.map((item) => ({
            ...item,
            url: `/lightning/r/${item.objectApiName}/${item.id}/view`,
            timeLabel: this.formatTimestamp(item.timestamp)
        })) : [];
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get errorMessage() {
        if (!this.error) return null;
        return (this.error.body && this.error.body.message) || 'Could not load activity.';
    }

    formatTimestamp(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        const now = new Date();
        const diffMs = now - d;
        const diffMin = Math.floor(diffMs / 60000);
        if (diffMin < 1) return 'just now';
        if (diffMin < 60) return `${diffMin}m ago`;
        const diffHr = Math.floor(diffMin / 60);
        if (diffHr < 24) return `${diffHr}h ago`;
        const diffDay = Math.floor(diffHr / 24);
        if (diffDay < 7) return `${diffDay}d ago`;
        return d.toLocaleDateString();
    }
}