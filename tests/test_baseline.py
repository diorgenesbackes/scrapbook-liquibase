import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
VERSIONS = json.loads((ROOT / "config/versions.json").read_text())
TABLES = frozenset("""
accounts sessions oidc_requests account_operations events event_members invitations covers
opening_dispatches consent_notices records idempotent_operations upload_sessions files
storage_objects file_variants processing_jobs processing_attempts cleanup_jobs notifications
notification_attempts outbox_messages processed_messages audit_entries
""".split())
MIGRATOR = "scrapbook_migrator"
APP = "scrapbook_app"


def run(args, *, cwd=ROOT, sql=None, env=None, timeout=120):
    return subprocess.run(
        args, cwd=cwd, input=sql, env=os.environ | (env or {}),
        text=True, capture_output=True, check=False, timeout=timeout,
    )


def checked(result, expected=None):
    output = result.stdout + result.stderr
    if expected is None and result.returncode:
        raise AssertionError(output)
    if expected is not None and (not result.returncode or expected not in output):
        raise AssertionError(f"Falha esperada contendo {expected!r}. Resultado: {output}")
    return result.stdout.strip()


class BaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        suffix = secrets.token_hex(8)
        cls.container = "scrapbook-f01-" + suffix
        cls.password = secrets.token_hex(24)
        image = VERSIONS["postgresImage"]
        checked(run(["docker", "run", "--rm", "-d", "--name", cls.container, "--publish",
                     "127.0.0.1::5432", "--env", "POSTGRES_PASSWORD", image],
                    env={"POSTGRES_PASSWORD": cls.password}))
        cls.addClassCleanup(checked_remove_container, cls.container)
        for _ in range(60):
            probe = run(["docker", "exec", cls.container, "pg_isready", "-h", "127.0.0.1"], timeout=5)
            if probe.returncode == 0:
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("O PostgreSQL descartável não iniciou.")
        port = checked(run(["docker", "port", cls.container, "5432/tcp"]))
        if not port.startswith("127.0.0.1:") or not port.rsplit(":", 1)[1].isdigit():
            raise RuntimeError(f"Publicação Docker inesperada: {port}")
        cls.port = port.rsplit(":", 1)[1]
        cls.counter = 0
        cli_version = checked(run(["liquibase", "--version"]))
        if f'Liquibase Version: {VERSIONS["liquibase"]}' not in cli_version:
            raise RuntimeError(f'Usar Liquibase {VERSIONS["liquibase"]} no laboratório.')

    def setUp(self):
        type(self).counter += 1
        self.database = f"f01_case_{self.counter}"
        checked(self.psql(f"CREATE DATABASE {self.database}", database="postgres"))
        bootstrap = (ROOT / "config/bootstrap.sql").read_text()
        checked(self.psql(bootstrap))
        checked(self.psql(
            f"ALTER ROLE {APP} PASSWORD '{self.password}'; "
            f"ALTER ROLE {MIGRATOR} PASSWORD '{self.password}'"
        ))
        checked(self.psql(bootstrap))

    def psql(self, sql, *, user="postgres", database=None):
        args = ["docker", "exec", "--interactive"]
        if user != "postgres":
            args += ["--env", "PGPASSWORD"]
        args.extend([self.container, "psql", "-qXAt", "--set=ON_ERROR_STOP=1",
                     "--dbname", database or self.database, "--username", user])
        if user != "postgres":
            args += ["--host", "127.0.0.1"]
        return run(args, sql=sql, env={"PGPASSWORD": self.password})

    def liquibase(self, command, *args, cwd=ROOT):
        return run(
            ["liquibase", "--log-level=warning", "--liquibase-schema-name=scrapbook", command,
             "--changelog-file=db.changelog-master.yaml", "--default-schema-name=scrapbook",
             f"--url=jdbc:postgresql://127.0.0.1:{self.port}/{self.database}",
             f"--username={MIGRATOR}", *args],
            cwd=cwd, env={"LIQUIBASE_COMMAND_PASSWORD": self.password},
        )

    def installed_tables(self):
        return set(checked(self.psql("""
            SELECT tablename FROM pg_tables WHERE schemaname = 'scrapbook'
            AND tablename NOT IN ('databasechangelog', 'databasechangeloglock');
        """)).splitlines())

    def install(self):
        checked(self.liquibase("update"))

    def assert_history(self, count):
        self.assertEqual(str(count), checked(self.psql("SELECT count(*) FROM scrapbook.databasechangelog")))

    def test_install_single_schema_inventory(self):
        self.assertEqual("180006", checked(self.psql("SHOW server_version_num")))
        self.assertEqual("scrapbook_owner", checked(self.psql("SELECT current_user", user=MIGRATOR)))
        checked(self.liquibase("validate"))
        self.install()
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)
        self.assertEqual("24", checked(self.psql("""
            SELECT count(*) FROM information_schema.columns
            WHERE table_schema = 'scrapbook' AND column_name = 'id'
            AND data_type = 'bigint' AND identity_generation = 'ALWAYS' AND is_nullable = 'NO';
        """)))
        self.assertEqual("24|34", checked(self.psql("""
            SELECT count(*) FILTER (WHERE contype = 'p'),
                count(*) FILTER (WHERE contype = 'f' AND confupdtype = 'r' AND confdeltype = 'r')
            FROM pg_constraint
            WHERE connamespace = 'scrapbook'::regnamespace
              AND conrelid NOT IN (
                  'scrapbook.databasechangelog'::regclass, 'scrapbook.databasechangeloglock'::regclass
              );
        """)))
        self.assertEqual("timestamp without time zone", checked(self.psql("""
            SELECT data_type FROM information_schema.columns WHERE table_schema = 'scrapbook'
            AND table_name = 'events' AND column_name = 'starts_at';
        """)))
        self.assertEqual("4", checked(self.psql("""
            SELECT count(*) FROM information_schema.columns WHERE table_schema = 'scrapbook'
            AND table_name = 'upload_sessions' AND column_name IN
                ('lease_token', 'lease_until', 'attempt_count', 'next_attempt_at');
        """)))
        self.assertEqual("t", checked(self.psql("""
            SELECT indisvalid AND indpred IS NOT NULL FROM pg_index
            WHERE indexrelid = 'scrapbook.ix_upload_sessions_worker_due'::regclass;
        """)))

    def test_reapply_preserves_catalog_and_detects_drift(self):
        self.install()
        first = checked(self.psql("SELECT scrapbook.foundation_signature()"))
        self.install()
        self.assertEqual(first, checked(self.psql("SELECT scrapbook.foundation_signature()")))
        self.assert_history(1)
        checked(self.psql("ALTER TABLE scrapbook.accounts ADD COLUMN unauthorized text"))
        checked(self.liquibase("update"), expected="divergência no catálogo")
        checked(self.liquibase("rollback-count", "--count=1"), expected="catálogo")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)

    def test_detect_incompatible_existing_object(self):
        checked(self.psql("CREATE TABLE scrapbook.accounts (unexpected text)", user=MIGRATOR))
        checked(self.liquibase("update"), expected="divergência no catálogo")
        self.assertEqual({"accounts"}, self.installed_tables())
        self.assertEqual("unexpected", checked(self.psql("""
            SELECT column_name FROM information_schema.columns WHERE table_schema = 'scrapbook'
            AND table_name = 'accounts';
        """)))

    def test_bootstrap_rejects_unexpected_role_membership(self):
        checked(self.psql("GRANT pg_read_all_data TO scrapbook_app WITH SET TRUE"))
        try:
            bootstrap = (ROOT / "config/bootstrap.sql").read_text()
            checked(self.psql(bootstrap), expected="Associação de roles incompatível")
            self.assertEqual(set(), self.installed_tables())
        finally:
            checked(self.psql("REVOKE pg_read_all_data FROM scrapbook_app"))

    def test_bootstrap_rejects_global_and_schema_default_grants(self):
        bootstrap = (ROOT / "config/bootstrap.sql").read_text()
        for scope in ("", " IN SCHEMA scrapbook"):
            with self.subTest(scope=scope):
                alter = f"ALTER DEFAULT PRIVILEGES FOR ROLE scrapbook_owner{scope}"
                checked(self.psql(alter + " GRANT SELECT ON TABLES TO PUBLIC"))
                checked(self.psql(bootstrap), expected="Privilégios padrão incompatíveis")
                checked(self.psql(alter + " REVOKE SELECT ON TABLES FROM PUBLIC"))
        checked(self.psql(bootstrap))

    def test_install_rejects_effective_audit_access_after_bootstrap(self):
        checked(self.psql("""
            ALTER DEFAULT PRIVILEGES FOR ROLE scrapbook_owner IN SCHEMA scrapbook
            GRANT SELECT ON TABLES TO scrapbook_app;
        """))
        checked(self.liquibase("update"), expected="Privilégios efetivos incompatíveis")
        self.assertEqual(set(), self.installed_tables())
        self.assert_history(0)

    def test_reapply_rejects_effective_read_on_liquibase_control(self):
        self.install()
        checked(self.psql("GRANT SELECT (id) ON scrapbook.databasechangelog TO scrapbook_app"))
        checked(self.liquibase("update"), expected="divergência no catálogo")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)

    def test_application_permissions_and_audit(self):
        self.install()
        self.assertEqual("1", checked(self.psql(
            "INSERT INTO scrapbook.accounts(state) VALUES ('anonymized') RETURNING id", user=APP
        )))
        checked(self.psql("UPDATE scrapbook.accounts SET version = 1 WHERE id = 1", user=APP))
        checked(self.psql("""
            INSERT INTO scrapbook.audit_entries(area, actor_type, action, subject_type, outcome,
                correlation_id, expires_at)
            VALUES ('identity', 'system', 'fixture', 'account', 'success',
                '00000000-0000-0000-0000-000000000001', CURRENT_TIMESTAMP + INTERVAL '4320 hours');
        """, user=APP))
        for sql in (
            "CREATE TABLE scrapbook.forbidden (id bigint)",
            "ALTER TABLE scrapbook.accounts ADD COLUMN forbidden text",
            "DROP TABLE scrapbook.accounts",
            "SELECT * FROM scrapbook.databasechangelog",
            "SELECT * FROM scrapbook.databasechangeloglock",
            "SELECT * FROM scrapbook.audit_entries",
            "UPDATE scrapbook.audit_entries SET action = 'tampered'",
            "DELETE FROM scrapbook.audit_entries",
            "TRUNCATE TABLE scrapbook.audit_entries",
            "SELECT scrapbook.foundation_signature()",
        ):
            checked(self.psql(sql, user=APP), expected="permission denied" if "DROP" not in sql
                    and "ALTER" not in sql else "must be owner")
        checked(self.psql("SET ROLE scrapbook_owner", user=APP), expected="permission denied")
        self.assertEqual("t|f|f", checked(self.psql("""
            SELECT has_table_privilege('scrapbook_audit_reader', 'scrapbook.audit_entries', 'SELECT'),
                has_table_privilege('scrapbook_audit_reader', 'scrapbook.audit_entries', 'DELETE'),
                has_table_privilege('scrapbook_audit_reader', 'scrapbook.accounts', 'SELECT');
        """)))
        self.install()
        self.assert_history(1)

    def test_shared_technical_uniqueness(self):
        self.install()
        outbox = """
            INSERT INTO scrapbook.outbox_messages
                (message_id, type, protocol_version, payload, correlation_id, occurred_at, state, available_at)
            VALUES ('00000000-0000-0000-0000-000000000001', 'fixture', 1, '{}',
                '00000000-0000-0000-0000-000000000002', CURRENT_TIMESTAMP, 'pending', CURRENT_TIMESTAMP)
        """
        checked(self.psql(outbox, user=APP))
        checked(self.psql(outbox, user=APP), expected="uq_outbox_messages_message")
        inbox = """
            INSERT INTO scrapbook.processed_messages
                (consumer, source, message_id, payload_hash, state)
            VALUES ('fixture.a', 'internal', '00000000-0000-0000-0000-000000000001',
                decode(repeat('00', 32), 'hex'), 'processing')
        """
        checked(self.psql(inbox, user=APP))
        checked(self.psql(inbox, user=APP), expected="uq_processed_messages_internal")
        checked(self.psql(inbox.replace("fixture.a", "fixture.b"), user=APP))

    def test_failed_changeset_preserves_prior_history(self):
        self.install()
        with tempfile.TemporaryDirectory(prefix="scrapbook-f01-failing-") as temp:
            work = Path(temp)
            shutil.copytree(ROOT / "changelogs", work / "changelogs")
            original = (ROOT / "db.changelog-master.yaml").read_text()
            (work / "db.changelog-master.yaml").write_text(original + """
  - changeSet:
      id: fixture-failure
      author: test
      changes:
        - sql:
            sql: CREATE TABLE scrapbook.fixture_uncommitted (id bigint)
        - sql:
            sql: SELECT id FROM scrapbook.fixture_missing
""")
            checked(self.liquibase("update", cwd=work), expected="fixture_missing")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)
        self.install()

    def test_schema_generation_can_be_reapplied_and_reverted(self):
        self.install()
        initial_signature = checked(self.psql("SELECT scrapbook.foundation_signature()"))
        with tempfile.TemporaryDirectory(prefix="scrapbook-f01-evolution-") as temp:
            work = Path(temp)
            shutil.copytree(ROOT / "changelogs", work / "changelogs")
            original = (ROOT / "db.changelog-master.yaml").read_text()
            (work / "db.changelog-master.yaml").write_text(original + """
  - changeSet:
      id: fixture-schema-generation
      author: scrapbook
      runInTransaction: true
      changes:
        - sql:
            sql: ALTER TABLE scrapbook.accounts ADD COLUMN fixture_column text;
        - sql:
            sql: SELECT scrapbook.checkpoint_catalog('f01-story-001-base', 'fixture-schema-generation');
      rollback:
        - sql:
            splitStatements: false
            sql: |
              DO $verify$
              BEGIN
                  IF obj_description('scrapbook.foundation_signature()'::regprocedure::oid, 'pg_proc')
                      IS DISTINCT FROM 'fixture-schema-generation:' || scrapbook.foundation_signature() THEN
                      RAISE EXCEPTION 'Catálogo incompatível com a reversão da fixture.';
                  END IF;
              END;
              $verify$;
              ALTER TABLE scrapbook.accounts DROP COLUMN fixture_column RESTRICT;
              SELECT scrapbook.checkpoint_catalog('fixture-schema-generation', 'f01-story-001-base');
""")
            checked(self.liquibase("update", cwd=work))
            self.assert_history(2)
            checked(self.liquibase("update", cwd=work))
            self.assert_history(2)
            checked(self.liquibase("rollback-count", "--count=1", cwd=work))
            self.assert_history(1)
        self.assertEqual(initial_signature, checked(self.psql("SELECT scrapbook.foundation_signature()")))
        self.install()
        self.assert_history(1)

    def test_sequence_definition_drift_blocks_update_and_rollback(self):
        self.install()
        checked(self.psql("ALTER SEQUENCE scrapbook.accounts_id_seq INCREMENT BY 10"))
        checked(self.liquibase("update"), expected="divergência no catálogo")
        checked(self.liquibase("rollback-count", "--count=1"), expected="catálogo")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)

    def test_rollback_and_reapply_empty_baseline(self):
        self.install()
        checked(self.liquibase("rollback-count", "--count=1"))
        self.assertEqual(set(), self.installed_tables())
        self.assert_history(0)
        self.assertEqual("f", checked(self.psql("""
            SELECT to_regprocedure('scrapbook.foundation_signature()') IS NOT NULL;
        """)))
        self.install()
        self.assertEqual(TABLES, self.installed_tables())

    def test_rollback_refuses_populated_baseline_and_external_dependencies(self):
        self.install()
        checked(self.psql("INSERT INTO scrapbook.accounts(state) VALUES ('anonymized')", user=APP))
        checked(self.liquibase("rollback-count", "--count=1"), expected="contém dados")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)
        checked(self.psql("DELETE FROM scrapbook.accounts"))
        checked(self.psql("CREATE VIEW public.fixture_dependency AS SELECT id FROM scrapbook.accounts"))
        checked(self.liquibase("rollback-count", "--count=1"), expected="depends")
        self.assertEqual(TABLES, self.installed_tables())
        self.assert_history(1)


def checked_remove_container(container):
    checked(run(["docker", "rm", "-f", container]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
