LOCK TABLE scrapbook.events IN ACCESS EXCLUSIVE MODE;

DO $rollback$
BEGIN
    IF EXISTS (SELECT 1 FROM scrapbook.events WHERE creation_key_hash IS NOT NULL) THEN
        RAISE EXCEPTION 'A reversão descartaria chaves de criação de eventos.';
    END IF;
END;
$rollback$;

DROP INDEX scrapbook.uq_events_creation_key;

ALTER TABLE scrapbook.events
    DROP CONSTRAINT ck_events_creation_hashes,
    DROP COLUMN creation_payload_hash,
    DROP COLUMN creation_key_hash;

SELECT scrapbook.checkpoint_catalog('f03-story-001-event-creation', 'f01-story-001-base', TRUE);
