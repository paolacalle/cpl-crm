@IsTest
private class StructuredInteractionControllerTest {
  private static Contact makeContact() {
    Contact contactRecord = new Contact(
      FirstName = 'Structured',
      LastName = 'Student'
    );
    insert contactRecord;
    return contactRecord;
  }

  private static Lead makeLead() {
    Lead leadRecord = new Lead(
      FirstName = 'Lead',
      LastName = 'Student',
      Company = 'CPL',
      Status = 'New'
    );
    insert leadRecord;
    return leadRecord;
  }

  private static Account makePersonAccount() {
    RecordType personAccountRecordType = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = 'cpl_applicant_account'
      LIMIT 1
    ];

    Account accountRecord = new Account(
      RecordTypeId = personAccountRecordType.Id,
      LastName = 'Person Student',
      PersonEmail = 'person.student@example.com'
    );
    insert accountRecord;

    return [
      SELECT Id, PersonContactId
      FROM Account
      WHERE Id = :accountRecord.Id
    ];
  }

  @IsTest
  static void savesContactInteractionWithExistingAndNewTopics() {
    Contact contactRecord = makeContact();

    Topic__c aid = new Topic__c(Name = 'Financial Aid', Active__c = true);
    insert aid;

    Test.startTest();

    Id interactionId = StructuredInteractionController.saveInteraction(
      null,
      contactRecord.Id,
      'FAFSA question',
      Date.today(),
      'Student asked about FAFSA.',
      new List<Id>{ aid.Id },
      new List<String>{ 'FAFSA' }
    );

    Test.stopTest();

    System.assertNotEquals(null, interactionId);

    Interaction__c interactionRecord = [
      SELECT Contact__c, Lead__c, Title__c, Note__c, Interaction_Date__c
      FROM Interaction__c
      WHERE Id = :interactionId
    ];

    System.assertEquals(contactRecord.Id, interactionRecord.Contact__c);

    System.assertEquals(null, interactionRecord.Lead__c);

    System.assertEquals('FAFSA question', interactionRecord.Title__c);

    System.assertEquals(
      'Student asked about FAFSA.',
      interactionRecord.Note__c
    );

    System.assertEquals(Date.today(), interactionRecord.Interaction_Date__c);

    List<InteractionTopic__c> links = [
      SELECT Topic__r.Name
      FROM InteractionTopic__c
      WHERE Interaction__c = :interactionId
      ORDER BY Topic__r.Name
    ];

    System.assertEquals(2, links.size());
    System.assertEquals('FAFSA', links[0].Topic__r.Name);
    System.assertEquals('Financial Aid', links[1].Topic__r.Name);
  }

  @IsTest
  static void returnsRowsAndFiltersByTopic() {
    Lead leadRecord = makeLead();

    Topic__c aid = new Topic__c(Name = 'Financial Aid', Active__c = true);

    Topic__c internship = new Topic__c(Name = 'Internship', Active__c = true);

    insert new List<Topic__c>{ aid, internship };

    Interaction__c aidInteraction = new Interaction__c(
      Lead__c = leadRecord.Id,
      Title__c = 'FAFSA question',
      Interaction_Date__c = Date.today().addDays(-1),
      Note__c = 'Asked about FAFSA.'
    );

    Interaction__c internshipInteraction = new Interaction__c(
      Lead__c = leadRecord.Id,
      Title__c = 'Internship application',
      Interaction_Date__c = Date.today(),
      Note__c = 'Discussed internship.'
    );

    insert new List<Interaction__c>{ aidInteraction, internshipInteraction };

    insert new List<InteractionTopic__c>{
      new InteractionTopic__c(
        Interaction__c = aidInteraction.Id,
        Topic__c = aid.Id
      ),
      new InteractionTopic__c(
        Interaction__c = internshipInteraction.Id,
        Topic__c = internship.Id
      )
    };

    List<Map<String, Object>> allRows = StructuredInteractionController.getInteractions(
      leadRecord.Id,
      null,
      null,
      null,
      null
    );

    System.assertEquals(2, allRows.size());

    System.assertEquals(
      'Discussed internship.',
      (String) allRows[0].get('note')
    );

    List<Map<String, Object>> filteredRows = StructuredInteractionController.getInteractions(
      leadRecord.Id,
      aid.Id,
      null,
      null,
      null
    );

    System.assertEquals(1, filteredRows.size());

    System.assertEquals(
      'Asked about FAFSA.',
      (String) filteredRows[0].get('note')
    );

    List<Object> topics = (List<Object>) filteredRows[0].get('topics');

    Map<String, Object> firstTopic = (Map<String, Object>) topics[0];

    System.assertEquals('Financial Aid', (String) firstTopic.get('name'));

    List<Map<String, Object>> titleAndDateRows = StructuredInteractionController.getInteractions(
      leadRecord.Id,
      null,
      'internship',
      Date.today(),
      Date.today()
    );

    System.assertEquals(1, titleAndDateRows.size());

    System.assertEquals(
      'Internship application',
      (String) titleAndDateRows[0].get('title')
    );
  }

  @IsTest
  static void savesInteractionFromRecordWithLeadLookup() {
    Lead leadRecord = makeLead();

    Task taskRecord = new Task(
      WhoId = leadRecord.Id,
      Subject = 'Follow up with student',
      Status = 'Not Started'
    );
    insert taskRecord;

    Id interactionId = StructuredInteractionController.saveInteraction(
      null,
      taskRecord.Id,
      'Task follow-up',
      Date.today(),
      'Logged from a related task page.',
      null,
      null
    );

    System.assertNotEquals(null, interactionId);

    Interaction__c interactionRecord = [
      SELECT Lead__c, Contact__c, Note__c
      FROM Interaction__c
      WHERE Id = :interactionId
    ];

    System.assertEquals(leadRecord.Id, interactionRecord.Lead__c);

    System.assertEquals(null, interactionRecord.Contact__c);

    List<Map<String, Object>> taskRows = StructuredInteractionController.getInteractions(
      taskRecord.Id,
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, taskRows.size());

    System.assertEquals(
      'Logged from a related task page.',
      (String) taskRows[0].get('note')
    );
  }

  @IsTest
  static void savesPersonAccountInteractionAgainstPersonContact() {
    Account personAccount = makePersonAccount();

    Id interactionId = StructuredInteractionController.saveInteraction(
      null,
      personAccount.Id,
      'Person account note',
      Date.today(),
      'Logged from the Person Account page.',
      null,
      null
    );

    Interaction__c interactionRecord = [
      SELECT Contact__c, Lead__c, Note__c
      FROM Interaction__c
      WHERE Id = :interactionId
    ];

    System.assertEquals(
      personAccount.PersonContactId,
      interactionRecord.Contact__c
    );

    System.assertEquals(null, interactionRecord.Lead__c);

    List<Map<String, Object>> accountRows = StructuredInteractionController.getInteractions(
      personAccount.Id,
      null,
      null,
      null,
      null
    );

    System.assertEquals(1, accountRows.size());

    System.assertEquals(
      'Logged from the Person Account page.',
      (String) accountRows[0].get('note')
    );
  }

  @IsTest
  static void updatesInteractionAndReplacesTopics() {
    Contact contactRecord = makeContact();

    Topic__c oldTopic = new Topic__c(Name = 'Old Topic', Active__c = true);

    Topic__c newTopic = new Topic__c(Name = 'New Topic', Active__c = true);

    insert new List<Topic__c>{ oldTopic, newTopic };

    Interaction__c interactionRecord = new Interaction__c(
      Contact__c = contactRecord.Id,
      Title__c = 'Original title',
      Interaction_Date__c = Date.today().addDays(-2),
      Note__c = 'Original note'
    );
    insert interactionRecord;

    insert new InteractionTopic__c(
      Interaction__c = interactionRecord.Id,
      Topic__c = oldTopic.Id
    );

    Id returnedInteractionId = StructuredInteractionController.saveInteraction(
      interactionRecord.Id,
      contactRecord.Id,
      'Updated title',
      Date.today(),
      'Updated note',
      new List<Id>{ newTopic.Id },
      null
    );

    System.assertEquals(interactionRecord.Id, returnedInteractionId);

    Interaction__c updated = [
      SELECT Note__c, Title__c, Interaction_Date__c
      FROM Interaction__c
      WHERE Id = :interactionRecord.Id
    ];

    System.assertEquals('Updated title', updated.Title__c);

    System.assertEquals('Updated note', updated.Note__c);

    System.assertEquals(Date.today(), updated.Interaction_Date__c);

    List<InteractionTopic__c> links = [
      SELECT Topic__c
      FROM InteractionTopic__c
      WHERE Interaction__c = :interactionRecord.Id
    ];

    System.assertEquals(1, links.size());

    System.assertEquals(newTopic.Id, links[0].Topic__c);
  }

  @IsTest
  static void activeTopicsExcludesRetiredTopics() {
    insert new List<Topic__c>{
      new Topic__c(Name = 'Active Topic', Active__c = true),
      new Topic__c(Name = 'Retired Topic', Active__c = false)
    };

    List<Map<String, Object>> topics = StructuredInteractionController.getActiveTopics();

    System.assertEquals(1, topics.size());

    System.assertEquals('Active Topic', (String) topics[0].get('name'));

    System.assertEquals(true, (Boolean) topics[0].get('active'));
  }

  @IsTest
  static void rejectsUnsupportedParentRecords() {
    List<Map<String, Object>> rows = StructuredInteractionController.getInteractions(
      UserInfo.getUserId(),
      null,
      null,
      null,
      null
    );

    System.assertEquals(0, rows.size());

    try {
      StructuredInteractionController.saveInteraction(
        null,
        UserInfo.getUserId(),
        'Unsupported',
        Date.today(),
        'Nope',
        null,
        null
      );

      System.assert(false, 'Expected unsupported parent error.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void rejectsMissingParentRecord() {
    try {
      StructuredInteractionController.saveInteraction(
        null,
        null,
        'Missing parent',
        Date.today(),
        'Test note',
        null,
        null
      );

      System.assert(false, 'Expected missing parent record error.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void rejectsBlankTitle() {
    Contact contactRecord = makeContact();

    try {
      StructuredInteractionController.saveInteraction(
        null,
        contactRecord.Id,
        '',
        Date.today(),
        'Test note',
        null,
        null
      );

      System.assert(false, 'Expected blank title error.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void rejectsMissingInteractionDate() {
    Contact contactRecord = makeContact();

    try {
      StructuredInteractionController.saveInteraction(
        null,
        contactRecord.Id,
        'Missing date',
        null,
        'Test note',
        null,
        null
      );

      System.assert(false, 'Expected interaction date error.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }

  @IsTest
  static void rejectsBlankNote() {
    Contact contactRecord = makeContact();

    try {
      StructuredInteractionController.saveInteraction(
        null,
        contactRecord.Id,
        'Blank note',
        Date.today(),
        '',
        null,
        null
      );

      System.assert(false, 'Expected blank note error.');
    } catch (AuraHandledException expected) {
      System.assertNotEquals(null, expected);
    }
  }
}
