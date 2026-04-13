#!/usr/bin/env bash
set -euo pipefail

# Post-agent hook — fires on the Claude Code Stop event.
# Validates deliverables for in-progress Guardian phases and updates state.

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)/../scripts"
UPDATE_STATE="$SCRIPTS_DIR/update-state.sh"

# Phase -> expected deliverables (paths relative to scan directory)
declare -A PHASE_DELIVERABLES=(
  [recon]="recon/pre-recon.md recon/recon.md"
  [vuln-injection]="vuln/injection-analysis.md vuln/injection-queue.json"
  [vuln-xss]="vuln/xss-analysis.md vuln/xss-queue.json"
  [vuln-auth]="vuln/auth-analysis.md vuln/auth-queue.json"
  [vuln-authz]="vuln/authz-analysis.md vuln/authz-queue.json"
  [vuln-ssrf]="vuln/ssrf-analysis.md vuln/ssrf-queue.json"
  [exploit-injection]="exploit/injection-evidence.md"
  [exploit-xss]="exploit/xss-evidence.md"
  [exploit-auth]="exploit/auth-evidence.md"
  [exploit-authz]="exploit/authz-evidence.md"
  [exploit-ssrf]="exploit/ssrf-evidence.md"
  [report]="report/security-assessment.md"
)

# 1. Find the active scan directory
find_active_scan() {
  local scans_dir="guardian/scans"
  if [[ ! -d "$scans_dir" ]]; then
    return 1
  fi

  for scan_dir in "$scans_dir"/*/; do
    local state_file="$scan_dir.state.json"
    if [[ ! -f "$state_file" ]]; then
      continue
    fi

    # Check if any phase has status "in_progress"
    local in_progress_count
    in_progress_count=$(jq '[.phases // {} | to_entries[] | select(.value.status == "in_progress")] | length' "$state_file")
    if [[ "$in_progress_count" -gt 0 ]]; then
      echo "$scan_dir"
      return 0
    fi
  done

  return 1
}

# 2. Find the active scan or exit silently
SCAN_DIR=$(find_active_scan) || { echo '{"status":"skipped","reason":"no active scan"}'; exit 0; }
STATE_FILE="${SCAN_DIR}.state.json"

# 3. Get all in-progress phases
mapfile -t IN_PROGRESS_PHASES < <(
  jq -r '.phases // {} | to_entries[] | select(.value.status == "in_progress") | .key' "$STATE_FILE"
)

# 4. For each in-progress phase, check deliverables and update state
TRANSITIONS='[]'
for phase in "${IN_PROGRESS_PHASES[@]}"; do
  expected="${PHASE_DELIVERABLES[$phase]:-}"
  if [[ -z "$expected" ]]; then
    continue
  fi

  # Check if all expected deliverables exist
  all_present=true
  deliverables_list=()
  for deliverable in $expected; do
    full_path="${SCAN_DIR}${deliverable}"
    if [[ -f "$full_path" ]]; then
      deliverables_list+=("$full_path")
    else
      all_present=false
      break
    fi
  done

  if [[ "$all_present" == true ]]; then
    deliverables_json=$(printf '%s\n' "${deliverables_list[@]}" | jq -R . | jq -s .)
    "$UPDATE_STATE" "$STATE_FILE" "$phase" "completed" "$deliverables_json"
    TRANSITIONS=$(echo "$TRANSITIONS" | jq --arg p "$phase" --arg f "in_progress" --arg t "completed" '. + [{"phase":$p,"from":$f,"to":$t}]')
  else
    "$UPDATE_STATE" "$STATE_FILE" "$phase" "failed"
    TRANSITIONS=$(echo "$TRANSITIONS" | jq --arg p "$phase" --arg f "in_progress" --arg t "failed" '. + [{"phase":$p,"from":$f,"to":$t}]')
  fi
done

# 5. Structured output
SCAN_NAME=$(basename "${SCAN_DIR%/}")
echo "$TRANSITIONS" | jq -c --arg s "$SCAN_NAME" '{"status":"ok","scan":$s,"transitions":.}'
