#!/usr/bin/env bash
set -euo pipefail

QUEUE_FILE="${1:-}"

if [[ -z "$QUEUE_FILE" ]]; then
  echo '{"should_exploit": false, "reason": "no queue file path provided", "count": 0}'
  exit 1
fi

if [[ ! -f "$QUEUE_FILE" ]]; then
  echo '{"should_exploit": false, "reason": "queue file not found", "count": 0}'
  exit 1
fi

# Validate JSON and extract vulnerability count
count="$(jq -r '.vulnerabilities | length' "$QUEUE_FILE" 2>/dev/null)" || {
  echo '{"should_exploit": false, "reason": "invalid JSON or missing vulnerabilities array", "count": 0}'
  exit 1
}

if [[ -z "$count" || "$count" == "null" ]]; then
  echo '{"should_exploit": false, "reason": "missing vulnerabilities array", "count": 0}'
  exit 1
fi

if [[ "$count" -gt 0 ]]; then
  jq -n --argjson count "$count" '{"should_exploit": true, "count": $count}'
  exit 0
else
  echo '{"should_exploit": false, "reason": "empty vulnerability queue", "count": 0}'
  exit 1
fi
