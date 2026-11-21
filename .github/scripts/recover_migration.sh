#!/usr/bin/env bash
set -euo pipefail
source .github/scripts/release_support.sh

: "${AWS_ACCOUNT_ID:?}" "${ECR_REPOSITORY:?}" "${RECOVERY_CLUSTER:?}" "${RECOVERY_TASK_DEFINITION:?}"
: "${RECOVERY_RDS_IDENTIFIER:?}" "${RECOVERY_SUBNET_IDS:?}" "${RECOVERY_GROUP_ID:?}"
[[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ && "$ECR_REPOSITORY" =~ ^[a-z0-9][a-z0-9_./-]+$ ]] || exit 2
[[ "$RECOVERY_CLUSTER" == arn:aws:ecs:us-east-1:"$AWS_ACCOUNT_ID":cluster/* ]] || exit 2
[[ "$RECOVERY_TASK_DEFINITION" =~ ^arn:aws:ecs:us-east-1:[0-9]{12}:task-definition/[a-zA-Z0-9_-]+:[0-9]+$ ]] || exit 2
[[ "$RECOVERY_TASK_DEFINITION" == arn:aws:ecs:us-east-1:"$AWS_ACCOUNT_ID":task-definition/* ]] || exit 2
[[ "$RECOVERY_RDS_IDENTIFIER" =~ ^[a-z][a-z0-9-]+$ && "$RECOVERY_GROUP_ID" =~ ^sg-[a-f0-9]+$ ]] || exit 2
case "${RECOVERY_OPERATION:?}" in
    preview-empty-base|rollback-empty-base) ;;
    *) exit 2 ;;
esac
record operation "$RECOVERY_OPERATION"
ensure_current_revision

rds=$(aws rds describe-db-instances --db-instance-identifier "$RECOVERY_RDS_IDENTIFIER" --output json)
endpoint=$(jq -er --arg account "$AWS_ACCOUNT_ID" --arg id "$RECOVERY_RDS_IDENTIFIER" '
    .DBInstances | select(length == 1) | .[0] |
    select(.DBInstanceArn == ("arn:aws:rds:us-east-1:" + $account + ":db:" + $id) and
        .DBInstanceStatus == "available" and .Engine == "postgres" and
        .PubliclyAccessible == false and .Endpoint.Port == 5432 and
        any(.TagList[]; .Key == "Environment" and .Value == "hlg") and
        any(.TagList[]; .Key == "Purpose" and .Value == "scrapbook-recovery-rehearsal"))
    | .Endpoint.Address | select(test("^[a-z0-9.-]+[.]rds[.]amazonaws[.]com$"))
' <<< "$rds")
url="jdbc:postgresql://$endpoint:5432/scrapbook_recovery?sslmode=verify-full&sslrootcert=/opt/scrapbook/certs/rds-us-east-1.pem"
definition=$(aws ecs describe-task-definition --task-definition "$RECOVERY_TASK_DEFINITION" --output json)
image=$(jq -er --arg definition "$RECOVERY_TASK_DEFINITION" --arg url "$url" '
    .taskDefinition | select(.taskDefinitionArn == $definition and .status == "ACTIVE" and
        .networkMode == "awsvpc" and (.requiresCompatibilities | index("FARGATE")) != null and
        (.runtimePlatform.cpuArchitecture // "X86_64") == "X86_64" and
        (.runtimePlatform.operatingSystemFamily // "LINUX") == "LINUX")
    | .containerDefinitions | select(length == 1) | .[0] |
    select(.name == "liquibase" and .essential != false and
        ((.command // []) | length) == 0 and ((.entryPoint // []) | length) == 0 and
        any(.environment[]; .name == "LIQUIBASE_COMMAND_URL" and .value == $url) and
        all(.environment[]; .name != "LIQUIBASE_COMMAND_PASSWORD") and
        any(.secrets[]; .name == "LIQUIBASE_COMMAND_PASSWORD" and (.valueFrom | startswith("arn:aws:secretsmanager:"))) and
        .logConfiguration.logDriver == "awslogs") | .image
' <<< "$definition")
digest=${image##*@}
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || exit 1
[[ "$image" == "$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/$ECR_REPOSITORY@$digest" ]] || exit 1
network=$(jq -ecn --argjson subnets "$RECOVERY_SUBNET_IDS" --arg group "$RECOVERY_GROUP_ID" '
    if ($subnets | type != "array" or length != 2 or (unique | length) != 2
        or any(.[]; type != "string" or (test("^subnet-[a-f0-9]+$") | not)))
    then error("Configure duas sub-redes ECS distintas para o ensaio.")
    else {awsvpcConfiguration: {subnets: $subnets, securityGroups: [$group], assignPublicIp: "ENABLED"}} end')
overrides=$(jq -n --arg operation "$RECOVERY_OPERATION" --arg endpoint "$endpoint" '
    {containerOverrides: [{name: "liquibase", command: [$operation],
        environment: [{name: "RECOVERY_RDS_ENDPOINT", value: $endpoint}]}]}')
record generation f01-story-001-base
record cluster "$RECOVERY_CLUSTER"
record taskDefinition "$RECOVERY_TASK_DEFINITION"
record image "$image"
ensure_current_revision
token="recovery-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
task=$(aws ecs run-task --cluster "$RECOVERY_CLUSTER" --task-definition "$RECOVERY_TASK_DEFINITION" \
    --launch-type FARGATE --client-token "$token" --started-by "$token" \
    --network-configuration "$network" --overrides "$overrides" --output json |
    jq -er 'select(.failures == [] and (.tasks | length) == 1) | .tasks[0].taskArn')
record task "$task"
aws ecs wait tasks-stopped --cluster "$RECOVERY_CLUSTER" --tasks "$task"
aws ecs describe-tasks --cluster "$RECOVERY_CLUSTER" --tasks "$task" --output json |
    jq -e --arg task "$task" --arg definition "$RECOVERY_TASK_DEFINITION" --arg digest "$digest" '
        .failures == [] and (.tasks | length) == 1 and
        (.tasks[0] | .taskArn == $task and .taskDefinitionArn == $definition and .lastStatus == "STOPPED" and
            any(.containers[]; .name == "liquibase" and .exitCode == 0 and .imageDigest == $digest))
    ' >/dev/null
