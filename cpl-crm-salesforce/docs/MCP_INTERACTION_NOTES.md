# MCP interaction note flows

The first two tools are `MCP_Create_Interaction_Note` (note plus existing-topic links)
and `MCP_Update_Interaction_Note` (note content only). Both are delivered as **Draft**
autolaunched flows. This package does not deploy or change the existing task flows.

## Deploy when ready

From the Salesforce project directory:

```sh
sf project deploy start --manifest manifest/mcp-interaction-notes.xml --target-org CPLProduction --test-level RunSpecifiedTests --tests MCPInteractionFlowsTest
```

The [manifest](../manifest/mcp-interaction-notes.xml) selects only the two new flows
and their Apex test class. Avoid deploying the entire source directory: it also
contains the requested production-flow refresh and unrelated existing work.

After deployment, review and activate both flows in Flow Builder, grant the
calling user appropriate Flow/object/field/record access, then add the activated
flows to the custom Salesforce MCP server. Refresh Claude's tool list.

Flows use `DefaultMode`, not an explicit system-context override. Verify access
using the actual MCP user's account. The existing Structured Interactions User
permission set is a starting point, not a newly assigned permission in this package.
Creation requires access to the selected Contact/Lead, active topics, and create
access to the interaction and its junction records; updating requires edit access
to the target interaction and supplied fields.

## Create contract

| Input | Type | Behavior |
|---|---|---|
| `contactId` | Text | Exactly one of contactId or leadId is required. Must be an accessible Contact ID. |
| `leadId` | Text | Alternative to contactId; must be an accessible Lead ID. |
| `title` | Text | Required, nonblank, maximum 255 characters. |
| `note` | Text | Required, nonblank, maximum 32,768 characters. Preserves supplied content. |
| `interactionDate` | Date | Required occurrence date; no guessed default. |
| `topicIds` | Text collection | Existing active Topic__c IDs. Omit/empty allows an unlabeled note. Duplicates produce one link. |

Account IDs are not accepted as parents. For a Person Account, resolve its
PersonContactId first. The existing UI controller supports additional parent
resolution, but these MCP flows intentionally require an explicit Contact or Lead.

The flow validates required inputs, the selected person, and all supplied topics
before creating records. It bulk-fetches topics once and inserts the junction
collection outside the loop. Both 15- and 18-character topic IDs are accepted.
Missing, inactive, inaccessible, malformed or wrong-object topics fail the request.
It never creates/reactivates/renames shared topics and never deletes records.

Outputs: `isSuccess`, `interactionId`, `errorMessage`, `topicCount` (distinct links).
The success flag and interaction ID are assigned only after all writes succeed.

## Update contract

| Input | Type | Behavior |
|---|---|---|
| `interactionId` | Text | Required Interaction__c ID; also returned as an output. |
| `title` | Text | Optional full replacement; blank/omitted preserves. Maximum 255 characters. |
| `note` | Text | Optional full replacement; blank/omitted preserves. Maximum 32,768 characters. |
| `interactionDate` | Date | Optional replacement; omitted preserves. |

At least one change is required. Conditional assignments build a sparse update
record so omitted fields are not written back from a stale read. The flow does
not change the Contact, Lead, owner, labels, junctions or topics. It does not
support clearing fields or automatically appending content. Read and merge the
existing note when a user asks to append. Explicit content replaces the entire field.

Outputs: `isSuccess`, `interactionId`, `errorMessage`. An ID alone is not success.

## Transaction and error handling

Validation/read errors before writing return `isSuccess=false` with `errorMessage`.
The write elements intentionally have **no fault connectors**. A write failure
must abort the synchronous transaction so that a failed topic-link insert cannot
leave its newly created interaction behind. The caller receives a platform error
instead of the normal output envelope for these failures.

Do not add an Assignment-only fault path after writes: catching a fault and ending
normally can commit earlier writes. Do not split creation across transactions,
asynchronous actions or pauses. These tools are intended as standalone synchronous
MCP calls. An Apex/subflow wrapper that catches their failures must separately
ensure rollback; do not assume the wrapper preserves this transaction contract.

Salesforce references:
- [Rollback behavior](https://trailhead.salesforce.com/content/learn/modules/flow-implementation-2/roll-back-changes-after-an-error)
- [Flow MCP tools](https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/flows.html)

## Claude usage

Use existing active topics first. Propose fitting labels and ask Lisa whether she
wants different ones before creation, unless her request already specifies her
choice. Never invent IDs or silently create a new shared topic. Resolve ambiguous
people and topics before calling. Do not infer a missing interaction date.

For updates, retrieve the intended interaction first and send only requested edits.
Do not call the update tool to replace labels. Separate label-management tools
remain future work.

Check the platform response for a fault and then the flow's `isSuccess` output.
Report what succeeded, not just that the tool returned. If a response is lost,
query Salesforce before retrying; creation does not have an idempotency key.
Identical note content on separate calls can create separate records.

## Verification

Validation against `CPLProduction` on October 5, 2026 succeeded with
`checkOnly=true`: 10 tests passed, zero component/test errors, and no metadata
warnings. Validation ID: `0AfVx000001iNTNKA2`. No flows were deployed or activated.
Tests exercised 22/23 create-flow elements and 14/15 update-flow elements; the
uncovered elements are the pre-write query-fault handlers.

`MCPInteractionFlowsTest` runs both flows with isolated test records. It covers
Contact/Lead creation, empty labels, multiple and duplicate topics, 15-character
IDs, rejected inactive/wrong-object topics, missing/whitespace input, parent
ambiguity, content/date updates, preserved omitted fields and links, no-change
requests and missing records.

Deployment validation compiles the actual flows and executes these tests in the
target org without retaining changes. It does not test Claude's tool discovery or
the actual MCP user's permissions. After deployment/activation, verify those with
the intended user and perform a rollback-mode Flow Builder debug before real use.

The all-or-nothing write design is based on Salesforce transaction semantics; the
test suite does not inject a post-note junction-DML failure. Keep the write-fault
contract intact when extending these flows.
