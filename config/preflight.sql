DO $preflight$
DECLARE
    owner_oid oid := to_regrole('scrapbook_owner');
    schema_oid oid := to_regnamespace('scrapbook');
BEGIN
    SET LOCAL search_path TO pg_catalog;

    IF session_user <> 'scrapbook_migrator' OR current_user <> 'scrapbook_owner'
        OR current_setting('server_version_num')::integer NOT BETWEEN 180000 AND 189999
        OR NOT EXISTS (
            SELECT 1 FROM pg_namespace WHERE oid = schema_oid AND nspowner = owner_oid
        ) THEN
        RAISE EXCEPTION 'Banco ou identidade incompatível com a migração Scrap Book.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_default_acl AS defaults
        CROSS JOIN LATERAL aclexplode(defaults.defaclacl) AS privilege
        WHERE defaults.defaclrole = owner_oid
          AND defaults.defaclnamespace IN (0, schema_oid)
          AND defaults.defaclobjtype IN ('r', 'S', 'f')
          AND privilege.grantee <> owner_oid
    ) THEN
        RAISE EXCEPTION 'Privilégios padrão incompatíveis com a matriz Scrap Book.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_roles AS runtime
        WHERE runtime.rolname IN ('scrapbook_app', 'scrapbook_audit_reader')
          AND (
              runtime.rolsuper
              OR has_schema_privilege(runtime.oid, schema_oid, 'CREATE')
              OR EXISTS (SELECT 1 FROM pg_auth_members WHERE member = runtime.oid)
          )
    ) THEN
        RAISE EXCEPTION 'Associação de roles ou privilégios de runtime incompatíveis.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_class AS control
        WHERE control.relnamespace = schema_oid
          AND control.relname IN ('databasechangelog', 'databasechangeloglock')
          AND (
              control.relowner <> owner_oid OR control.relkind <> 'r'
              OR EXISTS (
                  SELECT 1 FROM pg_roles AS runtime
                  WHERE runtime.rolname IN ('scrapbook_app', 'scrapbook_audit_reader')
                    AND (
                        has_any_column_privilege(runtime.oid, control.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
                        OR has_table_privilege(runtime.oid, control.oid, 'DELETE, TRUNCATE, TRIGGER, MAINTAIN')
                    )
              )
          )
    ) THEN
        RAISE EXCEPTION 'Privilégios efetivos incompatíveis nos controles do Liquibase.';
    END IF;
END;
$preflight$;
