ALTER TABLE scrapbook.sessions
    ADD CONSTRAINT fk_sessions_accounts_id
    FOREIGN KEY (sessions_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.account_operations
    ADD CONSTRAINT fk_account_operations_accounts_id
    FOREIGN KEY (account_operations_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.events
    ADD CONSTRAINT fk_events_creator_accounts_id
    FOREIGN KEY (events_creator_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.events
    ADD CONSTRAINT fk_events_covers_event_id
    FOREIGN KEY (id, events_covers_id)
    REFERENCES scrapbook.covers (covers_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.event_members
    ADD CONSTRAINT fk_event_members_events_id
    FOREIGN KEY (event_members_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.event_members
    ADD CONSTRAINT fk_event_members_accounts_id
    FOREIGN KEY (event_members_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.invitations
    ADD CONSTRAINT fk_invitations_events_id
    FOREIGN KEY (invitations_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.invitations
    ADD CONSTRAINT fk_invitations_event_members_event_id
    FOREIGN KEY (invitations_events_id, invitations_issuer_event_members_id)
    REFERENCES scrapbook.event_members (event_members_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.invitations
    ADD CONSTRAINT fk_invitations_recipient_accounts_id
    FOREIGN KEY (invitations_recipient_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.covers
    ADD CONSTRAINT fk_covers_events_id
    FOREIGN KEY (covers_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.opening_dispatches
    ADD CONSTRAINT fk_opening_dispatches_events_id
    FOREIGN KEY (opening_dispatches_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.opening_dispatches
    ADD CONSTRAINT fk_opening_dispatches_event_members_event_id
    FOREIGN KEY (opening_dispatches_events_id, opening_dispatches_event_members_id)
    REFERENCES scrapbook.event_members (event_members_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.records
    ADD CONSTRAINT fk_records_events_id
    FOREIGN KEY (records_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.records
    ADD CONSTRAINT fk_records_consent_notices_id
    FOREIGN KEY (records_consent_notices_id)
    REFERENCES scrapbook.consent_notices (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.idempotent_operations
    ADD CONSTRAINT fk_idempotent_operations_events_id
    FOREIGN KEY (idempotent_operations_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.idempotent_operations
    ADD CONSTRAINT fk_idempotent_operations_records_event_id
    FOREIGN KEY (idempotent_operations_events_id, idempotent_operations_records_id)
    REFERENCES scrapbook.records (records_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.upload_sessions
    ADD CONSTRAINT fk_upload_sessions_events_id
    FOREIGN KEY (upload_sessions_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.upload_sessions
    ADD CONSTRAINT fk_upload_sessions_records_event_id
    FOREIGN KEY (upload_sessions_events_id, upload_sessions_records_id)
    REFERENCES scrapbook.records (records_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.upload_sessions
    ADD CONSTRAINT fk_upload_sessions_idempotent_operations_event_id
    FOREIGN KEY (upload_sessions_events_id, upload_sessions_idempotent_operations_id)
    REFERENCES scrapbook.idempotent_operations (idempotent_operations_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.files
    ADD CONSTRAINT fk_files_records_id
    FOREIGN KEY (files_records_id)
    REFERENCES scrapbook.records (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.storage_objects
    ADD CONSTRAINT fk_storage_objects_files_id
    FOREIGN KEY (storage_objects_files_id)
    REFERENCES scrapbook.files (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.storage_objects
    ADD CONSTRAINT fk_storage_objects_processing_attempts_file_id
    FOREIGN KEY (storage_objects_files_id, storage_objects_processing_attempts_id)
    REFERENCES scrapbook.processing_attempts (processing_attempts_files_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.file_variants
    ADD CONSTRAINT fk_file_variants_files_id
    FOREIGN KEY (file_variants_files_id)
    REFERENCES scrapbook.files (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.file_variants
    ADD CONSTRAINT fk_file_variants_storage_objects_file_id
    FOREIGN KEY (file_variants_files_id, file_variants_storage_objects_id)
    REFERENCES scrapbook.storage_objects (storage_objects_files_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.processing_jobs
    ADD CONSTRAINT fk_processing_jobs_files_id
    FOREIGN KEY (processing_jobs_files_id)
    REFERENCES scrapbook.files (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.processing_attempts
    ADD CONSTRAINT fk_processing_attempts_processing_jobs_file_id
    FOREIGN KEY (processing_attempts_files_id, processing_attempts_processing_jobs_id)
    REFERENCES scrapbook.processing_jobs (processing_jobs_files_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.cleanup_jobs
    ADD CONSTRAINT fk_cleanup_jobs_storage_objects_id
    FOREIGN KEY (cleanup_jobs_storage_objects_id)
    REFERENCES scrapbook.storage_objects (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.notifications
    ADD CONSTRAINT fk_notifications_events_id
    FOREIGN KEY (notifications_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.notifications
    ADD CONSTRAINT fk_notifications_accounts_id
    FOREIGN KEY (notifications_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.notifications
    ADD CONSTRAINT fk_notifications_invitations_id
    FOREIGN KEY (notifications_events_id, notifications_invitations_id)
    REFERENCES scrapbook.invitations (invitations_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.notifications
    ADD CONSTRAINT fk_notifications_opening_dispatches_id
    FOREIGN KEY (notifications_events_id, notifications_opening_dispatches_id)
    REFERENCES scrapbook.opening_dispatches (opening_dispatches_events_id, id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.notification_attempts
    ADD CONSTRAINT fk_notification_attempts_notifications_id
    FOREIGN KEY (notification_attempts_notifications_id)
    REFERENCES scrapbook.notifications (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.audit_entries
    ADD CONSTRAINT fk_audit_entries_accounts_id
    FOREIGN KEY (audit_entries_accounts_id)
    REFERENCES scrapbook.accounts (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;

ALTER TABLE scrapbook.audit_entries
    ADD CONSTRAINT fk_audit_entries_events_id
    FOREIGN KEY (audit_entries_events_id)
    REFERENCES scrapbook.events (id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;
