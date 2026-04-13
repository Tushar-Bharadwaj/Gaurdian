# Guardian Plugin Conversion Design

## Summary

Convert Guardian from an npm-style package (`package.json` with `claude-code` field) to a proper Claude Code plugin with correct path resolution, structured hook output, and skill-creator-audited skills.

## Problem

1. **No plugin manifest**: Missing `.claude-plugin/plugin.json` (required for Claude Code plugin discovery).
2. **Broken hooks**: `post-agent.sh` is configured in `package.json` under `claude-code.hooks` — Claude Code plugins use `hooks/hooks.json` with a wrapper format. The hook never fires.
3. **Broken paths**: 80+ references to `guardian-skills/...` assume npm-style installation where the package lands in a known node_modules path. Plugins install to a random cache directory — these paths all fail.
4. **No structured output**: Hook scripts produce no stdout. Claude Code expects structured JSON from hooks.
5. **No skill quality audit**: Skills lack proper frontmatter, trigger descriptions, and may not follow progressive disclosure best practices.

## Design

### 1. Plugin Infrastructure

#### 1.1 New file: `.claude-plugin/plugin.json`

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

#### 1.2 New file: `hooks/hooks.json`

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

#### 1.3 New file: `hooks/session-start.sh`

Exports `GUARDIAN_ROOT` so all skills can reference plugin scripts via `$GUARDIAN_ROOT`:

```bash
#!/usr/bin/env bash
echo "export GUARDIAN_ROOT=\"${CLAUDE_PLUGIN_ROOT}\"" >> "$CLAUDE_ENV_FILE"
```

Structured output:
```json
{"status": "ok", "exported": ["GUARDIAN_ROOT"]}
```

#### 1.4 Modified: `package.json`

Remove the `claude-code` field entirely. Retain npm metadata (name, version, description, license, repository, keywords).

#### 1.5 Modified: `hooks/post-agent.sh`

- Internal path resolution via `dirname "$0"` is already correct (no change needed).
- Add structured JSON output to stdout for all exit paths:
  - Active scan with transitions: `{"status": "ok", "scan": "<name>", "transitions": [...]}`
  - No active scan: `{"status": "skipped", "reason": "no active scan"}`

### 2. Path Conversion

#### 2.1 Read references (partials, schemas, cross-skill)

All `guardian-skills/...` paths in SKILL.md files become relative to the skill's base directory (provided by Claude Code as a header when the skill is invoked via the Skill tool).

| Current | Converted | Notes |
|---------|-----------|-------|
| `guardian-skills/partials/target.md` | `../../partials/target.md` | From `skills/<name>/SKILL.md` |
| `guardian-skills/partials/rules.md` | `../../partials/rules.md` | |
| `guardian-skills/partials/scope-vuln.md` | `../../partials/scope-vuln.md` | |
| `guardian-skills/partials/scope-exploit.md` | `../../partials/scope-exploit.md` | |
| `guardian-skills/partials/login-instructions.md` | `../../partials/login-instructions.md` | |
| `guardian-skills/schemas/config-schema.json` | `../../schemas/config-schema.json` | |
| `guardian-skills/schemas/queue-schema.json` | `../../schemas/queue-schema.json` | |
| `guardian-skills/skills/guardian-recon/SKILL.md` | `../guardian-recon/SKILL.md` | Cross-skill reference |

#### 2.2 Bash references (scripts)

Scripts executed via the Bash tool run in the user's project directory. They use `$GUARDIAN_ROOT` (exported by the SessionStart hook).

| Current | Converted |
|---------|-----------|
| `guardian-skills/scripts/update-state.sh` | `"$GUARDIAN_ROOT/scripts/update-state.sh"` |
| `guardian-skills/scripts/validate-config.sh` | `"$GUARDIAN_ROOT/scripts/validate-config.sh"` |
| `guardian-skills/scripts/check-dependencies.sh` | `"$GUARDIAN_ROOT/scripts/check-dependencies.sh"` |
| `guardian-skills/scripts/check-queue.sh` | `"$GUARDIAN_ROOT/scripts/check-queue.sh"` |

#### 2.3 Unchanged paths

| Path | Reason |
|------|--------|
| `guardian/config.yaml` | Project-relative output |
| `guardian/.env` | Project-relative credentials |
| `guardian/scans/<name>/...` | Project-relative scan outputs |
| `references/methodology.md` | Already relative to skill directory |

#### 2.4 Special case: `hooks/post-agent.sh`

The script internally resolves `SCRIPTS_DIR` via `$(cd "$(dirname "$0")" && pwd)/../scripts`. This works correctly when invoked from its actual location via `${CLAUDE_PLUGIN_ROOT}` in hooks.json. No change needed.

#### 2.5 Special case: `schemas/queue-schema.json`

The `$id` field references `https://shannon.dev/guardian-skills/queue-schema.json`. Update to `https://github.com/CaptainClaude/guardian/schemas/queue-schema.json` to match the repository.

### 3. Skill-Creator Audit

All 14 skills are run through the skill-creator for quality review. Audit criteria:

- **Frontmatter**: Proper `name`, `description` (third-person, with trigger phrases), `version`
- **Body size**: Lean SKILL.md (under 5,000 words), heavy content in `references/`
- **Progressive disclosure**: Partials and references loaded on demand, not inlined
- **Consistency**: Skills within the same category follow identical structure

Skill categories and shared patterns:

| Category | Skills | Pattern |
|----------|--------|---------|
| Orchestration | `guardian` | Full pipeline orchestrator |
| Setup/Recon | `guardian-setup`, `guardian-recon` | Config + discovery |
| Vulnerability (5) | `guardian-vuln-{injection,xss,auth,authz,ssrf}` | Analysis -> queue.json |
| Exploitation (5) | `guardian-exploit-{injection,xss,auth,authz,ssrf}` | Queue -> evidence |
| Report | `guardian-report` | Aggregation -> assessment |

### 4. Verification

After all changes, verify in a **separate Claude Code session** (so the SessionStart hook fires fresh):

1. Install plugin locally: `claude plugin add /path/to/guardian`
2. Verify `GUARDIAN_ROOT` is exported: `echo $GUARDIAN_ROOT`
3. Invoke `/guardian-setup` — confirm `check-dependencies.sh` runs, schema reads work
4. Invoke each vuln skill — confirm partials load, scripts execute, queue JSON validates against schema
5. Invoke each exploit skill — confirm methodology references load, state transitions work
6. Trigger session stop — confirm `post-agent.sh` fires, structured JSON output appears
7. Invoke `/guardian` orchestrator — confirm cross-skill references resolve
8. For each skill, verify Read paths resolve and Bash scripts execute without "file not found"

## Scan Deliverables (unchanged)

All outputs go to `guardian/scans/<scan-name>/` relative to the user's project:

| Phase | Files | Format |
|-------|-------|--------|
| State | `.state.json` | JSON |
| Recon | `recon/pre-recon.md`, `recon/recon.md` | Markdown |
| Vuln (per domain) | `vuln/<domain>-analysis.md`, `vuln/<domain>-queue.json` | Markdown + JSON |
| Exploit (per domain) | `exploit/<domain>-evidence.md` | Markdown |
| Report | `report/security-assessment.md` | Markdown |

Total: 22 deliverables per full scan.

## File Manifest

### New files (4)

| File | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `hooks/hooks.json` | Hook configuration (wrapper format) |
| `hooks/session-start.sh` | Exports GUARDIAN_ROOT to session env |
| `docs/superpowers/specs/2026-04-13-plugin-conversion-design.md` | This spec |

### Modified files (19)

| File | Change |
|------|--------|
| `package.json` | Remove `claude-code` field |
| `hooks/post-agent.sh` | Add structured JSON output |
| `schemas/queue-schema.json` | Fix `$id` URI |
| `README.md` | Updated install instructions |
| `skills/guardian/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-setup/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-recon/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-vuln-injection/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-vuln-xss/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-vuln-auth/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-vuln-authz/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-vuln-ssrf/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-injection/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-xss/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-auth/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-authz/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-ssrf/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-report/SKILL.md` | Path fixes + skill-creator audit |
| `skills/guardian-exploit-auth/references/methodology.md` | Path fix |

### Deleted files (0)

None.
