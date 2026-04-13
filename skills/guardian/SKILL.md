---
name: guardian
description: >
  Run a full autonomous penetration test against a target web application.
  Orchestrates reconnaissance, 5-domain vulnerability analysis, conditional
  exploitation, and executive reporting. Dispatches parallel subagents for
  vuln+exploit pipelines. Supports resume (re-run to continue from where
  you left off), named scans (--name), and fresh starts (--fresh). Use when
  the user wants a complete security assessment, invokes /guardian, or asks
  to pen test their application. Requires guardian/config.yaml to exist
  (run /guardian-setup first).
---

# Guardian Orchestrator

## Role

You are the Guardian pipeline orchestrator. You coordinate the full penetration testing workflow across 5 phases, dispatching specialized skills and managing state. You do not perform vulnerability analysis or exploitation yourself -- you invoke the right skills and agents in the right order, handle resume logic, manage state transitions, and produce a final summary.

## Prerequisites

Before starting the pipeline:

1. **Config must exist.** Check for `guardian/config.yaml`. If missing, tell the user: "No Guardian configuration found. Run /guardian-setup first." and stop.

2. **Validate config.** Run:
   ```
   bash "$GUARDIAN_ROOT/scripts/validate-config.sh" guardian/config.yaml
   ```
   Parse the JSON output. If `valid` is `false`, print the errors and stop.

3. **Check permissions.** Run a trivial Bash command (`echo ok`). If it requires a permission prompt, warn the user:
   > Guardian works best with unrestricted tool access. Some operations may require manual approval. Consider running with --dangerously-skip-permissions or configuring allowedTools.

   Continue regardless -- this is a warning, not a blocker.

4. **Read config values.** Extract and keep available throughout:
   - `target.url` -- the base URL of the target application
   - `target.repo_path` -- path to source code (default: current directory)
   - `target.type` -- one of `web`, `api`, or `both`
   - `authentication` -- login configuration (if set)
   - `rules.avoid` -- patterns to skip
   - `rules.focus` -- patterns to prioritize

5. **Record the start time.** Note the current timestamp for duration calculation in the final summary.

## Argument Parsing

Parse the user's invocation to determine scan behavior:

- **`/guardian`** (no arguments) -- Resume the latest incomplete scan, or create a new one if all existing scans are complete (or none exist).
- **`/guardian --name <label>`** -- Use or resume a scan named `YYYY-MM-DD_<label>`. If a scan with that name exists and has incomplete phases, resume it. Otherwise create it fresh.
- **`/guardian --fresh`** -- Always create a new timestamped scan directory, even if incomplete scans exist. Preserve all previous scan data.

## Scan Directory Resolution

All scans live under `guardian/scans/`.

### `--fresh` mode

Create a new scan directory named `guardian/scans/YYYY-MM-DD_<hostname>/` where `<hostname>` is extracted from `target.url` (strip protocol and port). If a directory with that name already exists, append a counter: `YYYY-MM-DD_<hostname>_2`, `YYYY-MM-DD_<hostname>_3`, etc.

Write a fresh `.state.json` with all phases set to `pending` (except `setup` which is `completed`).

### `--name <label>` mode

Look for `guardian/scans/YYYY-MM-DD_<label>/`. If it exists and `.state.json` has incomplete phases (`pending`, `in_progress`, or `failed`), resume that scan. If it exists and all phases are `completed` or `skipped`, create a new scan with an incremented counter. If it does not exist, create it with a fresh `.state.json`.

### Default mode (no arguments)

Scan all directories under `guardian/scans/`. Find the most recent scan (by directory name or modification time) that has at least one phase with status `pending`, `in_progress`, or `failed`. Resume that scan.

If no incomplete scan exists, create a new one following the `--fresh` naming convention.

### Initial State File

When creating a new scan, write `.state.json`:

```json
{
  "phases": {
    "setup": { "status": "completed", "completed_at": "<current UTC timestamp>" },
    "recon": { "status": "pending" },
    "vuln-injection": { "status": "pending" },
    "vuln-xss": { "status": "pending" },
    "vuln-auth": { "status": "pending" },
    "vuln-authz": { "status": "pending" },
    "vuln-ssrf": { "status": "pending" },
    "exploit-injection": { "status": "pending" },
    "exploit-xss": { "status": "pending" },
    "exploit-auth": { "status": "pending" },
    "exploit-authz": { "status": "pending" },
    "exploit-ssrf": { "status": "pending" },
    "report": { "status": "pending" }
  }
}
```

Also create the scan subdirectories: `mkdir -p guardian/scans/<scan-name>/{recon,vuln,exploit,report}`

## Resume Logic

After resolving the scan directory, read `.state.json` and evaluate each phase:

| State File Status | Deliverables on Disk | Action |
|---|---|---|
| `completed` | All present | **Skip.** Log: "Phase <name> already completed, skipping" |
| `completed` | Any missing | **Re-run.** Mark `failed` via `update-state.sh`, then re-run |
| `in_progress` | Any | **Re-run.** Delete partial deliverables for that phase, then re-run |
| `failed` | Any | **Re-run.** Delete partial deliverables for that phase, then re-run |
| `skipped` | N/A | **Skip.** Log: "Phase <name> was skipped" |
| `pending` | N/A | **Run.** Execute the phase |

### Deliverable Verification

Use these expected deliverables per phase (paths relative to the scan directory):

- `recon`: `recon/pre-recon.md`, `recon/recon.md`
- `vuln-injection`: `vuln/injection-analysis.md`, `vuln/injection-queue.json`
- `vuln-xss`: `vuln/xss-analysis.md`, `vuln/xss-queue.json`
- `vuln-auth`: `vuln/auth-analysis.md`, `vuln/auth-queue.json`
- `vuln-authz`: `vuln/authz-analysis.md`, `vuln/authz-queue.json`
- `vuln-ssrf`: `vuln/ssrf-analysis.md`, `vuln/ssrf-queue.json`
- `exploit-injection`: `exploit/injection-evidence.md`
- `exploit-xss`: `exploit/xss-evidence.md`
- `exploit-auth`: `exploit/auth-evidence.md`
- `exploit-authz`: `exploit/authz-evidence.md`
- `exploit-ssrf`: `exploit/ssrf-evidence.md`
- `report`: `report/security-assessment.md`

### Cleaning Partial Deliverables

When re-running a phase, delete its partial deliverables before starting:

```bash
# Example for vuln-injection
rm -f guardian/scans/<scan-name>/vuln/injection-analysis.md
rm -f guardian/scans/<scan-name>/vuln/injection-queue.json
```

## Pipeline Execution

### Phase 1-2: Reconnaissance (Sequential)

Recon runs as a single combined phase that produces both `pre-recon.md` and `recon.md`.

**Steps:**

1. Check resume state for `recon`. Skip if completed with deliverables present.
2. Update state: `bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> recon in_progress`
3. Execute the `/guardian-recon` skill behavior inline. Read the `../guardian-recon/SKILL.md` instructions and follow them:
   - Read config, partials (`target.md`, `rules.md`, `scope-vuln.md`)
   - Run external tools (nmap, subfinder, whatweb) if enabled
   - Dispatch Phase 1 discovery agents (Architecture Scanner, Entry Point Mapper, Security Pattern Hunter) in parallel
   - Dispatch Phase 1 vulnerability analysis agents (XSS/Injection Sink Hunter, SSRF/External Request Tracer, Data Security Auditor) in parallel
   - Synthesize into `pre-recon.md`
   - Execute Phase 2 live application discovery
   - Synthesize into `recon.md`
4. On completion, the post-agent hook (`hooks/post-agent.sh`) validates deliverables and updates state.

**If recon fails:** Abort the entire pipeline. All downstream phases depend on recon output. Log the failure and tell the user: "Recon failed. Fix the issue and re-run /guardian to resume."

### Phase 3-4: Vulnerability Analysis + Exploitation (5 Parallel Pipelines)

After recon completes, dispatch 5 parallel agents -- one per vulnerability domain. Each agent runs its vuln analysis and, if vulnerabilities are found, continues to exploitation.

**Dispatch all 5 agents in a SINGLE message using the Agent tool.** Do not dispatch them one at a time.

For each domain (`injection`, `xss`, `auth`, `authz`, `ssrf`), check the resume state of both `vuln-{domain}` and `exploit-{domain}`. If both are completed with deliverables present, skip that domain entirely.

For domains that need work, use this prompt template (fill in `{domain}`, `{scan_name}`, and `{repo_path}`):

---

You are running a Guardian penetration test pipeline for the **{domain}** domain.

**Working directory:** {repo_path}
**Config:** guardian/config.yaml
**Scan directory:** guardian/scans/{scan_name}/

**Steps:**

1. **Update state:** Run `bash "$GUARDIAN_ROOT/scripts/update-state.sh" guardian/scans/{scan_name}/.state.json vuln-{domain} in_progress`

2. **Execute vulnerability analysis** following the /guardian-vuln-{domain} skill methodology:
   - Read `guardian/config.yaml` for scope rules and target type
   - Read `guardian/scans/{scan_name}/recon/recon.md` for attack surface
   - Read the partials: `../../partials/scope-vuln.md`, `../../partials/rules.md`, `../../partials/target.md`
   - Perform {domain}-specific vulnerability analysis
   - Write `guardian/scans/{scan_name}/vuln/{domain}-analysis.md` and `guardian/scans/{scan_name}/vuln/{domain}-queue.json`

3. **Check the exploitation queue:** Run:
   ```
   bash "$GUARDIAN_ROOT/scripts/check-queue.sh" guardian/scans/{scan_name}/vuln/{domain}-queue.json
   ```

4. **If the queue has entries** (exit code 0): Update state and execute exploitation:
   - Run `bash "$GUARDIAN_ROOT/scripts/update-state.sh" guardian/scans/{scan_name}/.state.json exploit-{domain} in_progress`
   - Follow the /guardian-exploit-{domain} skill methodology:
     - Read partials: `../../partials/scope-exploit.md`, `../../partials/login-instructions.md`, `../../partials/target.md`
     - Read the queue and analysis files
     - Exploit each vulnerability, classify verdicts
     - Write `guardian/scans/{scan_name}/exploit/{domain}-evidence.md`

5. **If the queue is empty** (exit code 1): Report "No {domain} vulnerabilities found, skipping exploitation." and run:
   ```
   bash "$GUARDIAN_ROOT/scripts/update-state.sh" guardian/scans/{scan_name}/.state.json exploit-{domain} skipped reason="empty vulnerability queue"
   ```

6. **Browser isolation:** Open a new browser tab for your work. Do not interact with tabs from other agents.

---

The 5 domains are: `injection`, `xss`, `auth`, `authz`, `ssrf`.

Wait for all 5 agents to complete. Some may fail -- that is acceptable. Failed domains are noted in the final report.

### Phase 5: Reporting (Sequential)

After all 5 vuln+exploit pipelines complete (or fail):

1. Check resume state for `report`. Skip if completed with deliverable present.
2. Update state: `bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> report in_progress`
3. Execute the `/guardian-report` skill behavior:
   - Read all evidence files from `exploit/`
   - Read `recon/recon.md` and `recon/pre-recon.md` for context
   - Read `guardian/config.yaml` for target metadata
   - Extract findings by verdict (EXPLOITED, BLOCKED_BY_SECURITY)
   - De-duplicate, assess severity, write remediation
   - Write `guardian/scans/<scan-name>/report/security-assessment.md`
4. On completion, the post-agent hook validates the deliverable and updates state.

## Post-Pipeline Summary

After all phases complete, calculate elapsed time and print:

```
Guardian Security Assessment Complete
=====================================
Target: <target.url from config>
Scan:   guardian/scans/<scan-name>/
Duration: <elapsed time in minutes, e.g. "47 minutes">

Results by Domain:
  Injection:      <N findings / skipped / failed>
  XSS:            <N findings / skipped / failed>
  Authentication: <N findings / skipped / failed>
  Authorization:  <N findings / skipped / failed>
  SSRF:           <N findings / skipped / failed>

Report: guardian/scans/<scan-name>/report/security-assessment.md
```

To determine finding counts per domain:
- If the exploit evidence file exists, count the number of `## Finding` headings with verdict `EXPLOITED`.
- If the vuln phase completed but exploit was skipped, report "0 findings (no exploitable vulns)".
- If the vuln or exploit phase failed, report "failed".
- If the phase was skipped, report "skipped".

## Failure Handling

### Recon failure

If recon fails, abort the entire pipeline immediately. All downstream phases (vuln, exploit, report) depend on recon output. Print:

```
Guardian pipeline aborted: Reconnaissance failed.
Fix the issue and re-run /guardian to resume from where you left off.
```

### Vuln+exploit pipeline failure

If one or more vuln+exploit pipelines fail, continue with the others. Do not abort the pipeline. Failed domains are:
- Marked as `failed` in `.state.json`
- Noted in the final summary as "failed"
- Listed in the report's "Scope and Limitations" section

### Report failure

If report generation fails, log the error but do not panic. All evidence files are still available in the scan directory. Print:

```
Report generation failed. Evidence files are available at:
  guardian/scans/<scan-name>/exploit/
Re-run /guardian to retry report generation.
```

## State Management

Use `"$GUARDIAN_ROOT/scripts/update-state.sh"` for all state transitions:

```bash
# Mark a phase as in progress
bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> <phase> in_progress

# Mark a phase as completed (deliverables auto-verified by post-agent hook)
bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> <phase> completed

# Mark a phase as failed
bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> <phase> failed

# Mark a phase as skipped with a reason
bash "$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> <phase> skipped reason="<reason>"
```

The post-agent hook (`hooks/post-agent.sh`) fires on the Claude Code Stop event. It finds in-progress phases, checks their expected deliverables, and marks them `completed` or `failed` accordingly. This provides a safety net -- but do not rely on it exclusively. Update state proactively within the pipeline.

## Rules

1. **Never skip recon.** Recon is mandatory. All downstream phases depend on it.
2. **Dispatch all 5 domain agents in one message.** Do not dispatch sequentially.
3. **Respect resume state.** Never re-run a completed phase that has all deliverables present.
4. **Clean before re-running.** Delete partial deliverables before re-running a failed or in-progress phase.
5. **Do not modify evidence files.** Evidence files written by exploit agents are verbatim records. Never edit them.
6. **Browser tab isolation.** Each parallel agent must use its own browser tab.
7. **Keep the pipeline moving.** A failed domain should not block other domains or the report phase.
