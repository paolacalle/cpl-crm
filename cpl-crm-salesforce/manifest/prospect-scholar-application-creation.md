# Dev deployment: application membership and quick views

Deploy [the task manifest](./prospect-scholar-application-creation.xml) to dev only:

```bash
sf project deploy start --manifest manifest/prospect-scholar-application-creation.xml --target-org cpl-sandbox --test-level RunSpecifiedTests --tests ScholarApplicationMembershipTest --tests CplHomeMemberPipelineControllerTest --tests ScholarApplicationStageServiceTest --wait 30
```

The Screen Flow remains Draft in source. Deployment does not assign the New override.
This package adds application-indicator automation, not application creation or duplicate enforcement.

After deployment:

1. Assign **CPL Application Membership Read** to staff using the views. It grants read-only field access, not additional Account or application record access.
2. Populate existing member flags once:

   ```bash
   sf apex run --file scripts/apex/backfillScholarApplicationMembership.apex --target-org YOUR_DEV_ALIAS
   ```

3. Check the returned job in **Setup > Apex Jobs**. Confirm completion with zero errors before relying on the lists. The batch updates Accounts, so existing Account automation also runs. It is safe to rerun for reconciliation.
4. Assign **CPL Scholarship Pipeline** to staff using the pipeline. Run the stage/decision backfill below, verify Apex Jobs completed with zero errors, then reload Home. Quick links are Members with Active Applications and Schools. Scholarship Application Pipeline replaces the Scholar Applications quick link. Other lifecycle tiles are unchanged.
5. Verify both existing Applicant list views now select Person Accounts with the new flag checked. The restricted view retains its existing group sharing.
6. Test a member with no applications, one open application, several open applications, and only closed applications. Verify reparenting, deletion and restoration update both affected members. Waitlisted stays active; Accepted, Rejected and Withdrawn are closed.

Lifecycle values and automation are not migrated or removed. Members still marked Applicant will not have a pipeline tile; use the active-application view for current applications. Closed historical Applicants are not automatically reclassified.

The stored flag counts all applications in system context, including those hidden from a particular viewer. It is not a uniqueness constraint. Existing terminal-status validation rules continue to govern whether applications can be reopened.

The updated package passed validation-only deployment 0AfWe00000GF4QHKA1 to cpl-sandbox on 2026-10-12. No deployment or data migration was saved.

## Scholarship stage and decision migration

After deployment and permission assignment:

```bash
sf apex run --file scripts/apex/backfillScholarApplicationStages.apex --target-org cpl-sandbox
```

Wait for completion with zero errors in Apex Jobs before relying on pipeline counts.

| Existing status | New Application Stage | New Application Decision |
| --- | --- | --- |
| Invite Sent / Collecting Documents | Invite & Materials | Pending |
| In Review | Interview & Evaluations | Pending |
| Waitlisted | Ready for Decision | Waitlisted |
| Accepted / Rejected / Withdrawn | Closed | Same as existing status |

Application Stage and Application Decision are new stored fields. The old Application Status definition, including the corrected In Review label and default, is not deployed or overwritten. It remains synchronized behind the scenes for existing flows, validation rules, acceptance actions, Scholar promotion, and the active-application flag.

Staff use **Update Stage / Decision** to move completed reviews to Ready for Decision. Historical In Review records are not assumed to have completed interviews. Stage changes do not automatically complete action-plan tasks. Accepted, Rejected and Withdrawn force Closed; Waitlisted stays Ready for Decision. Closed with Pending is rejected. Existing terminal-status locks remain in effect.

All Decisions displays current non-Pending decisions, not decision history. Waitlisted appears in both Ready for Decision and All Decisions; the four counts are not additive.

The backfill fills missing fields without intentionally changing legacy statuses. It runs normal application validation and automation: inspect Apex Job errors and correct invalid historical records rather than bypassing validation. It can be rerun. Applications without the new fields populated do not appear in stage views.

The package updates the local Home definition, the normal application layout, the progress card, and Update Status action. Existing page activation assignments do not change. If another Home page is assigned in dev, add **Scholarship Application Pipeline** there using Lightning App Builder.

This compatibility approach defers retiring the old status field until every consumer is migrated. The eligibility Screen Flow remains the earlier read-only draft.
