 # Scholar Finalist Materials Form Intake Plan

## Summary

Create a new Form_Submission__c intake path for Scholar Finalist Materials using the existing Wix/Zapier pattern. Applicants receive a tokenized
personalized form link, submit their own materials, and provide recommender names/emails. The system then auto-sends separate tokenized
recommendation links to each recommender. All uploaded files are stored as Salesforce Files and linked to the relevant Form Submission and Prospect
Scholar Application.

## Key Changes

    - Add Form_Submission__c record type: Scholar_Finalist_Materials.
    - Add one submission classifier picklist on Form_Submission__c: Material_Submission_Type__c with:
        - Applicant Materials
        - Coach/Professor Recommendation
        - Internship Supervisor Recommendation
    - Add Form_Submission__c fields:
        - Prospect_Scholar_Application__c lookup to Prospect_Scholar_Application__c
        - Submission_Token__c text, stores the submitted token for audit
        - Recommender_Name__c, Recommender_Email__c
        - Coach_Professor_Recommender_Name__c, Coach_Professor_Recommender_Email__c
        - Internship_Supervisor_Recommender_Name__c, Internship_Supervisor_Recommender_Email__c
        - Financial_Aid_Scholarship_Grant_Details__c long text
        - Finalist_Essay__c long text
        - Materials_Submission_Current__c checkbox
    - Add Prospect_Scholar_Application__c tracking fields:
        - Materials_Form_Token__c text, unique random token
        - Materials_Form_URL__c URL
        - Resume_Received__c, Essay_Received__c, Financial_Aid_Info_Received__c
        - Coach_Professor_Recommendation_Received__c
        - Internship_Supervisor_Recommendation_Received__c
        - Materials_Complete__c formula checkbox requiring resume, essay, and both recommendations; financial aid is optional

## Link And Form Flow
    - Update ScholarshipInviteEmailAction to include a personalized applicant form URL with applicationId and token.
    - Token generation happens before email send if Materials_Form_Token__c is blank.
    - Applicant Wix form fields:
        - hidden applicationId, hidden token
        - resume upload
        - financial aid/scholarship/grant details
        - finalist essay
        - coach/professor recommender name/email
        - internship supervisor recommender name/email
    - Zapier creates a Form_Submission__c record with record type Scholar_Finalist_Materials and Material_Submission_Type__c = Applicant Materials.
    - Zapier uploads applicant files as Salesforce ContentVersion records, then links resulting files to both the Form Submission and Prospect Scholar
    Application.
    - After a valid applicant submission, automation sends two recommender emails with tokenized form links:
        - one for Coach/Professor Recommendation
        - one for Internship Supervisor Recommendation
    - Recommender forms only collect recommender identity plus letter upload; Zapier creates Form_Submission__c records and Salesforce Files for each.

## Automation Behavior

    - Extend Form_Submission_Intake_Router with a third branch for Scholar_Finalist_Materials.
    - This branch must not create or update Leads.
    - It validates Prospect_Scholar_Application__c plus Submission_Token__c against the application token.
    - If invalid, set Needs_Review__c = true and Processing_Status__c = Needs Review.
    - If valid:
        - link the submission to the application
        - mark prior same-type material submissions for that application as not current
        - set the new submission as current
        - update received checkboxes on the application
        - keep all historical submissions for audit
    - Recommendation emails are sent automatically after the applicant-materials submission is valid and includes recommender emails.

## UI And Permissions

    - Add a Scholar Finalist Materials page layout for Form_Submission__c focused on application link, material type, recommender details, essay,
    financial aid details, file links, raw payload, and processing status.
    - Add the new Form Submission related list to the Prospect Scholar Application layout.
    - Add all new fields to PS_CRM_Admin; add read/edit access to program/admin permission sets that manage applications.
    - Keep source URLs in Raw_Payload__c for audit even though Salesforce Files are the system of record.

## Test Plan
    - token is generated once and reused on later sends
    - missing applicant email still errors as today
    - duplicate applicant submission replaces current marker while preserving old record
    - invalid token flags Needs Review
    - coach/professor recommendation updates only that received checkbox

## Assumptions

- V1 uses Wix forms plus Zapier for inbound record/file creation.
- Uploaded files are stored as Salesforce Files, not only external URLs.
- Recommenders submit separately via auto-sent personalized links.
- Duplicate submissions are allowed; newest valid submission of each material type becomes current.
- Financial aid/scholarship/grant details are optional and do not block Materials_Complete__c.