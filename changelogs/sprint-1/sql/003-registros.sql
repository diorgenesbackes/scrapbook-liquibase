CREATE TABLE scrapbook.consent_notices (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    code varchar(32) NOT NULL,
    body text NOT NULL,
    body_hash bytea NOT NULL,
    effective_at timestamptz NOT NULL,
    CONSTRAINT pk_consent_notices_id PRIMARY KEY (id),
    CONSTRAINT ck_consent_notices_content CHECK (btrim(code) <> '' AND btrim(body) <> '' AND octet_length(body_hash) = 32),
    CONSTRAINT uq_consent_notices_code UNIQUE (code)
);

CREATE INDEX ix_consent_notices_effective
    ON scrapbook.consent_notices (effective_at, id);

CREATE TABLE scrapbook.records (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    records_events_id bigint NOT NULL,
    records_consent_notices_id bigint NOT NULL,
    category varchar(16) NOT NULL,
    format varchar(8) NOT NULL,
    sender_name varchar(120),
    message varchar(5000),
    caption varchar(500),
    expected_file_count smallint NOT NULL,
    consented_at timestamp without time zone NOT NULL,
    submitted_at timestamp without time zone NOT NULL,
    received_at timestamp without time zone,
    confirmed_at timestamp without time zone,
    state varchar(24) NOT NULL,
    rejection_code varchar(80),
    redacted_at timestamptz,
    CONSTRAINT pk_records_id PRIMARY KEY (id),
    CONSTRAINT ck_records_version CHECK (version >= 0),
    CONSTRAINT ck_records_kind CHECK (
        category IN ('testimonial', 'moment')
            AND format IN ('photo', 'video', 'audio', 'text')
            AND (category <> 'moment' OR format IN ('photo', 'video'))
            AND expected_file_count BETWEEN 0
            AND 10
            AND CASE WHEN format = 'text' THEN expected_file_count = 0 WHEN category = 'moment'
            AND format = 'photo' THEN expected_file_count >= 1 ELSE expected_file_count = 1 END
    ),
    CONSTRAINT ck_records_content CHECK (
        redacted_at IS NOT NULL OR (nullif(btrim(sender_name), '') IS NOT NULL
            AND ((format = 'text'
            AND nullif(btrim(message), '') IS NOT NULL
            AND caption IS NULL) OR (format <> 'text'
            AND message IS NULL)))
    ),
    CONSTRAINT ck_records_confirmation CHECK (
        (state IN ('confirmed', 'processing', 'available', 'processing_failed')) = (confirmed_at IS NOT NULL)
            AND (confirmed_at IS NULL OR (received_at IS NOT NULL
            AND confirmed_at >= received_at))
            AND (received_at IS NULL OR received_at >= submitted_at)
    ),
    CONSTRAINT ck_records_redaction CHECK (redacted_at IS NULL OR (state = 'rejected' AND confirmed_at IS NULL)),
    CONSTRAINT ck_records_state CHECK (
        state IN ('receiving', 'validating', 'confirmed', 'processing', 'available', 'rejected', 'processing_failed')
            AND (state <> 'rejected' OR rejection_code IS NOT NULL)
    ),
    CONSTRAINT uq_records_event_scope UNIQUE (records_events_id, id)
);

CREATE INDEX ix_records_gallery
    ON scrapbook.records (records_events_id, received_at, id)
    WHERE confirmed_at IS NOT NULL;

CREATE INDEX ix_records_gallery_category
    ON scrapbook.records (records_events_id, category, received_at, id)
    WHERE confirmed_at IS NOT NULL;

CREATE INDEX ix_records_notice
    ON scrapbook.records (records_consent_notices_id);

CREATE TABLE scrapbook.idempotent_operations (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    idempotent_operations_events_id bigint NOT NULL,
    idempotent_operations_records_id bigint NOT NULL,
    operation varchar(40) NOT NULL,
    key uuid NOT NULL,
    payload_hash bytea,
    authorization_hash bytea,
    hash_key_id varchar(64),
    authorization_expires_at timestamptz NOT NULL,
    state varchar(24) NOT NULL,
    completed_at timestamptz,
    result_code varchar(80),
    retired_at timestamptz,
    CONSTRAINT pk_idempotent_operations_id PRIMARY KEY (id),
    CONSTRAINT ck_idempotent_operations_version CHECK (version >= 0),
    CONSTRAINT ck_idempotent_operations_state CHECK (
        state IN ('in_progress', 'confirmed', 'rejected', 'expired')
            AND (state = 'in_progress' OR completed_at IS NOT NULL)
            AND (state <> 'in_progress' OR retired_at IS NULL)
    ),
    CONSTRAINT ck_idempotent_operations_hashes CHECK (
        (retired_at IS NOT NULL OR num_nonnulls(payload_hash, authorization_hash, hash_key_id) = 3)
            AND (payload_hash IS NULL OR octet_length(payload_hash) = 32)
            AND (authorization_hash IS NULL OR octet_length(authorization_hash) = 32)
    ),
    CONSTRAINT uq_idempotent_operations_scope_key UNIQUE (idempotent_operations_events_id, operation, key),
    CONSTRAINT uq_idempotent_operations_record UNIQUE (idempotent_operations_records_id),
    CONSTRAINT uq_idempotent_operations_event_scope UNIQUE (idempotent_operations_events_id, id)
);

CREATE INDEX ix_idempotent_operations_retire
    ON scrapbook.idempotent_operations (authorization_expires_at, id)
    WHERE retired_at IS NULL;

CREATE TABLE scrapbook.upload_sessions (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    upload_sessions_events_id bigint NOT NULL,
    upload_sessions_records_id bigint NOT NULL,
    upload_sessions_idempotent_operations_id bigint NOT NULL,
    state varchar(24) NOT NULL,
    window_opens_at timestamp without time zone NOT NULL,
    window_closes_at timestamp without time zone NOT NULL,
    completion_deadline_at timestamp without time zone NOT NULL,
    started_at timestamp without time zone NOT NULL,
    lease_token uuid,
    lease_until timestamptz,
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sealed_at timestamptz,
    terminal_at timestamptz,
    last_error_code varchar(80),
    CONSTRAINT pk_upload_sessions_id PRIMARY KEY (id),
    CONSTRAINT ck_upload_sessions_version CHECK (version >= 0),
    CONSTRAINT ck_upload_sessions_window CHECK (
        window_opens_at <= started_at
            AND started_at < window_closes_at
            AND window_closes_at < completion_deadline_at
    ),
    CONSTRAINT ck_upload_sessions_state CHECK (
        state IN ('authorized', 'receiving', 'validating', 'confirmed', 'rejected', 'expired')
            AND (state NOT IN ('confirmed', 'rejected', 'expired') OR terminal_at IS NOT NULL)
    ),
    CONSTRAINT ck_upload_sessions_worker_lease CHECK ((lease_token IS NULL) = (lease_until IS NULL) AND attempt_count >= 0),
    CONSTRAINT uq_upload_sessions_record UNIQUE (upload_sessions_records_id),
    CONSTRAINT uq_upload_sessions_operation UNIQUE (upload_sessions_idempotent_operations_id)
);

CREATE INDEX ix_upload_sessions_event
    ON scrapbook.upload_sessions (upload_sessions_events_id, id);

CREATE INDEX ix_upload_sessions_deadline
    ON scrapbook.upload_sessions (completion_deadline_at, id)
    WHERE state IN ('authorized', 'receiving', 'validating');

CREATE INDEX ix_upload_sessions_worker_due
    ON scrapbook.upload_sessions (next_attempt_at, id)
    WHERE state IN ('authorized', 'receiving', 'validating');

CREATE TABLE scrapbook.files (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    files_records_id bigint NOT NULL,
    position smallint NOT NULL,
    client_key uuid NOT NULL,
    kind varchar(8) NOT NULL,
    declared_type varchar(128) NOT NULL,
    declared_size integer NOT NULL,
    actual_size bigint,
    media_type varchar(128),
    container varchar(32),
    video_codec varchar(64),
    audio_codec varchar(64),
    duration numeric(12,6),
    frame_rate_numerator integer,
    frame_rate_denominator integer,
    width integer,
    height integer,
    orientation smallint,
    rotation smallint,
    sha256 bytea,
    validation_state varchar(24) NOT NULL,
    processing_state varchar(24) NOT NULL,
    profile_version integer NOT NULL DEFAULT 1,
    received_at timestamp without time zone,
    validated_at timestamptz,
    confirmed_at timestamp without time zone,
    error_code varchar(80),
    CONSTRAINT pk_files_id PRIMARY KEY (id),
    CONSTRAINT ck_files_version CHECK (version >= 0),
    CONSTRAINT ck_files_kind CHECK (kind IN ('photo', 'video', 'audio') AND position BETWEEN 1 AND 10 AND profile_version >= 1),
    CONSTRAINT ck_files_size CHECK (
        declared_size BETWEEN 1
            AND CASE kind WHEN 'photo' THEN 20000000 WHEN 'video' THEN 500000000 ELSE 50000000 END
            AND (actual_size IS NULL OR actual_size >= 0)
            AND (validation_state <> 'valid' OR (actual_size IS NOT NULL
            AND actual_size = declared_size))
    ),
    CONSTRAINT ck_files_media CHECK (
        (kind <> 'photo' OR duration IS NULL)
            AND (duration IS NULL OR duration >= 0)
            AND (kind = 'photo' OR validation_state <> 'valid' OR duration > 0)
            AND (kind = 'photo' OR validation_state <> 'valid' OR duration IS NOT NULL)
    ),
    CONSTRAINT ck_files_validation CHECK (
        validation_state IN ('expected', 'receiving', 'received', 'validating', 'valid', 'rejected')
            AND processing_state IN ('not_requested', 'pending', 'processing', 'available', 'failed')
            AND (sha256 IS NULL OR octet_length(sha256) = 32)
            AND (validation_state <> 'valid' OR (num_nonnulls(media_type, container, received_at, validated_at, sha256) = 5
            AND (kind <> 'video' OR video_codec IS NOT NULL)
            AND (kind <> 'audio' OR audio_codec IS NOT NULL)))
    ),
    CONSTRAINT ck_files_dimensions CHECK (
        (width IS NULL OR width > 0)
            AND (height IS NULL OR height > 0)
            AND (orientation IS NULL OR orientation BETWEEN 1
            AND 8)
            AND (rotation IS NULL OR rotation IN (0, 90, 180, 270))
            AND (validation_state <> 'valid' OR kind = 'audio' OR (width IS NOT NULL
            AND height IS NOT NULL))
    ),
    CONSTRAINT ck_files_rate CHECK (
        (frame_rate_numerator IS NULL) = (frame_rate_denominator IS NULL)
            AND (frame_rate_numerator IS NULL OR (kind = 'video'
            AND frame_rate_numerator > 0
            AND frame_rate_denominator > 0))
            AND (kind <> 'video' OR validation_state <> 'valid' OR frame_rate_numerator IS NOT NULL)
    ),
    CONSTRAINT uq_files_record_position UNIQUE (files_records_id, position),
    CONSTRAINT uq_files_record_client UNIQUE (files_records_id, client_key)
);

CREATE INDEX ix_files_processing
    ON scrapbook.files (processing_state, id);

CREATE TABLE scrapbook.storage_objects (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    storage_objects_files_id bigint NOT NULL,
    storage_objects_processing_attempts_id bigint,
    kind varchar(16) NOT NULL,
    state varchar(24) NOT NULL,
    bucket varchar(63) NOT NULL,
    object_key text NOT NULL,
    version_id text,
    multipart_id text,
    etag text,
    size bigint,
    sha256 bytea,
    last_modified_at timestamptz,
    observed_at timestamptz,
    stored_at timestamptz,
    deleted_at timestamptz,
    CONSTRAINT pk_storage_objects_id PRIMARY KEY (id),
    CONSTRAINT ck_storage_objects_version CHECK (version >= 0),
    CONSTRAINT ck_storage_objects_state CHECK (
        kind IN ('temporary', 'original', 'derived')
            AND state IN ('planned', 'initializing', 'uploading', 'stored', 'deleting', 'deleted')
            AND (state <> 'stored' OR num_nonnulls(version_id, size, last_modified_at, observed_at, stored_at) = 5)
            AND (state <> 'deleted' OR deleted_at IS NOT NULL)
    ),
    CONSTRAINT ck_storage_objects_storage CHECK (
        bucket ~ '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$'
            AND octet_length(object_key) BETWEEN 1
            AND 1024
            AND (size IS NULL OR size > 0)
            AND (sha256 IS NULL OR octet_length(sha256) = 32)
    ),
    CONSTRAINT ck_storage_objects_origin CHECK ((kind = 'derived') = (storage_objects_processing_attempts_id IS NOT NULL)),
    CONSTRAINT uq_storage_objects_object_key UNIQUE (bucket, object_key),
    CONSTRAINT uq_storage_objects_file_scope UNIQUE (storage_objects_files_id, id)
);

CREATE UNIQUE INDEX uq_storage_objects_original
    ON scrapbook.storage_objects (storage_objects_files_id)
    WHERE kind = 'original' AND state <> 'deleted';

CREATE INDEX ix_storage_objects_attempt
    ON scrapbook.storage_objects (storage_objects_processing_attempts_id)
    WHERE storage_objects_processing_attempts_id IS NOT NULL;

CREATE TABLE scrapbook.file_variants (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    file_variants_files_id bigint NOT NULL,
    file_variants_storage_objects_id bigint,
    kind varchar(16) NOT NULL,
    profile_version integer NOT NULL,
    state varchar(24) NOT NULL,
    media_type varchar(128),
    container varchar(32),
    video_codec varchar(64),
    audio_codec varchar(64),
    width integer,
    height integer,
    duration numeric(12,6),
    frame_rate_numerator integer,
    frame_rate_denominator integer,
    location_removed boolean,
    ready_at timestamptz,
    error_code varchar(80),
    CONSTRAINT pk_file_variants_id PRIMARY KEY (id),
    CONSTRAINT ck_file_variants_version CHECK (version >= 0),
    CONSTRAINT ck_file_variants_state CHECK (
        kind IN ('image', 'thumbnail', 'playback')
            AND state IN ('pending', 'processing', 'ready', 'failed')
            AND profile_version >= 1
            AND (state <> 'ready' OR num_nonnulls(file_variants_storage_objects_id, ready_at) = 2)
    ),
    CONSTRAINT ck_file_variants_media CHECK ((width IS NULL OR width > 0) AND (height IS NULL OR height > 0) AND (duration IS NULL OR duration >= 0)),
    CONSTRAINT ck_file_variants_rate CHECK (
        (frame_rate_numerator IS NULL) = (frame_rate_denominator IS NULL)
            AND (frame_rate_numerator IS NULL OR (frame_rate_numerator > 0
            AND frame_rate_denominator > 0
            AND frame_rate_numerator::bigint <= 30 * frame_rate_denominator::bigint))
    ),
    CONSTRAINT uq_file_variants_file_kind_profile UNIQUE (file_variants_files_id, kind, profile_version)
);

CREATE INDEX ix_file_variants_object
    ON scrapbook.file_variants (file_variants_storage_objects_id)
    WHERE file_variants_storage_objects_id IS NOT NULL;

CREATE TABLE scrapbook.processing_jobs (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    processing_jobs_files_id bigint NOT NULL,
    kind varchar(24) NOT NULL,
    profile_version integer NOT NULL,
    profile jsonb NOT NULL,
    state varchar(24) NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL,
    completed_at timestamptz,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_processing_jobs_id PRIMARY KEY (id),
    CONSTRAINT ck_processing_jobs_version CHECK (version >= 0),
    CONSTRAINT ck_processing_jobs_state CHECK (
        kind IN ('photo_prepare', 'av_transcode')
            AND state IN ('pending', 'running', 'reconciling', 'completed', 'failed')
            AND profile_version >= 1
            AND attempt_count >= 0
            AND jsonb_typeof(profile) = 'object'
            AND (lease_token IS NULL) = (lease_until IS NULL)
    ),
    CONSTRAINT ck_processing_jobs_completion CHECK ((state IN ('completed', 'failed')) = (completed_at IS NOT NULL)),
    CONSTRAINT uq_processing_jobs_file_profile UNIQUE (processing_jobs_files_id, kind, profile_version),
    CONSTRAINT uq_processing_jobs_file_scope UNIQUE (processing_jobs_files_id, id)
);

CREATE INDEX ix_processing_jobs_eligible
    ON scrapbook.processing_jobs (next_attempt_at, id)
    WHERE state IN ('pending', 'reconciling', 'running');

CREATE TABLE scrapbook.processing_attempts (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    processing_attempts_processing_jobs_id bigint NOT NULL,
    processing_attempts_files_id bigint NOT NULL,
    number integer NOT NULL,
    request_key uuid NOT NULL,
    provider varchar(24) NOT NULL,
    provider_job_id text,
    provider_job_hash bytea,
    output_prefix text NOT NULL,
    state varchar(24) NOT NULL,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    error_code varchar(80),
    CONSTRAINT pk_processing_attempts_id PRIMARY KEY (id),
    CONSTRAINT ck_processing_attempts_version CHECK (version >= 0),
    CONSTRAINT ck_processing_attempts_state CHECK (
        provider IN ('local', 'mediaconvert')
            AND state IN ('created', 'submitted', 'running', 'succeeded', 'failed', 'unknown')
            AND number >= 1
            AND (state NOT IN ('succeeded', 'failed') OR finished_at IS NOT NULL)
            AND (finished_at IS NULL OR finished_at >= started_at)
    ),
    CONSTRAINT ck_processing_attempts_prefix CHECK (octet_length(output_prefix) BETWEEN 1 AND 1024 AND position('://' IN output_prefix) = 0),
    CONSTRAINT ck_processing_attempts_provider CHECK (
        (provider_job_id IS NULL) = (provider_job_hash IS NULL)
            AND (provider_job_hash IS NULL OR octet_length(provider_job_hash) = 32)
            AND (provider <> 'mediaconvert' OR state NOT IN ('submitted', 'running', 'succeeded') OR provider_job_id IS NOT NULL)
    ),
    CONSTRAINT uq_processing_attempts_job_number UNIQUE (processing_attempts_processing_jobs_id, number),
    CONSTRAINT uq_processing_attempts_request UNIQUE (request_key),
    CONSTRAINT uq_processing_attempts_file_scope UNIQUE (processing_attempts_files_id, id)
);

CREATE UNIQUE INDEX uq_processing_attempts_provider_job
    ON scrapbook.processing_attempts (provider, provider_job_hash)
    WHERE provider_job_hash IS NOT NULL;

CREATE UNIQUE INDEX uq_processing_attempts_active
    ON scrapbook.processing_attempts (processing_attempts_processing_jobs_id)
    WHERE state IN ('created', 'submitted', 'running', 'unknown');

CREATE TABLE scrapbook.cleanup_jobs (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    cleanup_jobs_storage_objects_id bigint NOT NULL,
    action varchar(24) NOT NULL,
    eligible_at timestamptz NOT NULL,
    state varchar(24) NOT NULL,
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL,
    completed_at timestamptz,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_cleanup_jobs_id PRIMARY KEY (id),
    CONSTRAINT ck_cleanup_jobs_version CHECK (version >= 0),
    CONSTRAINT ck_cleanup_jobs_state CHECK (
        action IN ('delete_object', 'abort_multipart')
            AND state IN ('pending', 'running', 'reconciling', 'completed', 'failed', 'blocked')
            AND attempt_count >= 0
            AND (lease_token IS NULL) = (lease_until IS NULL)
            AND (state <> 'completed' OR completed_at IS NOT NULL)
    ),
    CONSTRAINT uq_cleanup_jobs_object_action UNIQUE (cleanup_jobs_storage_objects_id, action)
);

CREATE INDEX ix_cleanup_jobs_eligible
    ON scrapbook.cleanup_jobs (next_attempt_at, id)
    WHERE state IN ('pending', 'running', 'reconciling');
