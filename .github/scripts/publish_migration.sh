#!/usr/bin/env bash
set -euo pipefail
source .github/scripts/release_support.sh
source .github/scripts/release_ecs.sh

target=$(release_target)
active_parameter="/scrapbook/$target/liquibase/active"
pending_parameter="/scrapbook/$target/liquibase/pending"

finalize_migration() {
    local pending="$1" task definition image statuses marker
    task=$(jq -er --arg cluster "$ECS_CLUSTER" --arg target "$target" '
        select(.cluster == $cluster and .environment == $target and .result == "incomplete")
        | select(.generation | strings | test("^[a-z0-9][a-z0-9-]*\\z"))
        | select(.version | strings | test("^v(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)\\z"))
        | select(.sha | strings | test("^[0-9a-f]{40}\\z"))
        | .task | strings | select(length > 0)
    ' <<< "$pending") || return 1
    definition=$(jq -er '.taskDefinition | strings | select(length > 0)' <<< "$pending") || return 1
    image=$(jq -er '.image | strings | select(test("@sha256:[0-9a-f]{64}\\z"))' <<< "$pending") || return 1
    statuses=$(aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task" --output json) || return 1
    jq -e --arg arn "$task" --arg definition "$definition" --arg digest "${image##*@}" '
        (.failures | length) == 0 and (.tasks | length) == 1 and
        (.tasks[0] | .taskArn == $arn and .taskDefinitionArn == $definition and .lastStatus == "STOPPED" and
            any(.containers[]; .name == "liquibase" and .exitCode == 0 and .imageDigest == $digest))
    ' <<< "$statuses" >/dev/null || return 1

    marker=$(jq -c '.result = "success"' <<< "$pending") || return 1
    aws ssm put-parameter --name "$active_parameter" --type String --value "$marker" --overwrite >/dev/null || return 1
    aws ssm delete-parameter --name "$pending_parameter" >/dev/null || return 1
    sleep 30
}

reconcile_pending_migration() {
    local parameters pending
    parameters=$(aws ssm get-parameters --names "$pending_parameter" --output json)
    if jq -e --arg name "$pending_parameter" '
        .Parameters == [] and .InvalidParameters == [$name]
    ' <<< "$parameters" >/dev/null; then
        return
    fi
    pending=$(jq -ce --arg name "$pending_parameter" '
        select(.InvalidParameters == [] and (.Parameters | length) == 1)
        | .Parameters[0] | select(.Name == $name) | .Value | fromjson
    ' <<< "$parameters") || {
        echo "O registro pendente de migração está inválido. Confira o Parameter Store antes de publicar." >&2
        return 1
    }
    if ! finalize_migration "$pending"; then
        echo "Migração anterior pendente. Confira a tarefa e o catálogo antes de uma nova execução." >&2
        return 1
    fi
    record reconciledTask "$(jq -r .task <<< "$pending")"
}

: "${ECS_CLUSTER:?}" "${MIGRATION_TASK_DEFINITION:?}" "${MIGRATION_SUBNET_IDS:?}" "${MIGRATION_GROUP_ID:?}"
if [[ "$target" == production ]]; then
    [[ "${MIGRATION_PASSWORD_SECRET_ARN:?}" == "arn:aws:secretsmanager:us-east-1:$AWS_ACCOUNT_ID:secret:"?* ]]
    tls_url='^jdbc:postgresql://[a-z0-9.-]+:5432/[a-zA-Z0-9_]+\?sslmode=verify-full&sslrootcert=/opt/scrapbook/certs/rds-us-east-1\.pem$'
    [[ "${MIGRATION_DATABASE_URL:?}" =~ $tls_url ]]
fi
generation=$(cat config/catalog-generation.txt)
[[ "$generation" =~ ^[a-z0-9][a-z0-9-]*$ ]]
[[ "$MIGRATION_GROUP_ID" =~ ^sg-[a-f0-9]+$ ]]
network=$(jq -ecn --argjson subnets "$MIGRATION_SUBNET_IDS" --arg group "$MIGRATION_GROUP_ID" '
    if ($subnets | type != "array" or length != 2 or (unique | length) != 2
        or any(.[]; type != "string" or (test("^subnet-[a-f0-9]+$") | not)))
    then error("Configure duas sub-redes ECS distintas.")
    else {awsvpcConfiguration: {subnets: $subnets, securityGroups: [$group], assignPublicIp: "ENABLED"}} end')
ensure_current_revision
reconcile_pending_migration
aws ecs describe-task-definition --task-definition "$MIGRATION_TASK_DEFINITION" --output json |
    jq -e --arg target "$target" --arg password "${MIGRATION_PASSWORD_SECRET_ARN:-}" \
        --arg url "${MIGRATION_DATABASE_URL:-}" '
        .taskDefinition.containerDefinitions[] | select(.name == "liquibase") |
        ((.command // []) | length) == 0 and ((.entryPoint // []) | length) == 0 and
        (all(.environment[]; .name != "LIQUIBASE_COMMAND_PASSWORD")) and
        any(.secrets[]; .name == "LIQUIBASE_COMMAND_PASSWORD" and (.valueFrom | startswith("arn:aws:secretsmanager:"))) and
        ($target != "production" or (
            ([.secrets[] | select(.name == "LIQUIBASE_COMMAND_PASSWORD") | .valueFrom] == [$password]) and
            all(.secrets[]; .name != "LIQUIBASE_COMMAND_URL") and ((.environmentFiles // []) | length) == 0 and
            ([.environment[] | select(.name == "LIQUIBASE_COMMAND_URL") | .value] == [$url])
        )) and
        .logConfiguration.logDriver == "awslogs"' >/dev/null
image=$(build_immutable_image)
record image "$image"
record generation "$generation"
definition=$(register_task "$MIGRATION_TASK_DEFINITION" liquibase "$image")
[[ "$definition" == arn:aws:ecs:us-east-1:"$AWS_ACCOUNT_ID":task-definition/* ]]
record taskDefinition "$definition"
ensure_current_revision
token="liquibase-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
record cluster "$ECS_CLUSTER"
record clientToken "$token"
aws ssm put-parameter --name "$pending_parameter" --type String --value "$(cat release-evidence.json)" >/dev/null
task=$(aws ecs run-task --cluster "$ECS_CLUSTER" --task-definition "$definition" --launch-type FARGATE \
    --client-token "$token" --started-by "$token" --network-configuration "$network" --output json |
    jq -er 'select((.failures | length) == 0 and (.tasks | length) == 1) | .tasks[0].taskArn')
record task "$task"
pending=$(cat release-evidence.json)
aws ssm put-parameter --name "$pending_parameter" --type String --value "$pending" --overwrite >/dev/null
if ! aws ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$task"; then
    echo "A espera do ECS ficou inconclusiva. Conferindo o estado final da tarefa." >&2
fi
if ! finalize_migration "$pending"; then
    echo "Migração pendente de reconciliação. O registro no Parameter Store permanece ativo." >&2
    exit 1
fi
