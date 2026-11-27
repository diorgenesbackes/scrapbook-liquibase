LOCK TABLE scrapbook.processing_jobs, scrapbook.processing_attempts IN ACCESS EXCLUSIVE MODE;

DO $rollback$
DECLARE
    checkpoint jsonb := obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')::jsonb;
BEGIN
    IF checkpoint->>'generation' IS DISTINCT FROM 'f10-story-001-media-preparation'
        OR checkpoint->'signatures'->>'f10-story-001-media-preparation'
            IS DISTINCT FROM scrapbook.foundation_signature() THEN
        RAISE EXCEPTION 'Catálogo incompatível com a reversão da preparação de mídias.';
    END IF;

    IF EXISTS (SELECT 1 FROM scrapbook.processing_jobs
        WHERE confirmation_message_id IS NOT NULL OR retry_cycle <> 1)
        OR EXISTS (SELECT 1 FROM scrapbook.processing_attempts WHERE provider_submit_started_at IS NOT NULL) THEN
        RAISE EXCEPTION 'A reversão descartaria evidências da preparação de mídias.';
    END IF;
END;
$rollback$;

ALTER TABLE scrapbook.processing_attempts
    DROP CONSTRAINT ck_processing_attempts_provider_submit_started_at,
    DROP COLUMN provider_submit_started_at;

ALTER TABLE scrapbook.processing_jobs
    DROP CONSTRAINT ck_processing_jobs_confirmation,
    DROP COLUMN confirmation_message_id,
    DROP COLUMN confirmation_correlation_id,
    DROP COLUMN confirmed_at,
    DROP COLUMN retry_cycle;

SELECT scrapbook.checkpoint_catalog('f10-story-001-media-preparation', 'f08-story-004-video-multipart', TRUE);
