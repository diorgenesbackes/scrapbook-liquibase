CREATE TABLE scrapbook.notifications (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    notifications_events_id bigint NOT NULL,
    notifications_accounts_id bigint,
    notifications_invitations_id bigint,
    notifications_opening_dispatches_id bigint,
    kind varchar(24) NOT NULL,
    request_key uuid,
    deduplication_key varchar(200) NOT NULL,
    template_version integer NOT NULL,
    access_version bigint,
    recipient_email_ciphertext bytea,
    recipient_hash bytea,
    hash_key_id varchar(64),
    encryption_key_id varchar(64),
    state varchar(24) NOT NULL,
    due_at timestamptz NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL,
    accepted_at timestamptz,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_notifications_id PRIMARY KEY (id),
    CONSTRAINT ck_notifications_version CHECK (version >= 0),
    CONSTRAINT ck_notifications_kind CHECK (
        (kind = 'event_invitation'
            AND notifications_invitations_id IS NOT NULL
            AND notifications_opening_dispatches_id IS NULL) OR (kind = 'event_opened'
            AND notifications_opening_dispatches_id IS NOT NULL
            AND notifications_accounts_id IS NOT NULL
            AND access_version IS NOT NULL
            AND access_version > 0
            AND notifications_invitations_id IS NULL)
    ),
    CONSTRAINT ck_notifications_state CHECK (
        state IN ('pending', 'running', 'reconciling', 'accepted', 'failed', 'cancelled')
            AND attempt_count >= 0
            AND template_version > 0
            AND (state <> 'accepted' OR accepted_at IS NOT NULL)
            AND (lease_token IS NULL) = (lease_until IS NULL)
    ),
    CONSTRAINT ck_notifications_recipient CHECK (
        (recipient_email_ciphertext IS NULL) = (encryption_key_id IS NULL)
            AND (recipient_hash IS NULL) = (hash_key_id IS NULL)
            AND (recipient_hash IS NULL OR octet_length(recipient_hash) = 32)
            AND (state NOT IN ('pending', 'running') OR recipient_email_ciphertext IS NOT NULL)
    ),
    CONSTRAINT ck_notifications_deduplication CHECK (
        (kind = 'event_invitation'
            AND request_key IS NOT NULL
            AND btrim(deduplication_key) <> '') OR (kind = 'event_opened'
            AND request_key IS NULL
            AND btrim(deduplication_key) <> '')
    ),
    CONSTRAINT uq_notifications_deduplication UNIQUE (deduplication_key)
);

CREATE INDEX ix_notifications_eligible
    ON scrapbook.notifications (next_attempt_at, id)
    WHERE state IN ('pending', 'running', 'reconciling');

CREATE INDEX ix_notifications_events
    ON scrapbook.notifications (notifications_events_id, id);

CREATE INDEX ix_notifications_accounts
    ON scrapbook.notifications (notifications_accounts_id)
    WHERE notifications_accounts_id IS NOT NULL;

CREATE INDEX ix_notifications_invitations
    ON scrapbook.notifications (notifications_events_id, notifications_invitations_id)
    WHERE notifications_invitations_id IS NOT NULL;

CREATE INDEX ix_notifications_opening
    ON scrapbook.notifications (notifications_events_id, notifications_opening_dispatches_id)
    WHERE notifications_opening_dispatches_id IS NOT NULL;

CREATE TABLE scrapbook.notification_attempts (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    notification_attempts_notifications_id bigint NOT NULL,
    number integer NOT NULL,
    request_key uuid NOT NULL,
    provider_message_id text,
    provider_message_hash bytea,
    recipient_email_ciphertext bytea,
    encryption_key_id varchar(64),
    state varchar(24) NOT NULL,
    delivery_state varchar(24),
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    feedback_at timestamptz,
    error_code varchar(80),
    CONSTRAINT pk_notification_attempts_id PRIMARY KEY (id),
    CONSTRAINT ck_notification_attempts_version CHECK (version >= 0),
    CONSTRAINT ck_notification_attempts_state CHECK (
        state IN ('prepared', 'submitting', 'accepted', 'failed', 'unknown')
            AND (delivery_state IS NULL OR delivery_state IN ('pending', 'delivered', 'bounced', 'complained'))
            AND number > 0
            AND (state <> 'accepted' OR num_nonnulls(provider_message_id, provider_message_hash, finished_at) = 3)
            AND (finished_at IS NULL OR finished_at >= started_at)
    ),
    CONSTRAINT ck_notification_attempts_provider CHECK (
        (provider_message_id IS NULL) = (provider_message_hash IS NULL)
            AND (provider_message_hash IS NULL OR octet_length(provider_message_hash) = 32)
            AND (recipient_email_ciphertext IS NULL) = (encryption_key_id IS NULL)
    ),
    CONSTRAINT uq_notification_attempts_number UNIQUE (notification_attempts_notifications_id, number),
    CONSTRAINT uq_notification_attempts_request UNIQUE (request_key)
);

CREATE UNIQUE INDEX uq_notification_attempts_provider
    ON scrapbook.notification_attempts (provider_message_hash)
    WHERE provider_message_hash IS NOT NULL;

CREATE UNIQUE INDEX uq_notification_attempts_active
    ON scrapbook.notification_attempts (notification_attempts_notifications_id)
    WHERE state IN ('prepared', 'submitting', 'unknown');

CREATE TABLE scrapbook.outbox_messages (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    message_id uuid NOT NULL,
    type varchar(100) NOT NULL,
    protocol_version smallint NOT NULL,
    aggregate_type varchar(64),
    aggregate_id bigint,
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid,
    trace_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    state varchar(24) NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    available_at timestamptz NOT NULL,
    published_at timestamptz,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_outbox_messages_id PRIMARY KEY (id),
    CONSTRAINT ck_outbox_messages_version CHECK (version >= 0),
    CONSTRAINT ck_outbox_messages_state CHECK (
        state IN ('pending', 'publishing', 'published', 'failed')
            AND attempt_count >= 0
            AND protocol_version > 0
            AND (state <> 'published' OR published_at IS NOT NULL)
            AND (aggregate_type IS NULL) = (aggregate_id IS NULL)
            AND (lease_token IS NULL) = (lease_until IS NULL)
    ),
    CONSTRAINT ck_outbox_messages_payload CHECK (
        jsonb_typeof(payload) = 'object'
            AND octet_length(payload::text) <= 16384
            AND jsonb_typeof(trace_context) = 'object'
    ),
    CONSTRAINT uq_outbox_messages_message UNIQUE (message_id)
);

CREATE INDEX ix_outbox_messages_eligible
    ON scrapbook.outbox_messages (available_at, id)
    WHERE state IN ('pending', 'publishing');

CREATE INDEX ix_outbox_messages_retention
    ON scrapbook.outbox_messages (published_at, id)
    WHERE state = 'published';

CREATE TABLE scrapbook.processed_messages (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    consumer varchar(80) NOT NULL,
    source varchar(32) NOT NULL,
    message_id uuid,
    external_id text,
    external_hash bytea,
    payload_hash bytea NOT NULL,
    correlation_id uuid,
    state varchar(24) NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    completed_at timestamptz,
    error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_processed_messages_id PRIMARY KEY (id),
    CONSTRAINT ck_processed_messages_version CHECK (version >= 0),
    CONSTRAINT ck_processed_messages_identity CHECK (
        num_nonnulls(message_id, external_id) = 1
            AND (external_id IS NULL) = (external_hash IS NULL)
            AND (external_hash IS NULL OR octet_length(external_hash) = 32)
            AND octet_length(payload_hash) = 32
            AND btrim(consumer) <> ''
            AND source IN ('internal', 's3', 'mediaconvert', 'ses', 'scheduler')
    ),
    CONSTRAINT ck_processed_messages_state CHECK (
        state IN ('processing', 'completed', 'quarantined')
            AND attempt_count >= 0
            AND (state <> 'completed' OR completed_at IS NOT NULL)
            AND (state <> 'quarantined' OR error_code IS NOT NULL)
            AND (lease_token IS NULL) = (lease_until IS NULL)
    )
);

CREATE UNIQUE INDEX uq_processed_messages_internal
    ON scrapbook.processed_messages (consumer, source, message_id)
    WHERE message_id IS NOT NULL;

CREATE UNIQUE INDEX uq_processed_messages_external
    ON scrapbook.processed_messages (consumer, source, external_hash)
    WHERE external_hash IS NOT NULL;

CREATE INDEX ix_processed_messages_lease
    ON scrapbook.processed_messages (lease_until, id)
    WHERE state = 'processing';

CREATE INDEX ix_processed_messages_retention
    ON scrapbook.processed_messages (completed_at, id)
    WHERE state = 'completed';

CREATE TABLE scrapbook.audit_entries (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    audit_entries_accounts_id bigint,
    audit_entries_events_id bigint,
    actor_type varchar(16) NOT NULL,
    action varchar(80) NOT NULL,
    subject_type varchar(64) NOT NULL,
    subject_id bigint,
    outcome varchar(16) NOT NULL,
    reason_code varchar(80),
    correlation_id uuid NOT NULL,
    before_state jsonb NOT NULL DEFAULT '{}'::jsonb,
    after_state jsonb NOT NULL DEFAULT '{}'::jsonb,
    expires_at timestamptz NOT NULL,
    area varchar(24) NOT NULL,
    CONSTRAINT pk_audit_entries_id PRIMARY KEY (id),
    CONSTRAINT ck_audit_entries_actor CHECK (
        actor_type IN ('account', 'guest', 'system')
            AND outcome IN ('success', 'rejected', 'failure')
            AND (actor_type = 'account') = (audit_entries_accounts_id IS NOT NULL)
            AND expires_at = created_at + INTERVAL '4320 hours'
    ),
    CONSTRAINT ck_audit_entries_payload CHECK (
        jsonb_typeof(before_state) = 'object'
            AND jsonb_typeof(after_state) = 'object'
            AND btrim(action) <> ''
            AND btrim(subject_type) <> ''
    ),
    CONSTRAINT ck_audit_entries_area CHECK (area IN ('identity', 'events', 'records', 'notifications'))
);

CREATE INDEX ix_audit_entries_accounts
    ON scrapbook.audit_entries (audit_entries_accounts_id, created_at, id)
    WHERE audit_entries_accounts_id IS NOT NULL;

CREATE INDEX ix_audit_entries_events
    ON scrapbook.audit_entries (audit_entries_events_id, created_at, id)
    WHERE audit_entries_events_id IS NOT NULL;

CREATE INDEX ix_audit_entries_retention
    ON scrapbook.audit_entries (expires_at, id);

CREATE INDEX ix_audit_entries_area_created_at_id
    ON scrapbook.audit_entries (area, created_at, id);
