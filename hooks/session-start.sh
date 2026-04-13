#!/usr/bin/env bash
set -euo pipefail

# Export GUARDIAN_ROOT so skills can reference plugin scripts via $GUARDIAN_ROOT
echo "export GUARDIAN_ROOT=\"${CLAUDE_PLUGIN_ROOT}\"" >> "$CLAUDE_ENV_FILE"

# Structured output
echo '{"status":"ok","exported":["GUARDIAN_ROOT"]}'
