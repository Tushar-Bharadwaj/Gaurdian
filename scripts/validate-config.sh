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

# Convert YAML to JSON so jq can query it.
# Tries in order: mikefarah/yq → kislyuk/yq → python3+PyYAML.
yaml_to_json() {
  local file="$1"
  local out

  if command -v yq &>/dev/null; then
    # mikefarah/yq (brew install yq) uses -o=json
    if out=$(yq -o=json . "$file" 2>/dev/null) && echo "$out" | jq . &>/dev/null; then
      echo "$out"
      return 0
    fi
    # kislyuk/yq (pip install yq) outputs JSON-compatible by default
    if out=$(yq . "$file" 2>/dev/null) && echo "$out" | jq . &>/dev/null; then
      echo "$out"
      return 0
    fi
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import sys, json
try:
    import yaml
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f)
    print(json.dumps(data if data is not None else {}))
except ImportError:
    sys.exit(1)
" "$file" 2>/dev/null && return 0
  fi

  return 1
}

CONFIG_JSON="$(yaml_to_json "$CONFIG_FILE")" || {
  echo '{"valid": false, "errors": ["Cannot parse YAML: install yq (brew install yq) or PyYAML (pip3 install pyyaml)"]}'
  exit 1
}

errors=()

# Validate target.url exists and is non-empty
target_url="$(echo "$CONFIG_JSON" | jq -r '.target.url // empty' 2>/dev/null || true)"
if [[ -z "$target_url" ]]; then
  errors+=("target.url must exist and be non-empty")
fi

# Validate target.type if present
target_type="$(echo "$CONFIG_JSON" | jq -r '.target.type // empty' 2>/dev/null || true)"
if [[ -n "$target_type" ]]; then
  case "$target_type" in
    web|api|both) ;;
    *) errors+=("target.type must be one of: web, api, both (got: $target_type)") ;;
  esac
fi

# Validate authentication.success_condition.type if present
auth_sc_type="$(echo "$CONFIG_JSON" | jq -r '.authentication.success_condition.type // empty' 2>/dev/null || true)"
if [[ -n "$auth_sc_type" ]]; then
  case "$auth_sc_type" in
    url_contains|url_equals_exactly|element_present|text_contains) ;;
    *) errors+=("authentication.success_condition.type must be one of: url_contains, url_equals_exactly, element_present, text_contains (got: $auth_sc_type)") ;;
  esac
fi

# Validate authentication.login_type if present
auth_login_type="$(echo "$CONFIG_JSON" | jq -r '.authentication.login_type // empty' 2>/dev/null || true)"
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
  errors_json="$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)"
  jq -n --argjson errors "$errors_json" '{"valid": false, "errors": $errors}'
  exit 1
fi
