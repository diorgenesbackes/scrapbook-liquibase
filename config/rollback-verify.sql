DO $rollback_verify$
BEGIN
    IF current_database() <> 'scrapbook_recovery'
        OR EXISTS (SELECT 1 FROM scrapbook.databasechangelog)
        OR EXISTS (SELECT 1 FROM scrapbook.databasechangeloglock WHERE locked)
        OR EXISTS (
            SELECT 1 FROM pg_catalog.pg_class AS relation
            JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid = relation.relnamespace
            WHERE namespace.nspname = 'scrapbook' AND relation.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
                AND relation.relname NOT IN ('databasechangelog', 'databasechangeloglock')
        )
        OR to_regprocedure('scrapbook.foundation_signature()') IS NOT NULL THEN
        RAISE EXCEPTION 'Recuperação inconclusiva: o catálogo ou o histórico não chegou ao estado inicial.';
    END IF;
END;
$rollback_verify$;
