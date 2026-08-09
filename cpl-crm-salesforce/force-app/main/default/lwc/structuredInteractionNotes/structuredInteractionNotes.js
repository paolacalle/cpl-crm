import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getActiveTopics from "@salesforce/apex/StructuredInteractionController.getActiveTopics";
import getInteractions from "@salesforce/apex/StructuredInteractionController.getInteractions";
import saveInteraction from "@salesforce/apex/StructuredInteractionController.saveInteraction";

export default class StructuredInteractionNotes extends LightningElement {
  @api recordId;
  @api maxListHeight = 420;

  activeTopics = [];
  interactions = [];
  selectedFilterTopicId = "";
  titleFilter = "";
  startDateFilter = "";
  endDateFilter = "";
  selectedTopicIds = [];
  title = "";
  interactionDate = this.today;
  note = "";
  newTopics = "";
  editingInteractionId;
  wiredTopicsResult;
  wiredInteractionsResult;
  isEditorOpen = false;
  isSaving = false;
  pageReferenceRecordId;

  @wire(CurrentPageReference)
  wiredPageReference(pageReference) {
    this.pageReferenceRecordId =
      pageReference?.attributes?.recordId || pageReference?.state?.recordId;
  }

  @wire(getActiveTopics)
  wiredTopics(result) {
    this.wiredTopicsResult = result;
    if (result.data) {
      this.activeTopics = result.data;
    }
  }

  @wire(getInteractions, {
    recordId: "$effectiveRecordId",
    topicId: "$selectedFilterTopicIdForApex",
    titleFilter: "$titleFilterForApex",
    startDate: "$startDateFilterForApex",
    endDate: "$endDateFilterForApex"
  })
  wiredInteractions(result) {
    this.wiredInteractionsResult = result;
    if (result.data) {
      this.interactions = result.data.map((interaction) => ({
        ...interaction,
        title: interaction.title || interaction.name,
        url: `/${interaction.id}`,
        formattedDate: this.formatDate(interaction.interactionDate),
        dateMonth: this.formatDatePart(interaction.interactionDate, "month"),
        dateDay: this.formatDatePart(interaction.interactionDate, "day"),
        createdDateLabel: this.formatDateTime(interaction.createdDate),
        lastModifiedDateLabel: this.formatDateTime(
          interaction.lastModifiedDate
        ),
        hasTopics: interaction.topics && interaction.topics.length > 0,
        topics: (interaction.topics || []).map((topic) => ({
          ...topic,
          className: topic.active
            ? "topic-pill"
            : "topic-pill topic-pill-retired"
        }))
      }));
    }
  }

  get hasRecordContext() {
    return !!this.effectiveRecordId;
  }

  get today() {
    return new Date().toISOString().slice(0, 10);
  }

  get selectedFilterTopicIdForApex() {
    return this.selectedFilterTopicId || null;
  }

  get titleFilterForApex() {
    return this.titleFilter?.trim() || null;
  }

  get startDateFilterForApex() {
    return this.startDateFilter || null;
  }

  get endDateFilterForApex() {
    return this.endDateFilter || null;
  }

  get effectiveRecordId() {
    return this.recordId || this.pageReferenceRecordId || null;
  }

  get topicOptions() {
    return this.activeTopics.map((topic) => ({
      label: topic.name,
      value: topic.id
    }));
  }

  get filterTopicOptions() {
    return [{ label: "All topics", value: "" }, ...this.topicOptions];
  }

  get hasInteractions() {
    return this.interactions.length > 0;
  }

  get timelineStyle() {
    const parsedHeight = Number(this.maxListHeight);
    const safeHeight =
      Number.isFinite(parsedHeight) && parsedHeight >= 240 ? parsedHeight : 420;
    return `max-height: ${safeHeight}px;`;
  }

  get filterSummary() {
    const activeFilters = [
      this.titleFilter?.trim(),
      this.selectedFilterTopicId,
      this.startDateFilter,
      this.endDateFilter
    ].filter(Boolean).length;

    return activeFilters === 0
      ? "Showing all interactions"
      : `${activeFilters} filter${activeFilters === 1 ? "" : "s"} applied`;
  }

  get isEditing() {
    return !!this.editingInteractionId;
  }

  get editorTitle() {
    return this.isEditing ? "Edit Interaction Note" : "New Interaction Note";
  }

  get saveLabel() {
    return this.isEditing ? "Save Changes" : "Save Interaction Note";
  }

  get saveDisabled() {
    return this.isSaving || !this.hasRecordContext;
  }

  get editorToggleIcon() {
    return this.isEditorOpen ? "utility:close" : "utility:add";
  }

  get editorToggleLabel() {
    return this.isEditorOpen ? "Close" : "New";
  }

  get editorToggleVariant() {
    return this.isEditorOpen ? "neutral" : "brand";
  }

  handleFilterChange(event) {
    this.selectedFilterTopicId = event.detail.value;
  }

  handleClearFilters() {
    this.selectedFilterTopicId = "";
    this.titleFilter = "";
    this.startDateFilter = "";
    this.endDateFilter = "";
  }

  handleInputChange(event) {
    this[event.target.name] = event.detail.value;
  }

  handleTopicsChange(event) {
    this.selectedTopicIds = event.detail.value;
  }

  toggleEditor() {
    if (this.isEditorOpen) {
      this.resetForm();
      return;
    }

    this.isEditorOpen = !this.isEditorOpen;
  }

  async handleRefresh() {
    await Promise.all([
      refreshApex(this.wiredTopicsResult),
      refreshApex(this.wiredInteractionsResult)
    ]);
  }

  handleEdit(event) {
    const interaction = this.interactions.find(
      (row) => row.id === event.currentTarget.dataset.id
    );
    if (!interaction) {
      return;
    }
    this.editingInteractionId = interaction.id;
    this.title = interaction.title || "";
    this.interactionDate = interaction.interactionDate;
    this.note = interaction.note;
    this.selectedTopicIds = interaction.topicIds || [];
    this.newTopics = "";
    this.isEditorOpen = true;
  }

  handleCancelEdit() {
    this.resetForm();
  }

  async handleSave() {
    if (!this.hasRecordContext) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not save interaction",
          message: "Add this component to a record page before saving notes.",
          variant: "error"
        })
      );
      return;
    }

    if (!this.validateForm()) {
      return;
    }

    this.isSaving = true;

    try {
      await saveInteraction({
        interactionId: this.editingInteractionId || null,
        parentRecordId: this.effectiveRecordId,
        title: this.title,
        interactionDate: this.interactionDate,
        note: this.note,
        topicIds: this.selectedTopicIds || [],
        newTopicNames: this.parseNewTopics()
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: this.isEditing ? "Interaction updated" : "Interaction saved",
          variant: "success"
        })
      );

      this.resetForm();

      await Promise.all([
        refreshApex(this.wiredTopicsResult),
        refreshApex(this.wiredInteractionsResult)
      ]);
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not save interaction",
          message:
            error?.body?.message ||
            `Unexpected error saving the interaction. Record: ${this.effectiveRecordId}`,
          variant: "error"
        })
      );
    } finally {
      this.isSaving = false;
    }
  }

  validateForm() {
    const fields = [
      ...this.template.querySelectorAll("lightning-input, lightning-textarea")
    ];
    return fields.reduce((isValid, field) => {
      field.reportValidity();
      return isValid && field.checkValidity();
    }, true);
  }

  parseNewTopics() {
    return (this.newTopics || "")
      .split(",")
      .map((name) => name.trim())
      .filter((name) => name.length > 0);
  }

  resetForm() {
    this.editingInteractionId = null;
    this.title = "";
    this.interactionDate = this.today;
    this.note = "";
    this.selectedTopicIds = [];
    this.newTopics = "";
    this.isEditorOpen = false;
  }

  formatDate(value) {
    if (!value) {
      return "";
    }
    return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(
      new Date(`${value}T00:00:00`)
    );
  }

  formatDatePart(value, part) {
    if (!value) {
      return "";
    }

    const options = part === "month" ? { month: "short" } : { day: "2-digit" };
    return new Intl.DateTimeFormat(undefined, options).format(
      new Date(`${value}T00:00:00`)
    );
  }

  formatDateTime(value) {
    if (!value) {
      return "";
    }
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(new Date(value));
  }
}
