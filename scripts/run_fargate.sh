#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
    echo "Informe uma única operação de recuperação." >&2
    exit 2
fi

: "${LIQUIBASE_COMMAND_PASSWORD:?}"
case "${LIQUIBASE_COMMAND_URL:-}" in
    jdbc:postgresql://*.rds.amazonaws.com:5432/*\?sslmode=verify-full\&sslrootcert=/opt/scrapbook/certs/rds-us-east-1.pem) ;;
    *) echo "Configure a URL JDBC do RDS com verificação de TLS." >&2; exit 2 ;;
esac

preflight() {
    java -cp "classes:$LIQUIBASE_HOME/internal/lib/postgresql.jar" MigrationPreflight config/preflight.sql "$@"
}

apply() {
    local_stage=$1
    if ! liquibase --liquibase-schema-name=scrapbook "$@" --username=scrapbook_migrator \
        --default-schema-name=scrapbook --changelog-file=db.changelog-master.yaml >/dev/null 2>&1; then
        echo "LIQUIBASE_STAGE_FAILED $local_stage" >&2
        exit 1
    fi
}

assert_recovery_target() {
    if [ "${LIQUIBASE_COMMAND_URL:-}" != "jdbc:postgresql://${RECOVERY_RDS_ENDPOINT:?}:5432/scrapbook_recovery?sslmode=verify-full&sslrootcert=/opt/scrapbook/certs/rds-us-east-1.pem" ]; then
        echo "Recuperação restrita ao banco descartável ScrapBook." >&2
        exit 2
    fi
}

validate_rollback() {
    assert_recovery_target
    preflight f01-story-001-base
    java -cp "classes:$LIQUIBASE_HOME/internal/lib/postgresql.jar" MigrationPreflight config/rollback-preflight.sql
    apply validate
    apply rollback-count-sql --count=1
}

case "${1:-update}" in
    update)
        [ "$#" -eq 0 ] || exit 2
        preflight
        apply validate
        apply update
        preflight "$(cat config/catalog-generation.txt)"
        echo "LIQUIBASE_UPDATE_SUCCEEDED"
        ;;
    preview-empty-base)
        validate_rollback
        echo "LIQUIBASE_ROLLBACK_PREVIEW_SUCCEEDED"
        ;;
    rollback-empty-base)
        validate_rollback
        apply rollback-count --count=1
        java -cp "classes:$LIQUIBASE_HOME/internal/lib/postgresql.jar" MigrationPreflight config/rollback-verify.sql
        echo "LIQUIBASE_ROLLBACK_SUCCEEDED"
        ;;
    *)
        echo "Operação Liquibase inválida." >&2
        exit 2
        ;;
esac
