ALTER TABLE scrapbook.events
    ADD COLUMN creation_key_hash bytea,
    ADD COLUMN creation_payload_hash bytea,
    ADD CONSTRAINT ck_events_creation_hashes CHECK (
        (creation_key_hash IS NULL AND creation_payload_hash IS NULL)
        OR (creation_key_hash IS NOT NULL AND creation_payload_hash IS NOT NULL
            AND octet_length(creation_key_hash) = 32 AND octet_length(creation_payload_hash) = 32)
    );

CREATE UNIQUE INDEX uq_events_creation_key
    ON scrapbook.events (events_creator_accounts_id, creation_key_hash)
    WHERE creation_key_hash IS NOT NULL;

SELECT scrapbook.checkpoint_catalog('f01-story-001-base', 'f03-story-001-event-creation');
