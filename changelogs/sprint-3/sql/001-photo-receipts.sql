ALTER TABLE scrapbook.upload_sessions
    ADD COLUMN request_correlation_id uuid;

ALTER TABLE scrapbook.storage_objects
    ADD COLUMN receipt_event_at timestamptz,
    ADD COLUMN receipt_event_kind varchar(32),
    ADD CONSTRAINT ck_storage_objects_receipt_event CHECK (
        (receipt_event_at IS NULL AND receipt_event_kind IS NULL)
        OR (receipt_event_at IS NOT NULL AND receipt_event_kind IS NOT NULL
            AND receipt_event_kind IN ('put', 'complete_multipart')
            AND kind = 'temporary' AND observed_at IS NOT NULL
            AND version_id IS NOT NULL AND btrim(version_id) NOT IN ('', 'null'))
    );

CREATE TABLE scrapbook.photo_upload_receipts (
    id bigint GENERATED ALWAYS AS IDENTITY,
    storage_object_id bigint NOT NULL,
    version_id text NOT NULL,
    received_at timestamptz NOT NULL,
    event_kind varchar(32) NOT NULL DEFAULT 'put',
    size bigint NOT NULL,
    cleanup_after timestamptz NOT NULL,
    deleted_at timestamptz,
    CONSTRAINT pk_photo_upload_receipts_id PRIMARY KEY (id),
    CONSTRAINT fk_photo_upload_receipts_storage_object_id_storage_objects_id
        FOREIGN KEY (storage_object_id) REFERENCES scrapbook.storage_objects (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_photo_upload_receipts_version CHECK (btrim(version_id) NOT IN ('', 'null')),
    CONSTRAINT ck_photo_upload_receipts_kind CHECK (event_kind = 'put'),
    CONSTRAINT ck_photo_upload_receipts_size CHECK (size >= 0),
    CONSTRAINT uq_photo_upload_receipts_version UNIQUE (storage_object_id, version_id)
);

CREATE INDEX ix_photo_upload_receipts_cleanup
    ON scrapbook.photo_upload_receipts (cleanup_after, id)
    WHERE deleted_at IS NULL;

GRANT SELECT, INSERT, UPDATE (deleted_at) ON TABLE scrapbook.photo_upload_receipts TO scrapbook_app;

SELECT scrapbook.checkpoint_catalog('f03-story-001-event-creation', 'f08-story-002-photo-receipts');
