({
    resolveAccount: function(component) {
        var page = component.get("v.pageReference") || {};
        var state = page.state || {};
        var accountId = state.c__accountId;
        // Related-list context is not guaranteed; reject absent or non-Account context.
        if (!accountId && state.inContextOfRef) {
            try {
                var encoded = state.inContextOfRef.replace(/^1\./, "");
                encoded = encoded.replace(/-/g, "+").replace(/_/g, "/");
                while (encoded.length % 4) {
                    encoded += "=";
                }
                var context = JSON.parse(window.atob(encoded));
                var attributes = context.attributes || {};
                if (attributes.objectApiName === "Account") {
                    accountId = attributes.recordId;
                }
            } catch (error) {
                accountId = null;
            }
        }
        if (typeof accountId !== "string" || !/^001[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$/.test(accountId)) {
            component.set("v.accountId", null);
            component.set("v.errorMessage", "The originating CPL Member Account could not be identified. Open the member's Account and select New from its Prospect Scholar Applications related list. If this message persists there, the related list is not supplying the expected Account context.");
            return;
        }
        component.set("v.errorMessage", null);
        component.set("v.accountId", accountId);
    },
    startWhenReady: function(component) {
        var accountId = component.get("v.accountId");
        if (!accountId || component.get("v.flowStarted")) {
            return;
        }
        var flow = component.find("eligibilityFlow");
        if (!flow) {
            return;
        }
        // Render lifecycle ensures the conditional child exists; guard before startFlow.
        component.set("v.flowStarted", true);
        try {
            flow.startFlow("Create_Prospect_Scholar_Application", [
                { name: "recordId", type: "String", value: accountId }
            ]);
        } catch (error) {
            component.set("v.errorMessage", "The flow could not start. Confirm that Create Prospect Scholar Application is active and that you have permission to run it.");
        }
    },
    navigateBack: function(component) {
        var accountId = component.get("v.accountId");
        var page = accountId ? {
            type: "standard__recordPage",
            attributes: { recordId: accountId, objectApiName: "Account", actionName: "view" }
        } : {
            type: "standard__objectPage",
            attributes: { objectApiName: "Prospect_Scholar_Application__c", actionName: "list" },
            state: { filterName: "Recent" }
        };
        component.find("navigation").navigate(page, true);
    }
})
