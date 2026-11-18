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
    protected_tables AS (
        SELECT c.oid, c.relname FROM pg_class AS c
        WHERE c.relnamespace = 'scrapbook'::regnamespace AND c.relkind = 'r'
          AND c.relname IN ('audit_entries', 'databasechangelog', 'databasechangeloglock')
    ),
    runtime_roles AS (
        SELECT login.role_name, candidate.oid
        FROM (VALUES ('scrapbook_app'::name), ('scrapbook_audit_reader'::name)) AS login(role_name)
        JOIN pg_roles AS candidate ON candidate.rolname = login.role_name
            OR pg_has_role(login.role_name, candidate.oid, 'SET')
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
        SELECT jsonb_build_array('column', r.relname,
            row_number() OVER (PARTITION BY r.oid ORDER BY a.attnum), a.attname,
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
        SELECT jsonb_build_array('sequence', r.relname, format_type(s.seqtypid, NULL),
            s.seqstart, s.seqincrement, s.seqmin, s.seqmax, s.seqcache, s.seqcycle)
        FROM relations AS r JOIN pg_sequence AS s ON s.seqrelid = r.oid
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
    FROM catalog_entries
    WHERE NOT EXISTS (
        SELECT 1 FROM runtime_roles AS runtime
        WHERE has_schema_privilege(runtime.oid, 'scrapbook', 'CREATE')
    ) AND NOT EXISTS (
        SELECT 1 FROM runtime_roles AS runtime CROSS JOIN protected_tables AS protected
        WHERE has_table_privilege(runtime.oid, protected.oid, 'DELETE, TRUNCATE, TRIGGER, MAINTAIN')
           OR has_any_column_privilege(runtime.oid, protected.oid, 'UPDATE, REFERENCES')
           OR ((protected.relname <> 'audit_entries' OR runtime.role_name = 'scrapbook_app')
               AND has_any_column_privilege(runtime.oid, protected.oid, 'SELECT'))
           OR ((protected.relname <> 'audit_entries' OR runtime.role_name = 'scrapbook_audit_reader')
               AND has_any_column_privilege(runtime.oid, protected.oid, 'INSERT'))
    );
$signature$;

CREATE FUNCTION scrapbook.checkpoint_catalog(expected_generation text, next_generation text, restoring boolean DEFAULT FALSE)
RETURNS void
LANGUAGE plpgsql
SET search_path TO pg_catalog
AS $checkpoint$
DECLARE
    checkpoint jsonb := COALESCE(
        obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')::jsonb,
        '{"signatures": {}}'::jsonb
    );
    catalog_hash text := scrapbook.foundation_signature();
    known_hash text := checkpoint->'signatures'->>next_generation;
BEGIN
    IF current_user <> 'scrapbook_owner'
        OR next_generation IS NULL OR next_generation !~ '^[a-z0-9][a-z0-9-]*$'
        OR restoring IS NULL
        OR expected_generation IS NOT DISTINCT FROM next_generation
        OR checkpoint->>'generation' IS DISTINCT FROM expected_generation
        OR jsonb_typeof(checkpoint->'signatures') IS DISTINCT FROM 'object'
        OR (expected_generation IS NOT NULL AND checkpoint->'signatures'->>expected_generation IS NULL) THEN
        RAISE EXCEPTION 'Transição de geração do catálogo incompatível.';
    END IF;

    IF catalog_hash IS NULL THEN
        RAISE EXCEPTION 'Privilégios efetivos incompatíveis com a matriz Scrap Book.';
    END IF;

    IF restoring AND known_hash IS NULL THEN
        RAISE EXCEPTION 'Assinatura da geração de destino indisponível.';
    END IF;

    IF known_hash IS NOT NULL AND known_hash <> catalog_hash THEN
        RAISE EXCEPTION 'Catálogo incompatível com a assinatura registrada da geração %.', next_generation;
    END IF;

    IF known_hash IS NULL THEN
        checkpoint := jsonb_set(checkpoint, ARRAY['signatures', next_generation], to_jsonb(catalog_hash));
    END IF;
    checkpoint := jsonb_set(checkpoint, '{generation}', to_jsonb(next_generation));

    EXECUTE format(
        'COMMENT ON FUNCTION scrapbook.foundation_signature() IS %L',
        checkpoint::text
    );
END;
$checkpoint$;

SELECT scrapbook.checkpoint_catalog(NULL, 'f01-story-001-base');
