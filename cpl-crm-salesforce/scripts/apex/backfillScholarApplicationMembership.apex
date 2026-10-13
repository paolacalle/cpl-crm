// Run once after deployment; then monitor the returned job in Setup > Apex Jobs.
// Recalculates the derived checkbox only. Does not change lifecycle or applications.
Id jobId = Database.executeBatch(new ScholarApplicationMembershipBackfill(), 100);
System.debug('Scholar application membership backfill job: ' + jobId);
