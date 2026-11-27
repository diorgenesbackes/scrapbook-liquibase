ALTER TABLE scrapbook.processing_jobs
    ADD COLUMN confirmation_message_id uuid,
    ADD COLUMN confirmation_correlation_id uuid,
    ADD COLUMN confirmed_at timestamptz,
    ADD COLUMN retry_cycle integer NOT NULL DEFAULT 1,
    ADD CONSTRAINT ck_processing_jobs_confirmation CHECK (
        num_nonnulls(confirmation_message_id, confirmation_correlation_id, confirmed_at) IN (0, 3)
        AND retry_cycle >= 1
    );

ALTER TABLE scrapbook.processing_attempts
    ADD COLUMN provider_submit_started_at timestamptz,
    ADD CONSTRAINT ck_processing_attempts_provider_submit_started_at CHECK (
        provider_submit_started_at IS NULL
        OR (provider = 'mediaconvert' AND provider_submit_started_at >= started_at)
    );

SELECT scrapbook.checkpoint_catalog('f08-story-004-video-multipart', 'f10-story-001-media-preparation');
