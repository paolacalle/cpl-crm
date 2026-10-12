({
    initialize: function(component, event, helper) {
        // A pageReference can arrive after init. Do not restart an active interview.
        if (!component.get("v.flowStarted")) {
            helper.resolveAccount(component);
        }
    },
    handleRender: function(component, event, helper) {
        helper.startWhenReady(component);
    },
    handleStatusChange: function(component, event, helper) {
        var status = event.getParam("status");
        if (status === "FINISHED" || status === "FINISHED_SCREEN") {
            helper.navigateBack(component);
        } else if (status === "ERROR") {
            component.set("v.errorMessage", "The flow could not run. Confirm that Create Prospect Scholar Application is active and that you have permission to run it.");
        }
    },
    handleCancel: function(component, event, helper) {
        helper.navigateBack(component);
    }
})
