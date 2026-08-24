public with sharing class LeadReviewApplicationNoteAction {
    private static final String REVIEW_TITLE = 'Lead Stage : Review of application';
    private static final List<String> REVIEW_TOPICS = new List<String>{
        'Automated Note',
        'New to Contacting',
        'Review of Initial Application',
        'Lead Stage'
    };

    @InvocableMethod(label='Save Lead Review Application Note')
    public static List<Result> saveNotes(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }

        for (Request request : requests) {
            if (request == null || request.leadId == null) {
                throw new AuraHandledException('Lead is required.');
            }
            if (String.isBlank(request.note)) {
                throw new AuraHandledException('Review note is required.');
            }

            Id interactionId = StructuredInteractionController.saveInteraction(
                null,
                request.leadId,
                REVIEW_TITLE,
                Date.today(),
                request.note,
                new List<Id>(),
                REVIEW_TOPICS
            );

            Result result = new Result();
            result.interactionId = interactionId;
            results.add(result);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable(required=true)
        public String note;
    }

    public class Result {
        @InvocableVariable
        public Id interactionId;
    }
}