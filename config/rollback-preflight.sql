DO $rollback_preflight$
BEGIN
    IF current_database() <> 'scrapbook_recovery' OR session_user <> 'scrapbook_migrator'
        OR current_user <> 'scrapbook_owner'
        OR (SELECT count(*) FROM scrapbook.databasechangelog) <> 1
        OR NOT EXISTS (
            SELECT 1 FROM scrapbook.databasechangelog
            WHERE id = 'f01-story-001-base' AND author = 'scrapbook'
                AND filename = 'changelogs/sprint-1/changelog.yaml' AND exectype = 'EXECUTED'
        )
        OR EXISTS (SELECT 1 FROM scrapbook.databasechangeloglock WHERE locked) THEN
        RAISE EXCEPTION 'Recuperação recusada: alvo, histórico ou lock incompatível.';
    END IF;
END;
$rollback_preflight$;
