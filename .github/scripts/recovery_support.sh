#!/usr/bin/env bash

start_recovery_evidence() {
    jq -n --arg sha "$GITHUB_SHA" --arg repository "$GITHUB_REPOSITORY" \
        --arg runId "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
        --arg time "$(date -u +%FT%TZ)" \
        '{sha: $sha, repository: $repository, branch: "hlg", environment: "hlg",
          runId: $runId, attempt: $attempt, timestamp: $time, operation: "rollback", result: "incomplete"}' \
        > release-evidence.json
}
