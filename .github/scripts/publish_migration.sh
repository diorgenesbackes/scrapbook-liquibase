#!/usr/bin/env bash
set -euo pipefail
source .github/scripts/release_support.sh
source .github/scripts/release_ecs.sh

: "${ECS_CLUSTER:?}" "${MIGRATION_TASK_DEFINITION:?}" "${MIGRATION_SUBNET_IDS:?}" "${MIGRATION_GROUP_ID:?}"
generation=$(cat config/catalog-generation.txt)
[[ "$generation" =~ ^[a-z0-9][a-z0-9-]*$ ]]
[[ "$MIGRATION_GROUP_ID" =~ ^sg-[a-f0-9]+$ ]]
network=$(jq -ecn --argjson subnets "$MIGRATION_SUBNET_IDS" --arg group "$MIGRATION_GROUP_ID" '
    if ($subnets | type != "array" or length != 2 or (unique | length) != 2
        or any(.[]; type != "string" or (test("^subnet-[a-f0-9]+$") | not)))
    then error("Configure duas sub-redes ECS distintas.")
    else {awsvpcConfiguration: {subnets: $subnets, securityGroups: [$group], assignPublicIp: "ENABLED"}} end')
ensure_current_revision
aws ecs describe-task-definition --task-definition "$MIGRATION_TASK_DEFINITION" --output json |
    jq -e '
        .taskDefinition.containerDefinitions[] | select(.name == "liquibase") |
        ((.command // []) | length) == 0 and ((.entryPoint // []) | length) == 0 and
        (all(.environment[]; .name != "LIQUIBASE_COMMAND_PASSWORD")) and
        any(.secrets[]; .name == "LIQUIBASE_COMMAND_PASSWORD" and (.valueFrom | startswith("arn:aws:secretsmanager:"))) and
        .logConfiguration.logDriver == "awslogs"' >/dev/null
image=$(build_immutable_image)
record image "$image"
record generation "$generation"
definition=$(register_task "$MIGRATION_TASK_DEFINITION" liquibase "$image")
[[ "$definition" == arn:aws:ecs:us-east-1:"$AWS_ACCOUNT_ID":task-definition/* ]]
record taskDefinition "$definition"
ensure_current_revision
token="liquibase-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
task=$(aws ecs run-task --cluster "$ECS_CLUSTER" --task-definition "$definition" --launch-type FARGATE \
    --client-token "$token" --network-configuration "$network" --output json |
    jq -er 'select((.failures | length) == 0 and (.tasks | length) == 1) | .tasks[0].taskArn')
record task "$task"
aws ecs wait tasks-stopped --cluster "$ECS_CLUSTER" --tasks "$task"
aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task" --output json |
    jq -e --arg digest "${image##*@}" '.tasks[0] as $task |
        (.failures | length) == 0 and $task.lastStatus == "STOPPED" and
        any($task.containers[]; .name == "liquibase" and .exitCode == 0 and .imageDigest == $digest)' >/dev/null
marker=$(jq -c '.result = "success"' release-evidence.json)
aws ssm put-parameter --name /scrapbook/hlg/liquibase/active --type String \
    --value "$marker" --overwrite >/dev/null
