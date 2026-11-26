LOCK TABLE scrapbook.files, scrapbook.storage_objects, scrapbook.photo_upload_receipts IN ACCESS EXCLUSIVE MODE;

DO $rollback$
DECLARE
    checkpoint jsonb := obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')::jsonb;
BEGIN
    IF checkpoint->>'generation' IS DISTINCT FROM 'f08-story-004-video-multipart'
        OR checkpoint->'signatures'->>'f08-story-004-video-multipart'
            IS DISTINCT FROM scrapbook.foundation_signature() THEN
        RAISE EXCEPTION 'Catálogo incompatível com a reversão do envio de vídeos em partes.';
    END IF;

    IF EXISTS (SELECT 1 FROM scrapbook.files WHERE multipart_checksums IS NOT NULL)
        OR EXISTS (SELECT 1 FROM scrapbook.storage_objects
            WHERE multipart_id IS NOT NULL OR receipt_event_kind = 'complete_multipart')
        OR EXISTS (SELECT 1 FROM scrapbook.photo_upload_receipts WHERE event_kind = 'complete_multipart') THEN
        RAISE EXCEPTION 'A reversão descartaria dados ou evidências de envio em partes.';
    END IF;
END;
$rollback$;

ALTER TABLE scrapbook.photo_upload_receipts
    DROP CONSTRAINT ck_photo_upload_receipts_kind,
    ADD CONSTRAINT ck_photo_upload_receipts_kind CHECK (event_kind = 'put');

ALTER TABLE scrapbook.files
    DROP CONSTRAINT ck_files_multipart_checksums,
    DROP COLUMN multipart_checksums;

SELECT scrapbook.checkpoint_catalog('f08-story-004-video-multipart', 'f08-story-002-photo-receipts', TRUE);
