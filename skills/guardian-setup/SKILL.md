---
name: guardian-setup
version: 0.1.0
description: >
  Use this skill when the user invokes /guardian-setup, wants to configure
  a new pen test target, or before running /guardian for the first time.
  Checks and installs security tool dependencies (nmap, subfinder, whatweb),
  then walks through interactive configuration: target URL, application type,
  authentication, scope rules. Creates guardian/config.yaml and guardian/.env.
  Always run this before any other Guardian skill.
---

# Guardian Setup

Configure Guardian for penetration testing against a target application.

## Why Setup First

Running `/guardian-setup` before any analysis is important because it:
- **Secures credentials** — passwords and API keys go in `guardian/.env` (gitignored, chmod 0600), never in config files that might be committed
- **Defines scope** — avoid rules prevent Guardian from hitting destructive endpoints (e.g., `/admin/delete`) or production payment flows during testing
- **Enables resume** — the state file tracks which phases completed, so if a scan is interrupted, `/guardian` picks up where it left off instead of re-running everything
- **Feeds downstream skills** — all 12 downstream skills (recon, 5 vuln, 5 exploit, report) read from `guardian/config.yaml`. Without setup, they fail with "Run /guardian-setup first"

If the user wants to dive straight into analysis, acknowledge their urgency but explain that setup takes 2-3 minutes and saves significant time downstream.

## Prerequisites

- Claude Code with auto-accept permissions (--dangerously-skip-permissions or allowedTools configured)
- Target application must be running and accessible

> **SSL/TLS note:** All HTTP tools run with certificate verification disabled (`curl -k`,
> `whatweb --no-check-certificate`) so self-signed or expired certificates never block a scan.
> Playwright MCP uses a shared browser context — if the target returns SSL errors during browser
> navigation, the Playwright MCP server must be launched with `--ignore-https-errors`. Add it to
> the `args` array for the `playwright` MCP server entry in `~/.claude/settings.json`:
> ```json
> "playwright": { "args": ["--ignore-https-errors"] }
> ```

## Workflow

### Phase 1: Permission Check

Before doing anything else, verify that you have sufficient tool access.
Attempt a trivial Bash command (`echo ok`) and check that it runs without a
permission prompt.

If the user is NOT running in unrestricted mode, print this warning and ask
them to confirm before continuing:

> Guardian requires unrestricted tool access for penetration testing.
> Run Claude Code with --dangerously-skip-permissions, or configure
> allowedTools in your settings to include Bash, Read, Write, Edit,
> Glob, Grep, and the Playwright MCP tools.

If the user wants to proceed anyway, continue but note that some
operations may require manual approval.

### Phase 2: Dependency Check

Run the dependency checker:

```
bash "$GUARDIAN_ROOT/scripts/check-dependencies.sh"
```

Parse the JSON output. It contains:
- `os` — detected operating system
- `missing_required` — array of missing required tools
- `missing_recommended` — array of missing optional tools
- `available_tools` — array of already-installed optional tools
- `install_commands` — platform-specific install commands (keyed by OS)

**Required tools** (git, curl, jq):
If any are in `missing_required`, tell the user exactly which are missing
and stop. These must be installed manually before Guardian can proceed.

**Recommended tools** (nmap, subfinder, whatweb):
If any are in `missing_recommended`:

1. Explain what each missing tool does:
   - **nmap** — Network port scanner. Discovers open ports and services on the target host. Helps identify attack surface beyond the web application.
   - **subfinder** — Subdomain enumeration tool. Finds related subdomains that may host additional attack surface (staging servers, APIs, admin panels).
   - **whatweb** — Web technology fingerprinter. Identifies frameworks, CMS versions, server software, and other technologies in use. Helps tailor vulnerability checks.

2. Show the platform-specific install commands from the `install_commands` field in the JSON output. Present only the commands for the detected OS.

3. Ask the user:
   "Want me to install these? (They are optional -- Guardian works without them but produces better results with them.)"

4. If yes, run the install commands via Bash and verify each tool is now available.

5. Record which tools are available. You will write these into the config later as the `tools` section.

### Phase 3: Interactive Configuration

Ask questions ONE AT A TIME. Wait for the user's response before
proceeding to the next question. Do not batch questions.

#### Step 1 -- Target URL

Ask: "What is the URL of the application you want to test?"

After receiving the answer:
- Validate reachability: `curl -sk -o /dev/null -w '%{http_code}' <url>`
- If the status code is 000 or the command fails, tell the user the URL
  is unreachable and ask them to verify the application is running.
  Allow them to re-enter the URL or confirm they want to proceed anyway.
- Store the URL for config generation.

#### Step 1b -- Target Type

Ask: "What kind of application is this?"
- (a) Web application (has a UI in the browser)
- (b) API only (REST/GraphQL, no frontend)
- (c) Both (API backend + web frontend)

Map the answer to the config value: `web`, `api`, or `both`.

#### Step 1c -- API Specification

Only ask this if the target type is `api` or `both`.

Ask: "Do you have an OpenAPI/Swagger spec, GraphQL schema, or Postman collection?"

- If yes: ask for the file path or URL. Verify the file exists (if a path)
  or is reachable (if a URL). Store as `target.api_spec`.
- If no: respond with "No problem -- I will discover endpoints from source
  code analysis and runtime probing." and move on.

#### Step 2 -- Source Code Path

Ask: "Is the source code for this application in the current directory, or should I look elsewhere?"

- Default to `.` (the current working directory).
- If the user provides a different path, validate it exists and contains
  code files (check for common indicators: package.json, requirements.txt,
  go.mod, Cargo.toml, pom.xml, composer.json, Gemfile, or any src/ directory).
- If the directory looks empty or wrong, warn and ask for confirmation.
- Store as `target.repo_path`.

#### Step 3 -- Authentication

Ask: "Does the application require authentication to test?"

If no, skip to Step 4.

If yes, ask the following sub-questions one at a time:

**3a -- Login type:**
"What type of login does it use?"
- (a) Form-based (username/password in a web form)
- (b) SSO (Google, GitHub, Okta, etc.)
- (c) API key or token
- (d) HTTP Basic Auth

Map to: `form`, `sso`, `api`, `basic`.

**3b -- Login URL:**
"What is the login URL?" (e.g., https://example.com/login)

Validate reachability the same way as the target URL.

**3c -- Test credentials:**
"What are the test credentials?"
- Ask for the username/email.
- Ask for the password (or API key/token if login type is `api`).

These will be stored in `guardian/.env`, never in the YAML config.

**3d -- TOTP/MFA (optional):**
"Does the login require a TOTP/MFA code? If so, provide the TOTP secret
(the base32 string, not a QR code). Otherwise, just say no."

If provided, store as `GUARDIAN_TOTP_SECRET` in the .env file.

**3e -- Login flow:**
"Can you describe the login flow step by step? For example:"
- Fill the email field with the username
- Fill the password field with the password
- Click the Sign In button

"Or should I try to auto-detect the login flow from the page?"

If the user provides steps, store them as the `authentication.login_flow`
array. Use `$username` and `$password` as placeholders in the steps.

If the user wants auto-detection, note this for later but still write
a placeholder login_flow.

**3f -- Success condition:**
"How do I know login succeeded? Pick one:"
- (a) URL contains a string (e.g., /dashboard)
- (b) URL matches exactly (e.g., https://example.com/home)
- (c) An element appears on the page (provide a CSS selector)
- (d) Page contains specific text

After the user picks, ask for the specific value (the string, URL, selector,
or text to look for).

Map to the `authentication.success_condition` object with `type` and `value`.
Types: `url_contains`, `url_equals_exactly`, `element_present`, `text_contains`.

#### Step 4 -- Scope Rules

Ask: "Are there any areas I should AVOID during testing? For example:
/admin/delete, payment processing endpoints, third-party integrations.
(Enter paths/patterns separated by commas, or say none.)"

Then ask: "Any areas I should FOCUS on? For example: /api/v2, the
authentication system, file upload endpoints.
(Enter paths/patterns separated by commas, or say none.)"

Store as `rules.avoid` and `rules.focus` arrays. If the user says none,
use empty arrays.

#### Step 5 -- Description

Ask: "Anything else I should know about this application? For example:
tech stack, known issues, areas of concern, recent changes. (Optional.)"

Store as the `description` field. If the user skips, omit this field.

### Phase 4: Write Config Files

Create all necessary files from the collected information.

**Step 1 -- Create directory structure:**

```
mkdir -p guardian/scans
```

**Step 2 -- Write guardian/config.yaml:**

Build a YAML file matching the schema in `../../schemas/config-schema.json`.
Structure:

```yaml
target:
  url: <collected URL>
  repo_path: <collected path, default ".">
  type: <web|api|both>
  api_spec: <path or URL, only if provided>

authentication:
  login_type: <form|sso|api|basic>
  login_url: <login URL>
  credentials_env: guardian/.env
  login_flow:
    - "Fill email field with $username"
    - "Fill password field with $password"
    - "Click Sign In button"
  success_condition:
    type: <url_contains|url_equals_exactly|element_present|text_contains>
    value: <the value>

rules:
  avoid:
    - "/admin/delete"
  focus:
    - "/api/v2"

description: "Free-text context about the application"

tools:
  nmap: true
  subfinder: false
  whatweb: true
```

Omit the `authentication` section entirely if the user said no auth.
Omit `api_spec` if not provided. Omit `description` if not provided.
Set each tool boolean based on whether it is installed and available.

**Step 3 -- Write guardian/.env:**

Only write this file if authentication was configured.

```
GUARDIAN_USERNAME=<the username>
GUARDIAN_PASSWORD=<the password>
GUARDIAN_TOTP_SECRET=<the TOTP secret, only if provided>
```

Set file permissions to 0600: `chmod 600 guardian/.env`

**Step 4 -- Write guardian/.gitignore:**

```
.env
.state.json
.state.lock
```

**Step 5 -- Create scan directory:**

Compute the scan name: `<YYYY-MM-DD>_<hostname>` where hostname is
extracted from the target URL (strip protocol and port).

```
mkdir -p guardian/scans/<scan-name>
```

**Step 6 -- Write initial state file:**

Write `guardian/scans/<scan-name>/.state.json` with all pipeline phases
set to `pending`:

```json
{
  "phases": {
    "setup": {
      "status": "completed",
      "completed_at": "<current UTC timestamp>"
    },
    "pre-recon": {
      "status": "pending"
    },
    "recon": {
      "status": "pending"
    },
    "vuln-injection": {
      "status": "pending"
    },
    "vuln-xss": {
      "status": "pending"
    },
    "vuln-auth": {
      "status": "pending"
    },
    "vuln-authz": {
      "status": "pending"
    },
    "vuln-ssrf": {
      "status": "pending"
    },
    "exploit-injection": {
      "status": "pending"
    },
    "exploit-xss": {
      "status": "pending"
    },
    "exploit-auth": {
      "status": "pending"
    },
    "exploit-authz": {
      "status": "pending"
    },
    "exploit-ssrf": {
      "status": "pending"
    },
    "report": {
      "status": "pending"
    }
  }
}
```

**Step 7 -- Validate the config:**

Run the config validator to make sure the generated file is well-formed:

```
bash "$GUARDIAN_ROOT/scripts/validate-config.sh" guardian/config.yaml
```

If validation fails, fix the issue and re-validate.

### Phase 5: Confirmation

Print a summary showing the user what was configured:

```
Guardian configured successfully.

  Target:      <url>
  Type:        <web|api|both>
  Auth:        <login_type or "none">
  Source code: <repo_path>
  Tools:       nmap=<yes|no>, subfinder=<yes|no>, whatweb=<yes|no>
  Avoid:       <list or "none">
  Focus:       <list or "none">

  Config:      guardian/config.yaml
  Credentials: guardian/.env
  Scan dir:    guardian/scans/<scan-name>/
  State:       guardian/scans/<scan-name>/.state.json

Run /guardian to start the full penetration test, or run individual skills:
  /guardian-recon          -- Reconnaissance and attack surface mapping
  /guardian-vuln-injection -- Injection vulnerability analysis
  /guardian-vuln-xss       -- Cross-site scripting analysis
  /guardian-vuln-auth      -- Authentication vulnerability analysis
  /guardian-vuln-authz     -- Authorization vulnerability analysis
  /guardian-vuln-ssrf      -- SSRF vulnerability analysis
  /guardian-report         -- Generate the final security report
```

## Output Files

| File | Purpose |
|------|---------|
| `guardian/config.yaml` | Target configuration (URL, type, auth, scope, tools) |
| `guardian/.env` | Credentials (gitignored, chmod 0600) |
| `guardian/.gitignore` | Prevents secrets and state from being committed |
| `guardian/scans/<name>/.state.json` | Pipeline state tracker (all phases start as pending) |

## Error Handling

- If `check-dependencies.sh` fails to run, check that the script exists and is executable. Run `chmod +x "$GUARDIAN_ROOT/scripts/check-dependencies.sh"` if needed.
- If the target URL is unreachable, do not block setup. Warn the user and let them proceed -- the app may start later.
- If config validation fails after writing, read the error output and fix the YAML. Do not leave an invalid config file.
- If `guardian/.env` already exists, ask before overwriting: "Existing credentials found. Overwrite? (yes/no)"
- If `guardian/config.yaml` already exists, ask before overwriting: "Existing config found. Overwrite or update? (overwrite/update/cancel)"
