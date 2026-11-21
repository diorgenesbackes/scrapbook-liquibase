DO $bootstrap$
DECLARE
    role_name text;
    login_required boolean;
    owner_oid oid;
    database_name text := current_database();
    operator_name name := current_user;
    operator_oid oid := current_user::regrole;
    temporary_owner_access boolean;
    operator_grant_exists boolean;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('scrapbook.bootstrap'));

    FOR role_name, login_required IN
        SELECT * FROM (VALUES
            ('scrapbook_owner', FALSE),
            ('scrapbook_migrator', TRUE),
            ('scrapbook_app', TRUE),
            ('scrapbook_audit_reader', FALSE)
        ) AS required(name, can_login)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            EXECUTE format('CREATE ROLE %I %s NOINHERIT', role_name,
                CASE WHEN login_required THEN 'LOGIN' ELSE 'NOLOGIN' END);
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pg_roles
            WHERE rolname = role_name AND rolcanlogin = login_required
              AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
              AND NOT rolinherit AND NOT rolreplication AND NOT rolbypassrls
        ) THEN
            RAISE EXCEPTION 'Role incompatível com a matriz Scrap Book: %', role_name;
        END IF;

        EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', database_name, role_name);
    END LOOP;

    SELECT oid INTO STRICT owner_oid FROM pg_roles WHERE rolname = 'scrapbook_owner';
    IF EXISTS (
        SELECT 1 FROM pg_auth_members AS membership
        JOIN pg_roles AS member ON member.oid = membership.member
        WHERE member.rolname IN ('scrapbook_owner', 'scrapbook_app', 'scrapbook_audit_reader', 'scrapbook_migrator')
          AND NOT (
              member.rolname = 'scrapbook_migrator' AND membership.roleid = owner_oid
              AND NOT membership.admin_option AND NOT membership.inherit_option AND membership.set_option
          )
    ) THEN
        RAISE EXCEPTION 'Associação de roles incompatível com a matriz Scrap Book.';
    END IF;

    temporary_owner_access := NOT pg_has_role(operator_oid, owner_oid, 'SET');
    IF temporary_owner_access THEN
        SELECT EXISTS (
            SELECT 1 FROM pg_auth_members
            WHERE roleid = owner_oid AND member = operator_oid AND grantor = operator_oid
        ) INTO operator_grant_exists;
        IF operator_grant_exists THEN
            GRANT scrapbook_owner TO CURRENT_USER WITH SET TRUE GRANTED BY CURRENT_USER;
        ELSE
            GRANT scrapbook_owner TO CURRENT_USER WITH INHERIT FALSE, SET TRUE GRANTED BY CURRENT_USER;
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'scrapbook') THEN
        CREATE SCHEMA scrapbook AUTHORIZATION scrapbook_owner;
    ELSIF NOT EXISTS (
        SELECT 1 FROM pg_namespace WHERE nspname = 'scrapbook' AND nspowner = owner_oid
    ) THEN
        RAISE EXCEPTION 'Schema scrapbook preexistente com proprietário incompatível.';
    END IF;

    GRANT scrapbook_owner TO scrapbook_migrator WITH INHERIT FALSE, SET TRUE;
    SET LOCAL ROLE scrapbook_owner;
    REVOKE ALL ON SCHEMA scrapbook FROM PUBLIC;
    GRANT USAGE ON SCHEMA scrapbook TO scrapbook_app, scrapbook_audit_reader;
    ALTER DEFAULT PRIVILEGES FOR ROLE scrapbook_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

    IF EXISTS (
        SELECT 1 FROM pg_default_acl AS defaults
        CROSS JOIN LATERAL aclexplode(defaults.defaclacl) AS privilege
        WHERE defaults.defaclrole = owner_oid
          AND defaults.defaclnamespace IN (0, 'scrapbook'::regnamespace)
          AND defaults.defaclobjtype IN ('r', 'S', 'f')
          AND privilege.grantee <> owner_oid
    ) THEN
        RAISE EXCEPTION 'Privilégios padrão incompatíveis com a matriz Scrap Book.';
    END IF;

    EXECUTE format('SET LOCAL ROLE %I', operator_name);
    IF temporary_owner_access THEN
        IF operator_grant_exists THEN
            REVOKE SET OPTION FOR scrapbook_owner FROM CURRENT_USER GRANTED BY CURRENT_USER;
        ELSE
            REVOKE scrapbook_owner FROM CURRENT_USER GRANTED BY CURRENT_USER;
        END IF;
    END IF;

    EXECUTE format('ALTER ROLE scrapbook_migrator IN DATABASE %I SET role = scrapbook_owner',
        database_name);
    EXECUTE format('ALTER ROLE scrapbook_migrator IN DATABASE %I SET search_path TO pg_catalog',
        database_name);
END;
$bootstrap$;
