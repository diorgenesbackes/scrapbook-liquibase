CREATE TABLE scrapbook.accounts (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    subject varchar(255),
    name varchar(120),
    email varchar(320),
    normalized_email varchar(320),
    email_verified boolean NOT NULL DEFAULT false,
    state varchar(32) NOT NULL,
    security_version bigint NOT NULL DEFAULT 0,
    synchronized_at timestamptz,
    CONSTRAINT pk_accounts_id PRIMARY KEY (id),
    CONSTRAINT ck_accounts_version CHECK (version >= 0),
    CONSTRAINT ck_accounts_state CHECK (state IN ('active', 'revocation_pending', 'disabled', 'anonymized') AND security_version >= 0),
    CONSTRAINT ck_accounts_profile CHECK (
        (state = 'anonymized'
            AND NOT email_verified) OR (state <> 'anonymized'
            AND nullif(btrim(subject), '') IS NOT NULL
            AND nullif(btrim(name), '') IS NOT NULL
            AND nullif(btrim(email), '') IS NOT NULL
            AND nullif(btrim(normalized_email), '') IS NOT NULL)
    ),
    CONSTRAINT uq_accounts_subject UNIQUE (subject),
    CONSTRAINT uq_accounts_normalized_email UNIQUE (normalized_email)
);

CREATE TABLE scrapbook.sessions (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    sessions_accounts_id bigint NOT NULL,
    token_hash bytea NOT NULL,
    hash_key_id varchar(64) NOT NULL,
    access_token_ciphertext bytea,
    refresh_token_ciphertext bytea,
    encryption_key_id varchar(64),
    account_security_version bigint NOT NULL,
    state varchar(32) NOT NULL,
    expires_at timestamptz NOT NULL,
    access_expires_at timestamptz NOT NULL,
    refresh_expires_at timestamptz,
    revoked_at timestamptz,
    revocation_reason varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_sessions_id PRIMARY KEY (id),
    CONSTRAINT ck_sessions_version CHECK (version >= 0),
    CONSTRAINT ck_sessions_lifetime CHECK (expires_at > created_at AND expires_at <= created_at + INTERVAL '168 hours'),
    CONSTRAINT ck_sessions_state CHECK (
        state IN ('active', 'refreshing', 'revoked', 'expired')
            AND (state <> 'revoked' OR revoked_at IS NOT NULL)
    ),
    CONSTRAINT ck_sessions_secrets CHECK (
        octet_length(token_hash) = 32
            AND account_security_version >= 0
            AND (lease_token IS NULL) = (lease_until IS NULL)
            AND (access_token_ciphertext IS NULL OR octet_length(access_token_ciphertext) > 0)
            AND (refresh_token_ciphertext IS NULL OR octet_length(refresh_token_ciphertext) > 0)
            AND (coalesce(access_token_ciphertext, refresh_token_ciphertext) IS NULL OR encryption_key_id IS NOT NULL)
            AND (state NOT IN ('active', 'refreshing') OR access_token_ciphertext IS NOT NULL)
    ),
    CONSTRAINT uq_sessions_token_hash UNIQUE (hash_key_id, token_hash)
);

CREATE INDEX ix_sessions_accounts_state
    ON scrapbook.sessions (sessions_accounts_id, state, id);

CREATE INDEX ix_sessions_expires_at
    ON scrapbook.sessions (expires_at, id);

CREATE TABLE scrapbook.oidc_requests (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    state_hash bytea NOT NULL,
    nonce_hash bytea NOT NULL,
    browser_hash bytea NOT NULL,
    hash_key_id varchar(64) NOT NULL,
    verifier_ciphertext bytea,
    encryption_key_id varchar(64),
    return_path varchar(2048) NOT NULL,
    state varchar(32) NOT NULL,
    expires_at timestamptz NOT NULL,
    completed_at timestamptz,
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_oidc_requests_id PRIMARY KEY (id),
    CONSTRAINT ck_oidc_requests_version CHECK (version >= 0),
    CONSTRAINT ck_oidc_requests_state CHECK (
        state IN ('pending', 'processing', 'completed', 'failed', 'expired')
            AND (state <> 'completed' OR completed_at IS NOT NULL)
    ),
    CONSTRAINT ck_oidc_requests_secrets CHECK (
        octet_length(state_hash) = 32
            AND octet_length(nonce_hash) = 32
            AND octet_length(browser_hash) = 32
            AND expires_at > created_at
            AND (lease_token IS NULL) = (lease_until IS NULL)
            AND (verifier_ciphertext IS NULL OR encryption_key_id IS NOT NULL)
    ),
    CONSTRAINT uq_oidc_requests_state_hash UNIQUE (hash_key_id, state_hash)
);

CREATE INDEX ix_oidc_requests_expires_at
    ON scrapbook.oidc_requests (expires_at, id);

CREATE TABLE scrapbook.account_operations (
    id bigint GENERATED ALWAYS AS IDENTITY,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    version bigint NOT NULL DEFAULT 0,
    account_operations_accounts_id bigint NOT NULL,
    request_key uuid NOT NULL,
    kind varchar(32) NOT NULL,
    state varchar(32) NOT NULL,
    target_name varchar(120),
    target_email_ciphertext bytea,
    encryption_key_id varchar(64),
    provider_reference text,
    applied_security_version bigint,
    attempt_count integer NOT NULL DEFAULT 0,
    next_attempt_at timestamptz,
    completed_at timestamptz,
    last_error_code varchar(80),
    lease_token uuid,
    lease_until timestamptz,
    CONSTRAINT pk_account_operations_id PRIMARY KEY (id),
    CONSTRAINT ck_account_operations_version CHECK (version >= 0),
    CONSTRAINT ck_account_operations_state CHECK (
        kind IN ('email_change', 'password_change', 'password_recovery', 'session_revocation', 'profile_sync')
            AND state IN ('pending', 'provider_pending', 'verification_pending', 'reconciling', 'completed', 'failed')
            AND attempt_count >= 0
            AND (state <> 'completed' OR completed_at IS NOT NULL)
            AND (lease_token IS NULL) = (lease_until IS NULL)
    ),
    CONSTRAINT ck_account_operations_encryption CHECK (target_email_ciphertext IS NULL OR encryption_key_id IS NOT NULL),
    CONSTRAINT uq_account_operations_request UNIQUE (account_operations_accounts_id, kind, request_key)
);

CREATE INDEX ix_account_operations_pending
    ON scrapbook.account_operations (next_attempt_at, id)
    WHERE state IN ('pending', 'provider_pending', 'reconciling');
