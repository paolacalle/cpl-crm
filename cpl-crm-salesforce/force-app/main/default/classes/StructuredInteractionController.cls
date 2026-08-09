public with sharing class StructuredInteractionController {
  private static final List<String> LEAD_LOOKUP_FIELD_PRIORITY = new List<String>{
    'Lead__c',
    'Matched_Lead__c',
    'Source_Lead__c',
    'LeadId',
    'WhoId'
  };

  private static final List<String> CONTACT_LOOKUP_FIELD_PRIORITY = new List<String>{
    'Contact__c',
    'Matched_Contact__c',
    'Applicant_Contact__c',
    'CPL_Member__c',
    'ContactId',
    'WhoId'
  };

  private static final List<String> ACCOUNT_LOOKUP_FIELD_PRIORITY = new List<String>{
    'Applicant_Account__c',
    'Account__c',
    'Person_Account__c',
    'Member_Account__c',
    'Recipient_Account__c',
    'AccountId'
  };

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getActiveTopics() {
    List<Map<String, Object>> options = new List<Map<String, Object>>();

    for (Topic__c topic : [
      SELECT Id, Name, Active__c
      FROM Topic__c
      WHERE Active__c = TRUE
      ORDER BY Name ASC
    ]) {
      options.add(
        new Map<String, Object>{
          'id' => topic.Id,
          'name' => topic.Name,
          'active' => topic.Active__c
        }
      );
    }

    return options;
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getInteractions(
    Id recordId,
    Id topicId,
    String titleFilter,
    Date startDate,
    Date endDate
  ) {
    if (recordId == null) {
      return new List<Map<String, Object>>();
    }

    InteractionParent parent = resolveInteractionParent(recordId);
    if (parent == null) {
      return new List<Map<String, Object>>();
    }

    Id parentId = parent.id;
    String titleLike = String.isBlank(titleFilter)
      ? null
      : '%' + String.escapeSingleQuotes(titleFilter.trim()) + '%';
    String queryText =
      'SELECT Id, Name, Title__c, Note__c, Interaction_Date__c, ' +
      'CreatedDate, LastModifiedDate, CreatedBy.Name, LastModifiedBy.Name ' +
      'FROM Interaction__c WHERE ' +
      parent.fieldApiName +
      ' = :parentId ';

    if (titleLike != null) {
      queryText += 'AND Title__c LIKE :titleLike ';
    }

    if (startDate != null) {
      queryText += 'AND Interaction_Date__c >= :startDate ';
    }

    if (endDate != null) {
      queryText += 'AND Interaction_Date__c <= :endDate ';
    }

    Set<Id> matchingInteractionIds;
    if (topicId != null) {
      matchingInteractionIds = new Set<Id>();

      for (InteractionTopic__c link : [
        SELECT Interaction__c
        FROM InteractionTopic__c
        WHERE Topic__c = :topicId
      ]) {
        matchingInteractionIds.add(link.Interaction__c);
      }

      if (matchingInteractionIds.isEmpty()) {
        return new List<Map<String, Object>>();
      }

      queryText += 'AND Id IN :matchingInteractionIds ';
    }

    queryText += 'ORDER BY Interaction_Date__c DESC, CreatedDate DESC';

    List<Interaction__c> interactions = Database.query(queryText);
    return buildRows(interactions);
  }

  @AuraEnabled
  public static Id saveInteraction(
    Id interactionId,
    Id parentRecordId,
    String title,
    Date interactionDate,
    String note,
    List<Id> topicIds,
    List<String> newTopicNames
  ) {
    if (parentRecordId == null) {
      throw new AuraHandledException(
        'Choose a record before saving an interaction.'
      );
    }

    if (String.isBlank(title)) {
      throw new AuraHandledException('Interaction title is required.');
    }

    if (interactionDate == null) {
      throw new AuraHandledException('Interaction date is required.');
    }

    if (String.isBlank(note)) {
      throw new AuraHandledException('Note is required.');
    }

    InteractionParent parent = resolveInteractionParent(parentRecordId);

    if (parent == null) {
      throw new AuraHandledException(
        'This record does not have a supported Lead or Contact relationship.'
      );
    }

    Interaction__c interactionRecord;

    if (interactionId == null) {
      interactionRecord = new Interaction__c();
      interactionRecord.put(parent.fieldApiName, parent.id);
    } else {
      interactionRecord = [
        SELECT Id, Contact__c, Lead__c
        FROM Interaction__c
        WHERE Id = :interactionId
        LIMIT 1
      ];

      if ((Id) interactionRecord.get(parent.fieldApiName) != parent.id) {
        throw new AuraHandledException(
          'This interaction does not belong to the current record.'
        );
      }
    }

    interactionRecord.Title__c = title.trim();
    interactionRecord.Note__c = note.trim();
    interactionRecord.Interaction_Date__c = interactionDate;

    upsert interactionRecord;

    Set<Id> finalTopicIds = new Set<Id>();

    if (topicIds != null) {
      finalTopicIds.addAll(topicIds);
    }

    finalTopicIds.addAll(createOrFindTopics(newTopicNames));

    replaceTopicLinks(interactionRecord.Id, finalTopicIds);

    return interactionRecord.Id;
  }

  private static InteractionParent resolveInteractionParent(Id recordId) {
    Schema.SObjectType objectType = recordId.getSObjectType();

    if (objectType == Contact.SObjectType) {
      return new InteractionParent(recordId, 'Contact__c');
    }

    if (objectType == Lead.SObjectType) {
      return new InteractionParent(recordId, 'Lead__c');
    }

    if (objectType == Account.SObjectType) {
      Id personContactId = resolvePersonAccountContactId(recordId);

      if (personContactId != null) {
        return new InteractionParent(personContactId, 'Contact__c');
      }

      return null;
    }

    Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
    Map<String, Schema.SObjectField> fieldsByName = objectDescribe.fields.getMap();

    List<String> candidateFields = new List<String>();
    candidateFields.addAll(LEAD_LOOKUP_FIELD_PRIORITY);
    candidateFields.addAll(CONTACT_LOOKUP_FIELD_PRIORITY);
    candidateFields.addAll(ACCOUNT_LOOKUP_FIELD_PRIORITY);

    List<String> queryFields = new List<String>();
    Set<String> addedQueryFields = new Set<String>();

    for (String fieldName : candidateFields) {
      if (
        fieldsByName.containsKey(fieldName) &&
        isSupportedParentLookup(fieldsByName.get(fieldName)) &&
        !addedQueryFields.contains(fieldName)
      ) {
        queryFields.add(fieldName);
        addedQueryFields.add(fieldName);
      }
    }

    if (queryFields.isEmpty()) {
      return null;
    }

    String queryText =
      'SELECT ' +
      String.join(queryFields, ', ') +
      ' FROM ' +
      objectDescribe.getName() +
      ' WHERE Id = :recordId LIMIT 1';

    List<SObject> records = Database.query(queryText);

    if (records.isEmpty()) {
      return null;
    }

    SObject sourceRecord = records[0];

    for (String fieldName : queryFields) {
      Id relatedRecordId = (Id) sourceRecord.get(fieldName);

      if (relatedRecordId == null) {
        continue;
      }

      Schema.SObjectType relatedType = relatedRecordId.getSObjectType();

      if (relatedType == Lead.SObjectType) {
        return new InteractionParent(relatedRecordId, 'Lead__c');
      }

      if (relatedType == Contact.SObjectType) {
        return new InteractionParent(relatedRecordId, 'Contact__c');
      }

      if (relatedType == Account.SObjectType) {
        Id personContactId = resolvePersonAccountContactId(relatedRecordId);

        if (personContactId != null) {
          return new InteractionParent(personContactId, 'Contact__c');
        }
      }
    }

    return null;
  }

  private static Id resolvePersonAccountContactId(Id accountId) {
    List<Account> accounts = [
      SELECT IsPersonAccount, PersonContactId
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];

    if (
      accounts.isEmpty() ||
      !accounts[0].IsPersonAccount ||
      accounts[0].PersonContactId == null
    ) {
      return null;
    }

    return accounts[0].PersonContactId;
  }

  private static Boolean isSupportedParentLookup(
    Schema.SObjectField fieldToken
  ) {
    Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();

    if (fieldDescribe.getType() != Schema.DisplayType.Reference) {
      return false;
    }

    List<Schema.SObjectType> referenceTypes = fieldDescribe.getReferenceTo();

    return referenceTypes.contains(Lead.SObjectType) ||
      referenceTypes.contains(Contact.SObjectType) ||
      referenceTypes.contains(Account.SObjectType);
  }

  private static Set<Id> createOrFindTopics(List<String> rawNames) {
    Set<String> normalizedNames = new Set<String>();
    Map<String, String> originalByNormalized = new Map<String, String>();

    if (rawNames != null) {
      for (String rawName : rawNames) {
        String topicName = rawName == null ? null : rawName.trim();

        if (String.isBlank(topicName)) {
          continue;
        }

        String normalized = topicName.toLowerCase();
        normalizedNames.add(normalized);

        if (!originalByNormalized.containsKey(normalized)) {
          originalByNormalized.put(normalized, topicName);
        }
      }
    }

    Set<Id> topicIds = new Set<Id>();

    if (normalizedNames.isEmpty()) {
      return topicIds;
    }

    List<String> topicNames = originalByNormalized.values();

    for (Topic__c existingTopic : [
      SELECT Id, Name, Active__c
      FROM Topic__c
      WHERE Name IN :topicNames
    ]) {
      String normalized = existingTopic.Name == null
        ? null
        : existingTopic.Name.toLowerCase();

      if (normalized != null && normalizedNames.contains(normalized)) {
        topicIds.add(existingTopic.Id);
        normalizedNames.remove(normalized);
      }
    }

    List<Topic__c> topicsToInsert = new List<Topic__c>();

    for (String normalized : normalizedNames) {
      topicsToInsert.add(
        new Topic__c(
          Name = originalByNormalized.get(normalized),
          Active__c = true
        )
      );
    }

    if (!topicsToInsert.isEmpty()) {
      insert topicsToInsert;

      for (Topic__c topic : topicsToInsert) {
        topicIds.add(topic.Id);
      }
    }

    return topicIds;
  }

  private static void replaceTopicLinks(Id interactionId, Set<Id> topicIds) {
    delete [
      SELECT Id
      FROM InteractionTopic__c
      WHERE Interaction__c = :interactionId
    ];

    List<InteractionTopic__c> linksToInsert = new List<InteractionTopic__c>();

    if (topicIds != null) {
      for (Id topicId : topicIds) {
        linksToInsert.add(
          new InteractionTopic__c(
            Interaction__c = interactionId,
            Topic__c = topicId
          )
        );
      }
    }

    if (!linksToInsert.isEmpty()) {
      insert linksToInsert;
    }
  }

  private static List<Map<String, Object>> buildRows(
    List<Interaction__c> interactions
  ) {
    List<Map<String, Object>> rows = new List<Map<String, Object>>();

    if (interactions.isEmpty()) {
      return rows;
    }

    Set<Id> interactionIds = new Set<Id>();

    for (Interaction__c interactionRecord : interactions) {
      interactionIds.add(interactionRecord.Id);
    }

    Map<Id, List<Map<String, Object>>> topicsByInteractionId = new Map<Id, List<Map<String, Object>>>();

    for (InteractionTopic__c link : [
      SELECT Interaction__c, Topic__c, Topic__r.Name, Topic__r.Active__c
      FROM InteractionTopic__c
      WHERE Interaction__c IN :interactionIds
      ORDER BY Topic__r.Name ASC
    ]) {
      if (!topicsByInteractionId.containsKey(link.Interaction__c)) {
        topicsByInteractionId.put(
          link.Interaction__c,
          new List<Map<String, Object>>()
        );
      }

      topicsByInteractionId.get(link.Interaction__c)
        .add(
          new Map<String, Object>{
            'id' => link.Topic__c,
            'name' => link.Topic__r.Name,
            'active' => link.Topic__r.Active__c
          }
        );
    }

    for (Interaction__c interactionRecord : interactions) {
      List<Map<String, Object>> topics = topicsByInteractionId.get(
        interactionRecord.Id
      );

      if (topics == null) {
        topics = new List<Map<String, Object>>();
      }

      List<Id> topicIds = new List<Id>();

      for (Map<String, Object> topic : topics) {
        topicIds.add((Id) topic.get('id'));
      }

      rows.add(
        new Map<String, Object>{
          'id' => interactionRecord.Id,
          'name' => interactionRecord.Name,
          'title' => interactionRecord.Title__c,
          'note' => interactionRecord.Note__c,
          'interactionDate' => interactionRecord.Interaction_Date__c,
          'createdDate' => interactionRecord.CreatedDate,
          'lastModifiedDate' => interactionRecord.LastModifiedDate,
          'createdByName' => interactionRecord.CreatedBy.Name,
          'lastModifiedByName' => interactionRecord.LastModifiedBy.Name,
          'topics' => topics,
          'topicIds' => topicIds
        }
      );
    }

    return rows;
  }

  // Safe to keep: this private helper never crosses the LWC/Apex boundary.
  private class InteractionParent {
    private Id id;
    private String fieldApiName;

    private InteractionParent(Id id, String fieldApiName) {
      this.id = id;
      this.fieldApiName = fieldApiName;
    }
  }
}
