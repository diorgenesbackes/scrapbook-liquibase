SET LOCAL lock_timeout = '5s';

LOCK TABLE
    scrapbook.accounts,
    scrapbook.sessions,
    scrapbook.oidc_requests,
    scrapbook.account_operations,
    scrapbook.events,
    scrapbook.event_members,
    scrapbook.invitations,
    scrapbook.covers,
    scrapbook.opening_dispatches,
    scrapbook.consent_notices,
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
    scrapbook.processed_messages,
    scrapbook.audit_entries
IN ACCESS EXCLUSIVE MODE;

DO $rollback$
DECLARE
    table_name text;
    has_data boolean;
    catalog_hash text := scrapbook.foundation_signature();
BEGIN
    IF current_user <> 'scrapbook_owner'
        OR catalog_hash IS NULL
        OR obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')
            IS DISTINCT FROM 'f01-story-001-base:' || catalog_hash THEN
        RAISE EXCEPTION 'Rollback recusado: catálogo ou proveniência incompatível.';
    END IF;

    FOREACH table_name IN ARRAY ARRAY[
        'accounts', 'sessions', 'oidc_requests', 'account_operations', 'events', 'event_members', 'invitations', 'covers', 'opening_dispatches', 'consent_notices', 'records', 'idempotent_operations', 'upload_sessions', 'files', 'storage_objects', 'file_variants', 'processing_jobs', 'processing_attempts', 'cleanup_jobs', 'notifications', 'notification_attempts', 'outbox_messages', 'processed_messages', 'audit_entries'
    ]
    LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM scrapbook.%I)', table_name) INTO has_data;
        IF has_data THEN
            RAISE EXCEPTION 'Rollback recusado: a tabela scrapbook.% contém dados.', table_name;
        END IF;
    END LOOP;
END;
$rollback$;

DROP TABLE
    scrapbook.audit_entries,
    scrapbook.processed_messages,
    scrapbook.outbox_messages,
    scrapbook.notification_attempts,
    scrapbook.notifications,
    scrapbook.cleanup_jobs,
    scrapbook.processing_attempts,
    scrapbook.processing_jobs,
    scrapbook.file_variants,
    scrapbook.storage_objects,
    scrapbook.files,
    scrapbook.upload_sessions,
    scrapbook.idempotent_operations,
    scrapbook.records,
    scrapbook.consent_notices,
    scrapbook.opening_dispatches,
    scrapbook.covers,
    scrapbook.invitations,
    scrapbook.event_members,
    scrapbook.events,
    scrapbook.account_operations,
    scrapbook.oidc_requests,
    scrapbook.sessions,
    scrapbook.accounts
RESTRICT;

DROP FUNCTION scrapbook.checkpoint_catalog(text, text) RESTRICT;
DROP FUNCTION scrapbook.foundation_signature() RESTRICT;
