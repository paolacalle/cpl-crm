Id jobId = Database.executeBatch(new ScholarApplicationStageBackfill(), 100);
System.debug('Scholarship stage/decision backfill: ' + jobId);
