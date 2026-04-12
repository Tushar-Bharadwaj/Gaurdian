#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:-}"
PHASE="${2:-}"
STATUS="${3:-}"
shift 3 || true

if [[ -z "$STATE_FILE" || -z "$PHASE" || -z "$STATUS" ]]; then
  echo "Usage: update-state.sh <state-file> <phase> <status> [key=value...]" >&2
  exit 1
fi

LOCK_DIR="${STATE_FILE}.lock"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Platform-appropriate locking
acquire_lock() {
  local max_attempts=50
  local attempt=0
  if command -v flock &>/dev/null; then
    # Linux: use flock
    exec 9>"${STATE_FILE}.flock"
    flock -w 10 9
  else
    # macOS: use atomic mkdir
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
      attempt=$((attempt + 1))
      if [[ $attempt -ge $max_attempts ]]; then
        echo "Failed to acquire lock after $max_attempts attempts" >&2
        exit 1
      fi
      sleep 0.1
    done
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT
  fi
}

release_lock() {
  if command -v flock &>/dev/null; then
    exec 9>&-
  else
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

acquire_lock

# Initialize state file if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"phases": {}}' > "$STATE_FILE"
fi

# Build the update based on status
case "$STATUS" in
  in_progress)
    jq --arg phase "$PHASE" --arg status "$STATUS" --arg started_at "$NOW" \
      '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status, started_at: $started_at})' \
      "$STATE_FILE" > "${STATE_FILE}.tmp"
    ;;
  completed)
    # Parse extra args for deliverables
    deliverables="null"
    for arg in "$@"; do
      case "$arg" in
        deliverables=*)
          deliverables="${arg#deliverables=}"
          ;;
      esac
    done
    if [[ "$deliverables" == "null" ]]; then
      jq --arg phase "$PHASE" --arg status "$STATUS" --arg completed_at "$NOW" \
        '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status, completed_at: $completed_at})' \
        "$STATE_FILE" > "${STATE_FILE}.tmp"
    else
      jq --arg phase "$PHASE" --arg status "$STATUS" --arg completed_at "$NOW" --argjson deliverables "$deliverables" \
        '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status, completed_at: $completed_at, deliverables: $deliverables})' \
        "$STATE_FILE" > "${STATE_FILE}.tmp"
    fi
    ;;
  skipped)
    # Parse extra args for reason
    reason=""
    for arg in "$@"; do
      case "$arg" in
        reason=*)
          reason="${arg#reason=}"
          ;;
      esac
    done
    if [[ -n "$reason" ]]; then
      jq --arg phase "$PHASE" --arg status "$STATUS" --arg reason "$reason" \
        '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status, reason: $reason})' \
        "$STATE_FILE" > "${STATE_FILE}.tmp"
    else
      jq --arg phase "$PHASE" --arg status "$STATUS" \
        '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status})' \
        "$STATE_FILE" > "${STATE_FILE}.tmp"
    fi
    ;;
  failed)
    jq --arg phase "$PHASE" --arg status "$STATUS" \
      '.phases[$phase] = (.phases[$phase] // {} | . + {status: $status})' \
      "$STATE_FILE" > "${STATE_FILE}.tmp"
    ;;
  *)
    echo "Unknown status: $STATUS (expected: in_progress, completed, skipped, failed)" >&2
    release_lock
    exit 1
    ;;
esac

mv "${STATE_FILE}.tmp" "$STATE_FILE"
release_lock

# Output updated state
cat "$STATE_FILE"
