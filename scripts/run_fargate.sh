#!/bin/sh
set -eu

if [ "$#" -ne 0 ]; then
    echo "Esta imagem executa somente a aplicação do changelog." >&2
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
    if ! liquibase --liquibase-schema-name=scrapbook "$1" --username=scrapbook_migrator \
        --default-schema-name=scrapbook --changelog-file=db.changelog-master.yaml >/dev/null 2>&1; then
        echo "LIQUIBASE_STAGE_FAILED $1" >&2
        exit 1
    fi
}

preflight
apply validate
apply update
preflight "$(cat config/catalog-generation.txt)"
echo "LIQUIBASE_UPDATE_SUCCEEDED"
