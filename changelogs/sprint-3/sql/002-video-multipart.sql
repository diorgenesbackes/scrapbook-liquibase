ALTER TABLE scrapbook.files
    ADD COLUMN multipart_checksums bytea[],
    ADD CONSTRAINT ck_files_multipart_checksums CHECK (
        multipart_checksums IS NULL
        OR (kind = 'video'
            AND array_ndims(multipart_checksums) = 1
            AND array_lower(multipart_checksums, 1) = 1
            AND cardinality(multipart_checksums) BETWEEN 2 AND 30
            AND CASE WHEN array_ndims(multipart_checksums) = 1
                THEN array_position(multipart_checksums, NULL::bytea) IS NULL
                ELSE FALSE END)
    );

ALTER TABLE scrapbook.photo_upload_receipts
    DROP CONSTRAINT ck_photo_upload_receipts_kind,
    ADD CONSTRAINT ck_photo_upload_receipts_kind CHECK (event_kind IN ('put', 'complete_multipart'));

SELECT scrapbook.checkpoint_catalog('f08-story-002-photo-receipts', 'f08-story-004-video-multipart');
