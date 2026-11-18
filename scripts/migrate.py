import argparse
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def runtime_paths():
    java_home = os.environ.get("JAVA_HOME")
    liquibase_home = os.environ.get("LIQUIBASE_HOME")
    if not java_home or not liquibase_home:
        version = subprocess.run(["liquibase", "--version"], text=True, capture_output=True, check=True)
        java_match = re.search(r"^Java Home (.+) \(Version ", version.stdout, re.M)
        liquibase_match = re.search(r"^Liquibase Home: (.+)$", version.stdout, re.M)
        java_home = java_home or (java_match.group(1) if java_match else None)
        liquibase_home = liquibase_home or (liquibase_match.group(1) if liquibase_match else None)
    if not java_home or not liquibase_home:
        raise ValueError("configure JAVA_HOME e LIQUIBASE_HOME para a instalação do Liquibase")
    java = Path(java_home) / "bin/java"
    driver = Path(liquibase_home) / "internal/lib/postgresql.jar"
    if not java.is_file() or not driver.is_file():
        raise ValueError("JDK ou driver PostgreSQL do Liquibase indisponível")
    return java, driver


def main():
    parser = argparse.ArgumentParser(description="Executa o Liquibase com pré-validação do banco.")
    parser.add_argument("command", choices=("validate", "status", "update-sql", "update", "rollback-count"))
    parser.add_argument("--changelog-file", default="db.changelog-master.yaml")
    parser.add_argument("--count", type=int)
    args = parser.parse_args()
    rollback = args.command == "rollback-count"
    if rollback and (args.count is None or args.count < 1):
        parser.error("rollback-count exige --count positivo")
    if not rollback and args.count is not None:
        parser.error("--count só é aceito para rollback-count")

    url = os.environ.get("LIQUIBASE_COMMAND_URL", "")
    if not url.startswith("jdbc:postgresql://"):
        parser.error("configure LIQUIBASE_COMMAND_URL com a URL JDBC PostgreSQL do alvo")

    try:
        java, driver = runtime_paths()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(f"pré-validação indisponível: {error}")

    preflight = subprocess.run(
        [str(java), "--class-path", str(driver), str(ROOT / "scripts/MigrationPreflight.java"),
         str(ROOT / "config/preflight.sql")],
        check=False,
    )
    if preflight.returncode:
        return preflight.returncode

    command = ["liquibase", "--liquibase-schema-name=scrapbook", args.command,
               f"--url={url}", "--username=scrapbook_migrator", "--default-schema-name=scrapbook",
               f"--changelog-file={args.changelog_file}"]
    if rollback:
        command.append(f"--count={args.count}")
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
