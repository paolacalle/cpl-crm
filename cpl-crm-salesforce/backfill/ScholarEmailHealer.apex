
Id jobId = Database.executeBatch(new EmailActivityHealBatch(), 100);
System.debug('Backfill batch job: ' + jobId);