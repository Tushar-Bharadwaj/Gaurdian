#!/usr/bin/env bash
set -euo pipefail

# Post-agent hook — fires on the Claude Code Stop event.
# Validates deliverables for in-progress Guardian phases and updates state.
# Compatible with bash 3.x (macOS system bash).

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)/../scripts"
UPDATE_STATE="$SCRIPTS_DIR/update-state.sh"

# Returns space-separated list of expected deliverables for a phase.
# Replaces 'declare -A' associative arrays which require bash 4.0+.
get_deliverables() {
  case "$1" in
    recon)             echo "recon/pre-recon.md recon/recon.md" ;;
    vuln-injection)    echo "vuln/injection-analysis.md vuln/injection-queue.json" ;;
    vuln-xss)          echo "vuln/xss-analysis.md vuln/xss-queue.json" ;;
    vuln-auth)         echo "vuln/auth-analysis.md vuln/auth-queue.json" ;;
    vuln-authz)        echo "vuln/authz-analysis.md vuln/authz-queue.json" ;;
    vuln-ssrf)         echo "vuln/ssrf-analysis.md vuln/ssrf-queue.json" ;;
    exploit-injection) echo "exploit/injection-evidence.md" ;;
    exploit-xss)       echo "exploit/xss-evidence.md" ;;
    exploit-auth)      echo "exploit/auth-evidence.md" ;;
    exploit-authz)     echo "exploit/authz-evidence.md" ;;
    exploit-ssrf)      echo "exploit/ssrf-evidence.md" ;;
    report)            echo "report/security-assessment.md" ;;
    *)                 echo "" ;;
  esac
}

# 1. Find the active scan directory
find_active_scan() {
  local scans_dir="guardian/scans"
  if [[ ! -d "$scans_dir" ]]; then
    return 1
  fi

  for scan_dir in "$scans_dir"/*/; do
    local state_file="${scan_dir}.state.json"
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

# 3. Get all in-progress phases.
# Replaces 'mapfile -t' which requires bash 4.0+.
IN_PROGRESS_PHASES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && IN_PROGRESS_PHASES+=("$line")
done < <(jq -r '.phases // {} | to_entries[] | select(.value.status == "in_progress") | .key' "$STATE_FILE")

# 4. For each in-progress phase, check deliverables and update state
TRANSITIONS='[]'
for phase in "${IN_PROGRESS_PHASES[@]}"; do
  expected="$(get_deliverables "$phase")"
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
    # Pass deliverables= prefix so update-state.sh can parse the key=value arg
    "$UPDATE_STATE" "$STATE_FILE" "$phase" "completed" "deliverables=$deliverables_json"
    TRANSITIONS=$(echo "$TRANSITIONS" | jq --arg p "$phase" --arg f "in_progress" --arg t "completed" '. + [{"phase":$p,"from":$f,"to":$t}]')
  else
    "$UPDATE_STATE" "$STATE_FILE" "$phase" "failed"
    TRANSITIONS=$(echo "$TRANSITIONS" | jq --arg p "$phase" --arg f "in_progress" --arg t "failed" '. + [{"phase":$p,"from":$f,"to":$t}]')
  fi
done

# 5. Structured output
SCAN_NAME=$(basename "${SCAN_DIR%/}")
echo "$TRANSITIONS" | jq -c --arg s "$SCAN_NAME" '{"status":"ok","scan":$s,"transitions":.}'
