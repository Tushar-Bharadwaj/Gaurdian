# Guardian Plugin Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Guardian from an npm-style package to a proper Claude Code plugin with correct path resolution, structured hook output, and skill-creator-audited skills.

**Architecture:** Add `.claude-plugin/plugin.json` manifest, create `hooks/hooks.json` with wrapper format, add a `SessionStart` hook that exports `$GUARDIAN_ROOT`, then bulk-fix all `guardian-skills/...` paths (Read references become `../../` relative, Bash references use `$GUARDIAN_ROOT`). Finally, audit all 14 skills via skill-creator.

**Tech Stack:** Claude Code plugin system, Bash hooks, YAML/JSON config, Markdown skills

---

### Task 1: Create Plugin Manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create directory and manifest**

```bash
mkdir -p .claude-plugin
```

Write `.claude-plugin/plugin.json`:

```json
{
  "name": "guardian",
  "version": "0.1.0",
  "description": "AI-powered penetration testing skills for Claude Code — automated vulnerability analysis and exploitation across 5 security domains",
  "author": {
    "name": "CaptainClaude",
    "url": "https://github.com/CaptainClaude"
  },
  "repository": "https://github.com/CaptainClaude/guardian",
  "license": "AGPL-3.0",
  "keywords": ["security", "pentesting", "vulnerability-assessment", "exploitation"]
}
```

- [ ] **Step 2: Verify plugin.json is valid JSON**

```bash
cat .claude-plugin/plugin.json | jq .
```

Expected: Pretty-printed JSON with no errors.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add .claude-plugin/plugin.json manifest"
```

---

### Task 2: Create hooks/hooks.json and SessionStart Hook

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/session-start.sh`

- [ ] **Step 1: Write hooks/hooks.json**

```json
{
  "description": "Guardian pentest plugin hooks",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/post-agent.sh\"",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify hooks.json is valid JSON**

```bash
cat hooks/hooks.json | jq .
```

Expected: Pretty-printed JSON.

- [ ] **Step 3: Write hooks/session-start.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Export GUARDIAN_ROOT so skills can reference plugin scripts via $GUARDIAN_ROOT
echo "export GUARDIAN_ROOT=\"${CLAUDE_PLUGIN_ROOT}\"" >> "$CLAUDE_ENV_FILE"

# Structured output
echo '{"status":"ok","exported":["GUARDIAN_ROOT"]}'
```

- [ ] **Step 4: Make session-start.sh executable**

```bash
chmod +x hooks/session-start.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json hooks/session-start.sh
git commit -m "feat: add hooks.json (wrapper format) and session-start.sh"
```

---

### Task 3: Update package.json — Remove claude-code Field

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Remove the claude-code field**

Edit `package.json` to remove lines 11-21 (the entire `claude-code` block):

Before:
```json
{
  "name": "@CaptainClaude/guardian-skills",
  "version": "0.1.0",
  "description": "AI-powered penetration testing skills for Claude Code",
  "keywords": ["claude-code-plugin", "security", "pentesting"],
  "license": "AGPL-3.0",
  "repository": {
    "type": "git",
    "url": "https://github.com/CaptainClaude/guardian"
  },
  "claude-code": {
    "skills": "skills/",
    "hooks": {
      "Stop": [
        {
          "matcher": "",
          "command": "guardian-skills/hooks/post-agent.sh"
        }
      ]
    }
  }
}
```

After:
```json
{
  "name": "@CaptainClaude/guardian-skills",
  "version": "0.1.0",
  "description": "AI-powered penetration testing skills for Claude Code",
  "keywords": ["claude-code-plugin", "security", "pentesting"],
  "license": "AGPL-3.0",
  "repository": {
    "type": "git",
    "url": "https://github.com/CaptainClaude/guardian"
  }
}
```

- [ ] **Step 2: Verify package.json is valid JSON**

```bash
cat package.json | jq .
```

- [ ] **Step 3: Commit**

```bash
git add package.json
git commit -m "refactor: remove claude-code field from package.json (hooks now in hooks/hooks.json)"
```

---

### Task 4: Add Structured Output to hooks/post-agent.sh

**Files:**
- Modify: `hooks/post-agent.sh`

- [ ] **Step 1: Add structured JSON output for the "no active scan" early exit**

At line 52, the script does:
```bash
SCAN_DIR=$(find_active_scan) || exit 0
```

Change to:
```bash
SCAN_DIR=$(find_active_scan) || { echo '{"status":"skipped","reason":"no active scan"}'; exit 0; }
```

- [ ] **Step 2: Add structured JSON output for the main processing loop**

Replace the entire loop (lines 61-88) with a version that collects transitions and outputs JSON:

```bash
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
SCAN_NAME=$(basename "$SCAN_DIR")
echo "$TRANSITIONS" | jq -c --arg s "$SCAN_NAME" '{"status":"ok","scan":$s,"transitions":.}'
```

- [ ] **Step 3: Verify script syntax**

```bash
bash -n hooks/post-agent.sh
```

Expected: No output (no syntax errors).

- [ ] **Step 4: Commit**

```bash
git add hooks/post-agent.sh
git commit -m "feat: add structured JSON output to post-agent.sh"
```

---

### Task 5: Fix Path References — Orchestrator Skill (guardian)

**Files:**
- Modify: `skills/guardian/SKILL.md`

This is the most reference-heavy skill (20+ `guardian-skills/` references). The orchestrator is special because it dispatches subagents with inline prompts that include paths.

- [ ] **Step 1: Replace all Bash script references with $GUARDIAN_ROOT**

Find and replace every occurrence of `guardian-skills/scripts/` with `"$GUARDIAN_ROOT/scripts/` (or `$GUARDIAN_ROOT/scripts/` where already inside backticks/code blocks). Specifically:

| Line | Old | New |
|------|-----|-----|
| 28 | `bash guardian-skills/scripts/validate-config.sh` | `bash "$GUARDIAN_ROOT/scripts/validate-config.sh"` |
| 150 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 183 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 194 | `bash guardian-skills/scripts/check-queue.sh` | `bash "$GUARDIAN_ROOT/scripts/check-queue.sh"` |
| 198 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 207 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 223 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 290 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 294 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 297 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 300 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 303 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 2: Replace all Read (partial/schema) references with relative paths**

| Line | Old | New |
|------|-----|-----|
| 151 | `guardian-skills/skills/guardian-recon/SKILL.md` | `../guardian-recon/SKILL.md` |
| 188 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 188 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 188 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 200 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 200 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 200 | `guardian-skills/partials/target.md` | `../../partials/target.md` |

- [ ] **Step 3: Verify no remaining guardian-skills/ references**

```bash
grep -c "guardian-skills/" skills/guardian/SKILL.md
```

Expected: `0`

- [ ] **Step 4: Commit**

```bash
git add skills/guardian/SKILL.md
git commit -m "refactor: fix path references in guardian orchestrator skill"
```

---

### Task 6: Fix Path References — Setup and Recon Skills

**Files:**
- Modify: `skills/guardian-setup/SKILL.md`
- Modify: `skills/guardian-recon/SKILL.md`

- [ ] **Step 1: Fix guardian-setup paths**

Replace all `guardian-skills/` references in `skills/guardian-setup/SKILL.md`:

| Line | Old | New |
|------|-----|-----|
| 56 | `bash guardian-skills/scripts/check-dependencies.sh` | `bash "$GUARDIAN_ROOT/scripts/check-dependencies.sh"` |
| 228 | `guardian-skills/schemas/config-schema.json` | `../../schemas/config-schema.json` |
| 357 | `bash guardian-skills/scripts/validate-config.sh` | `bash "$GUARDIAN_ROOT/scripts/validate-config.sh"` |
| 403 | `guardian-skills/scripts/check-dependencies.sh` | `"$GUARDIAN_ROOT/scripts/check-dependencies.sh"` |
| 403 | `chmod +x guardian-skills/scripts/check-dependencies.sh` | `chmod +x "$GUARDIAN_ROOT/scripts/check-dependencies.sh"` |

- [ ] **Step 2: Fix guardian-recon paths**

Replace all `guardian-skills/` references in `skills/guardian-recon/SKILL.md`:

| Line | Old | New |
|------|-----|-----|
| 24 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 25 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 28 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 44 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 144 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 221 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 3: Verify no remaining references**

```bash
grep -c "guardian-skills/" skills/guardian-setup/SKILL.md skills/guardian-recon/SKILL.md
```

Expected: Both `0`.

- [ ] **Step 4: Commit**

```bash
git add skills/guardian-setup/SKILL.md skills/guardian-recon/SKILL.md
git commit -m "refactor: fix path references in setup and recon skills"
```

---

### Task 7: Fix Path References — All 5 Vuln Skills

**Files:**
- Modify: `skills/guardian-vuln-injection/SKILL.md`
- Modify: `skills/guardian-vuln-xss/SKILL.md`
- Modify: `skills/guardian-vuln-auth/SKILL.md`
- Modify: `skills/guardian-vuln-authz/SKILL.md`
- Modify: `skills/guardian-vuln-ssrf/SKILL.md`

All 5 vuln skills share the same reference patterns. Apply these replacements across all 5 files:

- [ ] **Step 1: Fix guardian-vuln-injection paths**

| Line | Old | New |
|------|-----|-----|
| 25 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 26 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 27 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 44 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 195 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 199 | `guardian-skills/schemas/queue-schema.json` | `../../schemas/queue-schema.json` |
| 337 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 2: Fix guardian-vuln-xss paths**

| Line | Old | New |
|------|-----|-----|
| 23 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 24 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 25 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 30 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 43 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 343 | `guardian-skills/schemas/queue-schema.json` | `../../schemas/queue-schema.json` |
| 385 | `bash guardian-skills/scripts/check-queue.sh` | `bash "$GUARDIAN_ROOT/scripts/check-queue.sh"` |
| 394 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 3: Fix guardian-vuln-auth paths**

| Line | Old | New |
|------|-----|-----|
| 26 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 27 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 28 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 46 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 163 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 233 | `guardian-skills/schemas/queue-schema.json` | `../../schemas/queue-schema.json` |
| 417 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 4: Fix guardian-vuln-authz paths**

| Line | Old | New |
|------|-----|-----|
| 25 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 26 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 27 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 32 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 55 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 330 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 5: Fix guardian-vuln-ssrf paths**

| Line | Old | New |
|------|-----|-----|
| 24 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 25 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 26 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 43 | `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` |
| 259 | `guardian-skills/schemas/queue-schema.json` | `../../schemas/queue-schema.json` |
| 297 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 6: Verify no remaining references across all 5 files**

```bash
grep -c "guardian-skills/" skills/guardian-vuln-*/SKILL.md
```

Expected: All `0`.

- [ ] **Step 7: Commit**

```bash
git add skills/guardian-vuln-*/SKILL.md
git commit -m "refactor: fix path references in all 5 vuln skills"
```

---

### Task 8: Fix Path References — All 5 Exploit Skills + methodology.md

**Files:**
- Modify: `skills/guardian-exploit-injection/SKILL.md`
- Modify: `skills/guardian-exploit-xss/SKILL.md`
- Modify: `skills/guardian-exploit-auth/SKILL.md`
- Modify: `skills/guardian-exploit-authz/SKILL.md`
- Modify: `skills/guardian-exploit-ssrf/SKILL.md`
- Modify: `skills/guardian-exploit-auth/references/methodology.md`

- [ ] **Step 1: Fix guardian-exploit-injection paths**

| Line | Old | New |
|------|-----|-----|
| 40 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 41 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 42 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 43 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 59 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 95 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 108 | `guardian-skills/skills/guardian-exploit-injection/references/methodology.md` | `references/methodology.md` |
| 172 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 2: Fix guardian-exploit-xss paths**

| Line | Old | New |
|------|-----|-----|
| 27 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 28 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 29 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 34 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 48 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 62 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 120 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 3: Fix guardian-exploit-auth paths**

| Line | Old | New |
|------|-----|-----|
| 26 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 27 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 28 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 47 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 72 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 109 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 120 | `bash guardian-skills/scripts/update-state.sh` | `bash "$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 4: Fix guardian-exploit-authz paths**

| Line | Old | New |
|------|-----|-----|
| 26 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 27 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 28 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 33 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 47 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 59 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 144 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 5: Fix guardian-exploit-ssrf paths**

| Line | Old | New |
|------|-----|-----|
| 26 | `guardian-skills/partials/target.md` | `../../partials/target.md` |
| 27 | `guardian-skills/partials/rules.md` | `../../partials/rules.md` |
| 28 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 29 | `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` |
| 34 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| 47 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 77 | `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` |
| 94 | `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |

- [ ] **Step 6: Fix methodology.md reference**

In `skills/guardian-exploit-auth/references/methodology.md` line 40:

| Old | New |
|-----|-----|
| `guardian-skills/partials/login-instructions.md` | `../../../partials/login-instructions.md` |

Note: This file is 3 levels deep (`skills/guardian-exploit-auth/references/`), so partials are at `../../../partials/`.

- [ ] **Step 7: Verify no remaining references across all exploit files**

```bash
grep -c "guardian-skills/" skills/guardian-exploit-*/SKILL.md skills/guardian-exploit-*/references/*.md
```

Expected: All `0`.

- [ ] **Step 8: Commit**

```bash
git add skills/guardian-exploit-*/SKILL.md skills/guardian-exploit-auth/references/methodology.md
git commit -m "refactor: fix path references in all 5 exploit skills + methodology.md"
```

---

### Task 9: Fix schemas/queue-schema.json $id

**Files:**
- Modify: `schemas/queue-schema.json`

- [ ] **Step 1: Update the $id field**

Change line 3 from:
```json
"$id": "https://shannon.dev/guardian-skills/queue-schema.json",
```

To:
```json
"$id": "https://github.com/CaptainClaude/guardian/schemas/queue-schema.json",
```

- [ ] **Step 2: Verify valid JSON**

```bash
cat schemas/queue-schema.json | jq .
```

- [ ] **Step 3: Commit**

```bash
git add schemas/queue-schema.json
git commit -m "fix: update queue-schema.json \$id URI to match repository"
```

---

### Task 10: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update installation instructions**

Replace the Installation section:

Before:
```markdown
## Installation

```bash
claude plugin add @CaptainClaude/guardian-skills
```
```

After:
```markdown
## Installation

### From local directory

```bash
claude plugin add /path/to/guardian
```

### From GitHub (when published)

```bash
claude plugin add @CaptainClaude/guardian
```
```

- [ ] **Step 2: Add plugin structure section after Security Notice**

Add:
```markdown
## Plugin Structure

```
guardian/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── hooks/
│   ├── hooks.json           # Hook configuration
│   ├── session-start.sh     # Exports $GUARDIAN_ROOT
│   └── post-agent.sh        # Validates deliverables on Stop
├── partials/                # Shared documentation fragments
├── schemas/                 # JSON schemas (config, queue)
├── scripts/                 # Utility scripts
└── skills/                  # 14 skill directories
```
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README for plugin installation and structure"
```

---

### Task 11: Skill-Creator Audit — Orchestration + Setup + Recon + Report

**Files:**
- Modify: `skills/guardian/SKILL.md`
- Modify: `skills/guardian-setup/SKILL.md`
- Modify: `skills/guardian-recon/SKILL.md`
- Modify: `skills/guardian-report/SKILL.md`

- [ ] **Step 1: Run skill-creator on guardian (orchestrator)**

Invoke the `skill-creator:skill-creator` skill to audit `skills/guardian/SKILL.md`. Focus on:
- Frontmatter: ensure `description` uses third-person with trigger phrases
- Body: check word count (<5,000), structure, progressive disclosure
- Verify it correctly instructs Claude to use `$GUARDIAN_ROOT` for scripts and `../../` for partials

- [ ] **Step 2: Run skill-creator on guardian-setup**

Same audit criteria. Verify the dependency check and config wizard flow is clear.

- [ ] **Step 3: Run skill-creator on guardian-recon**

Same audit criteria. Verify the 6-agent dispatch pattern is clearly structured.

- [ ] **Step 4: Run skill-creator on guardian-report**

Same audit criteria. Verify the report structure template is complete.

- [ ] **Step 5: Apply any fixes from the audits**

Implement recommended changes from each audit. Priority: frontmatter quality, description triggers, body structure.

- [ ] **Step 6: Commit**

```bash
git add skills/guardian/SKILL.md skills/guardian-setup/SKILL.md skills/guardian-recon/SKILL.md skills/guardian-report/SKILL.md
git commit -m "refactor: skill-creator audit for orchestrator, setup, recon, and report skills"
```

---

### Task 12: Skill-Creator Audit — All 5 Vuln Skills

**Files:**
- Modify: `skills/guardian-vuln-injection/SKILL.md`
- Modify: `skills/guardian-vuln-xss/SKILL.md`
- Modify: `skills/guardian-vuln-auth/SKILL.md`
- Modify: `skills/guardian-vuln-authz/SKILL.md`
- Modify: `skills/guardian-vuln-ssrf/SKILL.md`

- [ ] **Step 1: Run skill-creator on all 5 vuln skills**

Invoke the skill-creator to audit each. All 5 should follow an identical structural pattern:
- Same frontmatter format (third-person description, trigger phrases)
- Same section ordering (Role, Prerequisites, Scope, Methodology, Output, State, Completion)
- Same progressive disclosure (heavy methodology in body since no references/ dir)

- [ ] **Step 2: Ensure structural consistency across the 5 skills**

After individual audits, compare the 5 skills to verify:
- Identical Prerequisites section structure (same 7 steps in same order)
- Identical Scope Enforcement section
- Identical State Management section
- Identical Completion section format

- [ ] **Step 3: Apply fixes**

Implement recommended changes. Focus on frontmatter quality and cross-skill consistency.

- [ ] **Step 4: Commit**

```bash
git add skills/guardian-vuln-*/SKILL.md
git commit -m "refactor: skill-creator audit for all 5 vuln skills"
```

---

### Task 13: Skill-Creator Audit — All 5 Exploit Skills

**Files:**
- Modify: `skills/guardian-exploit-injection/SKILL.md`
- Modify: `skills/guardian-exploit-xss/SKILL.md`
- Modify: `skills/guardian-exploit-auth/SKILL.md`
- Modify: `skills/guardian-exploit-authz/SKILL.md`
- Modify: `skills/guardian-exploit-ssrf/SKILL.md`

- [ ] **Step 1: Run skill-creator on all 5 exploit skills**

Audit each. All 5 should follow an identical structural pattern:
- Same frontmatter format
- Same section ordering (Role, Authorization Context, Prerequisites, Scope, Target Preflight, Methodology, Verdict, State, Completion)
- Progressive disclosure via `references/methodology.md`

- [ ] **Step 2: Ensure structural consistency**

After audits, verify:
- Identical Authorization Context section (same text across all 5)
- Identical Target Preflight section
- Identical Verdict Classifications
- Identical State Management section
- `references/methodology.md` is referenced correctly (relative path `references/methodology.md`)

- [ ] **Step 3: Apply fixes**

Implement changes. Focus on frontmatter and consistency.

- [ ] **Step 4: Commit**

```bash
git add skills/guardian-exploit-*/SKILL.md
git commit -m "refactor: skill-creator audit for all 5 exploit skills"
```

---

### Task 14: Final Verification — Path References

- [ ] **Step 1: Verify zero remaining guardian-skills/ references**

```bash
grep -r "guardian-skills/" skills/ schemas/ hooks/ partials/ scripts/ package.json README.md
```

Expected: No matches.

- [ ] **Step 2: Verify all scripts reference $GUARDIAN_ROOT**

```bash
grep -r 'GUARDIAN_ROOT' skills/ | head -30
```

Expected: Every bash script reference uses `$GUARDIAN_ROOT/scripts/`.

- [ ] **Step 3: Verify all Read references use ../../ relative paths**

```bash
grep -r '\.\./\.\.' skills/ | head -30
```

Expected: Partial and schema references use `../../partials/` and `../../schemas/`.

- [ ] **Step 4: Verify hooks.json references use ${CLAUDE_PLUGIN_ROOT}**

```bash
cat hooks/hooks.json | grep CLAUDE_PLUGIN_ROOT
```

Expected: Both hook commands use `${CLAUDE_PLUGIN_ROOT}`.

- [ ] **Step 5: Verify .claude-plugin/plugin.json exists**

```bash
cat .claude-plugin/plugin.json | jq .name
```

Expected: `"guardian"`

---

### Task 15: Verification — Install and Test in Fresh Session

This task MUST be done in a separate Claude Code session.

- [ ] **Step 1: Install plugin locally**

```bash
claude plugin add /path/to/guardian
```

- [ ] **Step 2: Start a new session and verify GUARDIAN_ROOT**

```bash
echo $GUARDIAN_ROOT
```

Expected: Absolute path to the installed plugin directory.

- [ ] **Step 3: Invoke /guardian-setup**

Verify:
- `check-dependencies.sh` executes (not "file not found")
- Schema reference (`../../schemas/config-schema.json`) resolves when Claude reads it
- `validate-config.sh` executes

- [ ] **Step 4: Test a vuln skill — invoke /guardian-vuln-injection**

Verify:
- Partials load (`../../partials/target.md`, `../../partials/rules.md`, `../../partials/scope-vuln.md`)
- State script executes (`$GUARDIAN_ROOT/scripts/update-state.sh`)
- Queue schema reference resolves (`../../schemas/queue-schema.json`)

- [ ] **Step 5: Test an exploit skill — invoke /guardian-exploit-injection**

Verify:
- Partials load
- `references/methodology.md` loads (relative to skill dir)
- State script executes

- [ ] **Step 6: Test session stop**

Trigger a session stop. Verify:
- `post-agent.sh` fires
- Structured JSON output appears in hook results

- [ ] **Step 7: Test /guardian orchestrator**

Verify:
- Cross-skill reference (`../guardian-recon/SKILL.md`) resolves
- All script and partial references resolve within subagent prompts
