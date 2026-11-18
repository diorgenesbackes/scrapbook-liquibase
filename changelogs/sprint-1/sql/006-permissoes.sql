GRANT SELECT, INSERT, UPDATE ON TABLE
    scrapbook.accounts,
    scrapbook.sessions,
    scrapbook.oidc_requests,
    scrapbook.account_operations,
    scrapbook.events,
    scrapbook.invitations,
    scrapbook.covers,
    scrapbook.opening_dispatches,
    scrapbook.records,
    scrapbook.idempotent_operations,
    scrapbook.upload_sessions,
    scrapbook.files,
    scrapbook.storage_objects,
    scrapbook.file_variants,
    scrapbook.processing_jobs,
    scrapbook.processing_attempts,
    scrapbook.cleanup_jobs,
    scrapbook.notifications,
    scrapbook.notification_attempts,
    scrapbook.outbox_messages,
    scrapbook.processed_messages
TO scrapbook_app;

GRANT SELECT, INSERT ON TABLE
    scrapbook.event_members,
    scrapbook.consent_notices
TO scrapbook_app;

GRANT INSERT ON TABLE scrapbook.audit_entries TO scrapbook_app;

GRANT SELECT ON TABLE scrapbook.audit_entries TO scrapbook_audit_reader;
