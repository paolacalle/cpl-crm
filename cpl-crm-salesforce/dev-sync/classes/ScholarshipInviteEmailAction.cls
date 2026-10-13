public with sharing class ScholarshipInviteEmailAction {
    public class FlowException extends Exception {}

    public class Request {
        @InvocableVariable(required=true)
        public Id applicationId;
    }

    @InvocableMethod(label='Send Scholarship Invite Email' description='Sends the CPL Scholar finalist invite to the application applicant Person Account email.')
    public static void sendInvite(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> applicationIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.applicationId != null) {
                applicationIds.add(request.applicationId);
            }
        }

        if (applicationIds.isEmpty()) {
            throw new FlowException('No Prospect Scholar Application was provided.');
        }

        Map<Id, Prospect_Scholar_Application__c> applicationsById = new Map<Id, Prospect_Scholar_Application__c>([
            SELECT Id,
                   Applicant_Account__r.FirstName,
                   Applicant_Account__r.PersonEmail
            FROM Prospect_Scholar_Application__c
            WHERE Id IN :applicationIds
        ]);

        List<Messaging.SingleEmailMessage> messages = buildMessages(requests, applicationsById);

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages);
        }
    }

    @TestVisible
    private static List<Messaging.SingleEmailMessage> buildMessages(
        List<Request> requests,
        Map<Id, Prospect_Scholar_Application__c> applicationsById
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Request request : requests) {
            if (request == null || request.applicationId == null) {
                continue;
            }

            Prospect_Scholar_Application__c application = applicationsById.get(request.applicationId);
            if (application == null) {
                throw new FlowException('Prospect Scholar Application was not found.');
            }

            String recipientEmail = application.Applicant_Account__r == null
                ? null
                : application.Applicant_Account__r.PersonEmail;
            if (String.isBlank(recipientEmail)) {
                throw new FlowException('Applicant Person Account does not have a Person Email value.');
            }

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(new List<String>{ recipientEmail });
            message.setSubject('CPL Scholar Finalist Invitation');
            message.setHtmlBody(buildInviteBody(application.Applicant_Account__r.FirstName));
            message.setSaveAsActivity(false);
            messages.add(message);
        }

        return messages;
    }

    @TestVisible
    private static String buildInviteBody(String firstName) {
        String greetingName = String.isBlank(firstName) ? 'there' : firstName.escapeHtml4();
        return ''
            + '<p>' + greetingName + ',</p>'
            + '<p>I am so excited that you have decided that a career in Wealth Management as a Financial Advisor is your goal. '
            + 'I am also delighted to share that you have been selected as a <strong>CPL Scholar Finalist</strong>.</p>'
            + '<p>This recognition reflects both your accomplishments to date and your potential to contribute to a community of exceptional women who are committed to guiding, lifting, and inspiring one another throughout their careers.</p>'
            + '<p>To complete the review process, please provide the following in one consolidated email:</p>'
            + '<ul>'
            + '<li>Your most recent resume, including GPA, leadership activities, and athletic achievements</li>'
            + '<li>Two letters of recommendation: one from your coach or a college professor, and one from your summer internship supervisor</li>'
            + '<li>If applicable, a list of any financial aid, scholarships, or grants you are receiving or have received</li>'
            + '<li>A short essay describing your commitment to living out the CPL mantra, your aspirations for a career in wealth management, and any additional personal story you would like to share that will strengthen your application</li>'
            + '</ul>'
            + '<p>If you are selected as a CPL Scholar, you will receive a $10,000 scholarship/grant for your senior year. More importantly, you will gain lifelong access to a network of extraordinary women, and I will personally serve as your coach and mentor.</p>'
            + '<p>Together, we will build this community and continue our mission to change the face of wealth management and, by extension, the world.</p>'
            + '<p>Congratulations once again on being selected as a CPL Scholar Finalist. I cannot wait to see the impact you will make in this next chapter.</p>'
            + '<p>With pride and excitement,<br/>Lisa</p>';
    }
}