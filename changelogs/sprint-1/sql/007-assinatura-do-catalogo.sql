CREATE FUNCTION scrapbook.foundation_signature() RETURNS text
LANGUAGE SQL STABLE
SET search_path TO pg_catalog
AS $signature$
    WITH relations AS (
        SELECT c.*
        FROM pg_class AS c
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = 'scrapbook'
          AND c.relname NOT IN (
              'databasechangelog', 'databasechangeloglock', 'databasechangeloglock_pkey', 'pk_databasechangeloglock'
          )
    ),
    catalog_entries AS (
        SELECT jsonb_build_array('schema', nspname, pg_get_userbyid(nspowner), nspacl::text) AS entry
        FROM pg_namespace WHERE nspname = 'scrapbook'
        UNION ALL
        SELECT jsonb_build_array('relation', relname, relkind, pg_get_userbyid(relowner), relacl::text,
            relrowsecurity, relforcerowsecurity, relispartition,
            CASE WHEN relkind IN ('i', 'I') THEN pg_get_indexdef(oid) END)
        FROM relations
        UNION ALL
        SELECT jsonb_build_array('column', r.relname, a.attnum, a.attname,
            format_type(a.atttypid, a.atttypmod), a.attnotnull, a.attidentity,
            a.attgenerated, a.attacl::text, pg_get_expr(d.adbin, d.adrelid))
        FROM relations AS r
        JOIN pg_attribute AS a ON a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
        LEFT JOIN pg_attrdef AS d ON d.adrelid = r.oid AND d.adnum = a.attnum
        WHERE r.relkind = 'r'
        UNION ALL
        SELECT jsonb_build_array('constraint', r.relname, k.conname,
            pg_get_constraintdef(k.oid), k.convalidated)
        FROM relations AS r JOIN pg_constraint AS k ON k.conrelid = r.oid
        UNION ALL
        SELECT jsonb_build_array('index', r.relname, i.indisvalid, i.indisready)
        FROM relations AS r JOIN pg_index AS i ON i.indexrelid = r.oid
        UNION ALL
        SELECT jsonb_build_array('routine', p.proname, pg_get_function_identity_arguments(p.oid),
            p.prokind, pg_get_userbyid(p.proowner), p.proacl::text)
        FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'scrapbook'
        UNION ALL
        SELECT jsonb_build_array('trigger', r.relname, t.tgname, pg_get_triggerdef(t.oid), t.tgenabled)
        FROM relations AS r JOIN pg_trigger AS t ON t.tgrelid = r.oid
        WHERE NOT t.tgisinternal
        UNION ALL
        SELECT jsonb_build_array('policy', r.relname, p.polname, p.polcmd, p.polpermissive,
            p.polroles::text, pg_get_expr(p.polqual, p.polrelid), pg_get_expr(p.polwithcheck, p.polrelid))
        FROM relations AS r JOIN pg_policy AS p ON p.polrelid = r.oid
    )
    SELECT md5(string_agg(entry::text, E'\n' ORDER BY entry::text COLLATE "C"))
    FROM catalog_entries;
$signature$;

DO $checkpoint$
BEGIN
    EXECUTE format(
        'COMMENT ON FUNCTION scrapbook.foundation_signature() IS %L',
        'f01-baseline:' || scrapbook.foundation_signature()
    );
END;
$checkpoint$;
