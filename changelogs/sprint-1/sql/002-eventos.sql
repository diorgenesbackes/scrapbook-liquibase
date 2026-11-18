CREATE TABLE scrapbook.events (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    events_creator_accounts_id bigint NOT NULL,
    events_covers_id bigint,
    code varchar(43) NOT NULL,
    name varchar(120) NOT NULL,
    welcome_message varchar(2000),
    starts_at timestamp without time zone NOT NULL,
    submission_opens_at timestamp without time zone NOT NULL,
    submission_closes_at timestamp without time zone NOT NULL,
    completion_deadline_at timestamp without time zone NOT NULL,
    opening_mode varchar(16) NOT NULL,
    opens_at timestamp without time zone,
    access_state varchar(24) NOT NULL,
    access_frozen_at timestamp without time zone,
    access_version bigint NOT NULL DEFAULT 1,
    locked_at timestamptz,
    first_record_id bigint,
    first_record_confirmed_at timestamp without time zone,
    CONSTRAINT pk_events_id PRIMARY KEY (id),
    CONSTRAINT ck_events_version CHECK (version >= 0),
    CONSTRAINT ck_events_name CHECK (btrim(name) <> '' AND code ~ '^[A-Za-z0-9_-]{43}$'),
    CONSTRAINT ck_events_window CHECK (submission_opens_at < submission_closes_at AND submission_closes_at < completion_deadline_at),
    CONSTRAINT ck_events_opening CHECK (
        opening_mode IN ('immediate', 'scheduled')
            AND ((opening_mode = 'scheduled'
            AND opens_at IS NOT NULL
            AND opens_at > submission_closes_at) OR (opening_mode = 'immediate'
            AND opens_at IS NULL))
            AND access_state IN ('flexible', 'scheduled_locked', 'immediate_once')
            AND (access_state <> 'scheduled_locked' OR opening_mode = 'scheduled')
            AND (access_state <> 'immediate_once' OR opening_mode = 'immediate')
            AND (access_state = 'flexible' OR access_frozen_at IS NOT NULL)
            AND access_version >= 1
    ),
    CONSTRAINT ck_events_locking CHECK (num_nonnulls(locked_at, first_record_id, first_record_confirmed_at) IN (0, 3) AND first_record_id > 0),
    CONSTRAINT uq_events_code UNIQUE (code)
);

CREATE INDEX ix_events_creator
    ON scrapbook.events (events_creator_accounts_id, id);

CREATE INDEX ix_events_opening
    ON scrapbook.events (opens_at, id)
    WHERE opening_mode = 'scheduled';

CREATE TABLE scrapbook.event_members (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    event_members_events_id bigint NOT NULL,
    event_members_accounts_id bigint NOT NULL,
    slot smallint NOT NULL,
    joined_at timestamptz NOT NULL,
    CONSTRAINT pk_event_members_id PRIMARY KEY (id),
    CONSTRAINT ck_event_members_slot CHECK (slot IN (1, 2)),
    CONSTRAINT uq_event_members_event_slot UNIQUE (event_members_events_id, slot),
    CONSTRAINT uq_event_members_event_account UNIQUE (event_members_events_id, event_members_accounts_id),
    CONSTRAINT uq_event_members_event_scope UNIQUE (event_members_events_id, id)
);

CREATE INDEX ix_event_members_account_events
    ON scrapbook.event_members (event_members_accounts_id, event_members_events_id);

CREATE TABLE scrapbook.invitations (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    invitations_events_id bigint NOT NULL,
    invitations_issuer_event_members_id bigint NOT NULL,
    invitations_recipient_accounts_id bigint,
    request_key uuid NOT NULL,
    token_hash bytea NOT NULL,
    hash_key_id varchar(64) NOT NULL,
    token_ciphertext bytea,
    encryption_key_id varchar(64),
    state varchar(24) NOT NULL,
    expires_at timestamptz NOT NULL,
    accepted_at timestamptz,
    invalidated_at timestamptz,
    CONSTRAINT pk_invitations_id PRIMARY KEY (id),
    CONSTRAINT ck_invitations_version CHECK (version >= 0),
    CONSTRAINT ck_invitations_state CHECK (
        state IN ('pending', 'accepted', 'superseded', 'invalidated', 'expired')
            AND (state = 'accepted') = (invitations_recipient_accounts_id IS NOT NULL)
            AND (state = 'accepted') = (accepted_at IS NOT NULL)
    ),
    CONSTRAINT ck_invitations_lifetime CHECK (expires_at > created_at AND accepted_at < expires_at),
    CONSTRAINT ck_invitations_secrets CHECK (
        octet_length(token_hash) = 32
            AND (token_ciphertext IS NULL OR encryption_key_id IS NOT NULL)
            AND (state <> 'pending' OR token_ciphertext IS NOT NULL)
    ),
    CONSTRAINT uq_invitations_request UNIQUE (invitations_events_id, request_key),
    CONSTRAINT uq_invitations_token_hash UNIQUE (hash_key_id, token_hash),
    CONSTRAINT uq_invitations_event_scope UNIQUE (invitations_events_id, id)
);

CREATE UNIQUE INDEX uq_invitations_active
    ON scrapbook.invitations (invitations_events_id)
    WHERE state = 'pending';

CREATE INDEX ix_invitations_expires_at
    ON scrapbook.invitations (expires_at, id);

CREATE INDEX ix_invitations_issuer
    ON scrapbook.invitations (invitations_issuer_event_members_id);

CREATE INDEX ix_invitations_recipient
    ON scrapbook.invitations (invitations_recipient_accounts_id)
    WHERE invitations_recipient_accounts_id IS NOT NULL;

CREATE TABLE scrapbook.covers (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    covers_events_id bigint NOT NULL,
    state varchar(24) NOT NULL,
    bucket varchar(63) NOT NULL,
    object_key text NOT NULL,
    version_id text,
    temporary_key text,
    temporary_version_id text,
    declared_size integer NOT NULL,
    actual_size bigint,
    media_type varchar(128),
    width integer,
    height integer,
    sha256 bytea,
    received_at timestamptz,
    ready_at timestamptz,
    cleanup_after timestamptz,
    deleted_at timestamptz,
    attempt_count integer NOT NULL DEFAULT 0,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_covers_id PRIMARY KEY (id),
    CONSTRAINT ck_covers_version CHECK (version >= 0),
    CONSTRAINT ck_covers_state CHECK (
        state IN ('pending', 'validating', 'ready', 'superseded', 'rejected', 'deleting', 'deleted')
            AND (state <> 'ready' OR num_nonnulls(version_id, actual_size, media_type, width, height, ready_at) = 6)
            AND (state <> 'deleted' OR deleted_at IS NOT NULL)
            AND attempt_count >= 0
    ),
    CONSTRAINT ck_covers_size CHECK (
        declared_size BETWEEN 1
            AND 20000000
            AND (actual_size IS NULL OR actual_size >= 0)
            AND (state <> 'ready' OR actual_size BETWEEN 1
            AND 20000000)
            AND width > 0
            AND height > 0
            AND octet_length(sha256) = 32
    ),
    CONSTRAINT ck_covers_storage CHECK (
        bucket ~ '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$'
            AND octet_length(object_key) BETWEEN 1
            AND 1024
            AND (temporary_key IS NULL OR octet_length(temporary_key) BETWEEN 1
            AND 1024)
            AND (lease_token IS NULL) = (lease_until IS NULL)
    ),
    CONSTRAINT uq_covers_event_scope UNIQUE (covers_events_id, id),
    CONSTRAINT uq_covers_object_key UNIQUE (bucket, object_key)
);

CREATE INDEX ix_covers_cleanup
    ON scrapbook.covers (cleanup_after, id)
    WHERE state IN ('superseded', 'rejected', 'deleting');

CREATE TABLE scrapbook.opening_dispatches (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    opening_dispatches_events_id bigint NOT NULL,
    opening_dispatches_event_members_id bigint NOT NULL,
    access_version bigint NOT NULL,
    due_at timestamp without time zone NOT NULL,
    state varchar(24) NOT NULL,
    requested_at timestamptz,
    dispatched_at timestamptz,
    CONSTRAINT pk_opening_dispatches_id PRIMARY KEY (id),
    CONSTRAINT ck_opening_dispatches_version CHECK (version >= 0),
    CONSTRAINT ck_opening_dispatches_state CHECK (
        state IN ('pending', 'requested', 'dispatched', 'cancelled')
            AND access_version >= 1
            AND (state NOT IN ('requested', 'dispatched') OR requested_at IS NOT NULL)
            AND (state <> 'dispatched' OR dispatched_at IS NOT NULL)
    ),
    CONSTRAINT uq_opening_dispatches_recipient_version UNIQUE (opening_dispatches_events_id, opening_dispatches_event_members_id, access_version),
    CONSTRAINT uq_opening_dispatches_event_scope UNIQUE (opening_dispatches_events_id, id)
);

CREATE INDEX ix_opening_dispatches_member
    ON scrapbook.opening_dispatches (opening_dispatches_event_members_id);

CREATE INDEX ix_opening_dispatches_due
    ON scrapbook.opening_dispatches (due_at, id)
    WHERE state IN ('pending', 'requested');
