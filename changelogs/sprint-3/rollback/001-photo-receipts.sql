LOCK TABLE scrapbook.upload_sessions, scrapbook.storage_objects, scrapbook.photo_upload_receipts IN ACCESS EXCLUSIVE MODE;

DO $rollback$
DECLARE
    checkpoint jsonb := obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')::jsonb;
BEGIN
    IF checkpoint->>'generation' IS DISTINCT FROM 'f08-story-002-photo-receipts'
        OR checkpoint->'signatures'->>'f08-story-002-photo-receipts'
            IS DISTINCT FROM scrapbook.foundation_signature() THEN
        RAISE EXCEPTION 'Catálogo incompatível com a reversão da recepção de fotos.';
    END IF;

    IF EXISTS (SELECT 1 FROM scrapbook.photo_upload_receipts)
        OR EXISTS (SELECT 1 FROM scrapbook.storage_objects WHERE receipt_event_at IS NOT NULL)
        OR EXISTS (SELECT 1 FROM scrapbook.upload_sessions WHERE request_correlation_id IS NOT NULL) THEN
        RAISE EXCEPTION 'A reversão descartaria evidências de recepção ou correlação de fotos.';
    END IF;
END;
$rollback$;

DROP TABLE scrapbook.photo_upload_receipts RESTRICT;

ALTER TABLE scrapbook.storage_objects
    DROP CONSTRAINT ck_storage_objects_receipt_event,
    DROP COLUMN receipt_event_kind,
    DROP COLUMN receipt_event_at;

ALTER TABLE scrapbook.upload_sessions DROP COLUMN request_correlation_id;

SELECT scrapbook.checkpoint_catalog('f08-story-002-photo-receipts', 'f03-story-001-event-creation', TRUE);
