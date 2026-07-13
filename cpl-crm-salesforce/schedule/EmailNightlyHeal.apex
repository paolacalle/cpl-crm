// Chron triggers a scheduled job or task at 
// exactly 2:00 AM every day 
System.schedule(
    'CPL Email Activity Nightly Heal', 
    '0 0 2 * * ?',
    new EmailActivityHealBatch()
);