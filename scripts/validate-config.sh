#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-}"

if [[ -z "$CONFIG_FILE" ]]; then
  echo '{"valid": false, "errors": ["No config file path provided"]}'
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo '{"valid": false, "errors": ["Config file not found: '"$CONFIG_FILE"'"]}'
  exit 1
fi

errors=()

# Validate target.url exists and is non-empty
target_url="$(jq -r '.target.url // empty' "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -z "$target_url" ]]; then
  errors+=("target.url must exist and be non-empty")
fi

# Validate target.type if present
target_type="$(jq -r '.target.type // empty' "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -n "$target_type" ]]; then
  case "$target_type" in
    web|api|both) ;;
    *) errors+=("target.type must be one of: web, api, both (got: $target_type)") ;;
  esac
fi

# Validate authentication.success_condition.type if present
auth_sc_type="$(jq -r '.authentication.success_condition.type // empty' "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -n "$auth_sc_type" ]]; then
  case "$auth_sc_type" in
    url_contains|url_equals_exactly|element_present|text_contains) ;;
    *) errors+=("authentication.success_condition.type must be one of: url_contains, url_equals_exactly, element_present, text_contains (got: $auth_sc_type)") ;;
  esac
fi

# Validate authentication.login_type if present
auth_login_type="$(jq -r '.authentication.login_type // empty' "$CONFIG_FILE" 2>/dev/null || true)"
if [[ -n "$auth_login_type" ]]; then
  case "$auth_login_type" in
    form|sso|api|basic) ;;
    *) errors+=("authentication.login_type must be one of: form, sso, api, basic (got: $auth_login_type)") ;;
  esac
fi

if [[ ${#errors[@]} -eq 0 ]]; then
  echo '{"valid": true}'
  exit 0
else
  # Build errors JSON array
  errors_json="$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)"
  jq -n --argjson errors "$errors_json" '{"valid": false, "errors": $errors}'
  exit 1
fi
