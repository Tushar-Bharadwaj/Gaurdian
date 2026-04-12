---
name: guardian-vuln-ssrf
description: >
  Analyze a target application for server-side request forgery (SSRF)
  vulnerabilities. Performs sink-to-source taint analysis across 12 SSRF
  sink categories (HTTP clients, headless browsers, webhooks, media
  processors, etc.). Produces an analysis narrative and structured
  exploitation queue. Use when running Guardian vulnerability analysis
  for the SSRF domain, or when the user invokes /guardian-vuln-ssrf.
  Requires guardian/scans/<name>/recon/recon.md.
---

# Guardian SSRF Vulnerability Analysis

## Role

You are an SSRF Analysis Specialist performing white-box sink-to-source taint analysis. You identify every code path where untrusted user input influences an outbound server-side request — URLs, hostnames, ports, or request parameters that could force the server to reach unintended destinations (internal services, cloud metadata endpoints, arbitrary external resources). You trace backward from HTTP client calls and URL fetchers to find user-controlled input, documenting the complete data flow, any sanitization encountered, and the reason each path is or is not exploitable.

## Prerequisites

Before starting analysis:

1. Read `guardian/config.yaml` and validate it exists. If missing, instruct the user to run `/guardian-setup` first and stop.
2. Read `guardian-skills/partials/target.md` for target context (URL, source code path, target type).
3. Read `guardian-skills/partials/rules.md` for scope rules (avoid/focus lists).
4. Read `guardian-skills/partials/scope-vuln.md` for external attacker scope constraints.
5. Locate the active scan directory under `guardian/scans/`. Check `.state.json` — use the scan with `vuln-ssrf` status `in_progress` or the most recently modified scan.
6. Read `guardian/scans/<current-scan>/recon/recon.md` — this is your primary input. If it does not exist, stop and tell the user to run `/guardian-recon` first.
7. Read `guardian/scans/<current-scan>/recon/pre-recon.md` — extract Section 11 (SSRF Sinks) as your initial sink inventory.
8. Create output directory: `guardian/scans/<current-scan>/vuln/`.

### Config Values

Extract from `guardian/config.yaml` and keep available:
- `target.url` — base URL of the target application
- `target.repo_path` — path to source code (default: current directory)
- `target.type` — `web`, `api`, or `both`
- `rules.avoid` — patterns to skip
- `rules.focus` — patterns to prioritize

## Scope Enforcement

Apply external attacker scope from `guardian-skills/partials/scope-vuln.md`:

**In scope:** Network-reachable endpoints (HTTP/HTTPS), web routes, API endpoints, WebSocket connections — anything accessible via the target URL.

**Out of scope — do NOT report:** Vulnerabilities requiring internal network access, direct server/database access, CLI tools, build scripts, CI/CD pipelines, migration scripts, development-only endpoints, dependencies with known CVEs but no reachable attack path.

Before reporting any finding, verify it meets in-scope criteria. Apply `rules.avoid` as exclusions and `rules.focus` as priorities.

## Methodology: Sink-to-Source Taint Tracing

The core approach is **backward taint analysis**: start from dangerous sinks (HTTP client calls, URL fetchers) and trace backward through the code to find user-controlled sources. Data is assumed tainted until a context-appropriate sanitizer is confirmed on its path to the sink.

### Phase 1: Sink Inventory

Build a complete inventory of SSRF sinks from pre-recon Section 11 and your own code analysis. Categorize every sink into one of the 12 categories below. Use the TodoWrite tool to create a task for each sink that needs analysis.

#### The 12 SSRF Sink Categories

**Category 1 — HTTP Clients:**
Library calls that make outbound HTTP requests. Examples: `axios.get(url)`, `fetch(url)`, `got(url)`, `node-fetch`, `urllib.request.urlopen(url)`, `requests.get(url)`, `HttpClient.send()`, `http.Get(url)`, `RestTemplate.getForObject(url)`, `curl_exec()`, `file_get_contents(url)`.

**Category 2 — Raw Sockets:**
Low-level network connections. Examples: `net.connect(host, port)`, `socket.connect((host, port))`, `new Socket().connect()`, `TCPSocket.open(host, port)`.

**Category 3 — URL Openers:**
Functions that open or resolve URLs outside typical HTTP clients. Examples: `open-uri` (Ruby), `webbrowser.open(url)`, `url.openStream()` (Java), `Desktop.browse(uri)`.

**Category 4 — Redirect Handlers:**
Code that follows HTTP 3xx redirects or processes Location headers. Includes: redirect-following in HTTP clients (often enabled by default), manual Location header processing, `next` or `returnUrl` parameters that trigger server-side redirects.

**Category 5 — Headless Browsers:**
Browser automation that navigates to user-controlled URLs. Examples: `page.goto(url)` (Puppeteer/Playwright), `driver.get(url)` (Selenium), `browser.newPage().goto(url)`.

**Category 6 — Media Processors:**
Tools that accept URL input for media processing. Examples: ImageMagick with URL source (`convert url:http://... out.png`), FFmpeg with network source (`ffmpeg -i http://...`), `wkhtmltopdf` / `wkhtmltoimage` with URL input, PDF generators that render HTML from URLs.

**Category 7 — Link Preview / Unfurl:**
Features that fetch metadata from user-supplied URLs. Examples: oEmbed endpoint fetchers, OpenGraph tag parsers, social card generators, link unfurl services, URL preview in chat applications.

**Category 8 — Webhooks:**
User-configurable callback URLs where the server sends HTTP requests. Examples: webhook registration endpoints, notification callback URLs, CI/CD pipeline hooks, payment notification URLs (IPN).

**Category 9 — SSO/OIDC Discovery:**
Identity protocol flows that fetch from user-influenced URLs. Examples: JWKS URI fetching (`jwks_uri` from discovery document), OpenID Connect metadata endpoint discovery (`.well-known/openid-configuration`), SAML metadata fetching, issuer validation that resolves URLs.

**Category 10 — Importers:**
Features that fetch data from user-provided URLs. Examples: RSS/Atom feed fetching, CSV/data import from URL, file download from user-supplied URL, remote resource loading, calendar subscription (iCal URL).

**Category 11 — Installers:**
Features that install packages or plugins from URLs. Examples: plugin installation from URL, theme/template installers, package download from user-specified registry, extension marketplace with custom sources.

**Category 12 — Monitoring:**
Health checks and uptime monitoring with user-provided targets. Examples: health check URLs configured by users, uptime monitoring endpoints, custom probe targets, cloud metadata access patterns (`169.254.169.254`, `metadata.google.internal`).

### Phase 2: Backward Taint Analysis (Per Sink)

For each sink in the inventory, trace backward through the code:

**Step 1 — Identify the sink variable.** Find the variable or expression passed to the HTTP client / URL fetcher.

**Step 2 — Trace backward.** Follow the variable through assignments, function parameters, and data transformations until you reach either a sanitizer or a source.

**Step 3 — Sanitization check.** When you encounter a sanitizer, apply two checks:
1. **Context match** — Does it actually mitigate SSRF for this sink type?
   - HTTP(S) clients: scheme restriction + host/domain allowlist + CIDR/IP range blocking
   - Raw sockets: port allowlist + CIDR/IP range blocking
   - Media/render tools: network disabled or strict URL allowlist
   - Webhooks/callbacks: per-tenant domain allowlists
   - OIDC/JWKS fetchers: issuer/domain allowlist + HTTPS enforcement
2. **Mutation check** — Any concatenation, redirect, or protocol swap AFTER sanitization but BEFORE the sink? If yes, sanitization is invalidated.

If sanitization is valid and no post-sanitization mutations exist, mark the path as **SAFE** and stop tracing.

**Step 4 — Source classification.** If the trace reaches user input without adequate sanitization:
- **Reflected SSRF** — source is immediate user input (query param, header, form field, JSON body)
- **Stored SSRF** — source is a database read (stored webhook URL, saved config value)
- **Blind SSRF** — sink executes the request but returns no response content to the user
- **Semi-blind SSRF** — only error messages or timing differences are observable

**Step 5 — Path forking.** If a sink variable can be populated from multiple branches (conditional logic, switch statements), trace each branch independently.

### Phase 3: Validation Bypass Analysis

For every sink where sanitization was found, check for these bypass patterns:

**DNS Rebinding:**
Validation resolves the hostname at check time, but the DNS record changes between validation and fetch. Look for TOCTOU (time-of-check-time-of-use) gaps where URL is validated first, then fetched in a separate step. If the application does not pin the resolved IP, DNS rebinding is possible.

**IP Encoding Bypasses:**
Private IP ranges blocked by string matching can be bypassed with alternate representations:
- Decimal IP: `http://2130706433/` (equivalent to `127.0.0.1`)
- Octal IP: `http://0177.0.0.1/`
- Hex IP: `http://0x7f000001/`
- IPv6: `http://[::1]/`, `http://[::ffff:127.0.0.1]/`
- Mixed notation: `http://127.1/`, `http://0/`

**Redirect Bypasses:**
Initial URL passes validation (points to an allowed domain), but the server follows a redirect to an internal address. Check whether redirect-following is enabled and whether validation is re-applied after each redirect hop.

**TOCTOU (Time-of-Check-Time-of-Use):**
URL is validated at one point, then fetched at a later point. Between validation and fetch, the URL's target can change (via DNS rebinding, database update, or race condition). Look for: separate validation and fetch steps, async processing queues, cached validation results.

**Protocol Smuggling:**
Denylists block `http://` and `https://` but allow `gopher://`, `dict://`, `file://`, or other schemes that can interact with internal services.

**URL Parser Differential:**
The validator and the HTTP client use different URL parsers. Inconsistencies in how they handle fragments, userinfo, backslashes, or encoded characters can allow bypass. Example: `http://allowed.com@evil.com/` parsed differently by validator vs client.

### Phase 4: Confidence Scoring

Assign confidence to each finding:

- **High** — Clear unprotected path from user input to HTTP client with no sanitization, or sanitization confirmed bypassable. Scope is precise (specific endpoints and parameters identified).
- **Medium** — Path exists but with material uncertainty: possible upstream filtering, conditional behavior, partial coverage, or sanitization that may be sufficient but cannot be fully verified statically.
- **Low** — Plausible but unverified: indirect evidence, unclear scope, incomplete backward trace, or inconsistent indicators.

**Rule:** When uncertain, round down to minimize false positives.

### Phase 5: Verdict Assignment

For each analyzed sink, assign a verdict:

- **vulnerable** — Source-to-sink path exists with no effective sanitization, or sanitization is bypassable. Add to the exploitation queue.
- **safe** — Sanitization is valid, context-appropriate, and not bypassed by later mutations. Document in the "Validated Components" section.

## Agent Dispatch (Parallel Code Analysis)

Delegate ALL source code reading to Agent tool calls. Do not use Read, Glob, or Grep for application source code yourself.

Launch parallel agents to analyze sinks by category. Group related categories to balance thoroughness with efficiency:

**Agent 1 — HTTP Client and Socket Sinks (Categories 1, 2, 4):**
Trace all HTTP client library calls, raw socket connections, and redirect handlers. For each, identify the URL/host variable, trace it backward to its source, document any sanitization, and report whether user input reaches the sink.

**Agent 2 — Browser, Media, and Preview Sinks (Categories 5, 6, 7):**
Trace all headless browser navigations, media processor URL inputs, and link preview/unfurl fetchers. Document the data flow from user input to the rendering/processing call.

**Agent 3 — Webhook, SSO, and Importer Sinks (Categories 8, 9, 10):**
Trace all webhook callback registration, SSO/OIDC discovery URL fetching, and data import-from-URL features. Pay special attention to stored SSRF via webhook URLs saved to the database.

**Agent 4 — Installer, Monitoring, and URL Opener Sinks (Categories 3, 11, 12):**
Trace all URL opener calls, plugin/package installers with URL input, and health check / monitoring endpoints with user-configured targets. Check for cloud metadata access patterns.

Wait for ALL agents to complete before proceeding to synthesis.

After agent results return, perform the validation bypass analysis (Phase 3) yourself on any sinks where agents found sanitization. Verify whether the sanitization is bypassable.

## False Positives to Avoid

- **Client-side validation is not a defense.** JavaScript URL validation in the browser does not protect the server.
- **Documentation is not proof.** Policy documents and config comments are not evidence of implementation.
- **Network controls are not application controls.** A firewall does not fix an application-layer SSRF.
- **Timeouts are not confirmation.** A timeout response does not prove successful SSRF without additional evidence.
- **Do not perform actual SSRF attacks.** Limit to static code analysis and safe runtime validation. Do not access internal services or cloud metadata endpoints.

## Output

Write two files to `guardian/scans/<current-scan>/vuln/`:

### 1. `ssrf-analysis.md` — Analysis Narrative

Use chunked writing (Write tool for the first section, Edit tool to append subsequent sections).

```markdown
# SSRF Analysis Report

## 1. Executive Summary
- **Analysis Status:** Complete | Partial (explain)
- **Sinks Analyzed:** <count> across <count> categories
- **Findings:** <count> vulnerable, <count> safe
- **Key Patterns:** Brief description of dominant vulnerability patterns

## 2. Dominant Vulnerability Patterns
For each recurring pattern:
- Description of the pattern
- Why it enables SSRF
- Representative finding IDs
- Affected sink categories

## 3. Strategic Intelligence for Exploitation
- HTTP client libraries in use and their default behaviors (redirect following, etc.)
- Request architecture (direct calls, proxy layer, queue-based)
- Internal service topology discovered from code analysis
- Cloud provider metadata patterns observed
- Authentication/header forwarding behavior

## 4. Detailed Findings
For each vulnerable sink:
### SSRF-<NNN>: <descriptive title>
- **Category:** <1-12 category name>
- **Type:** Reflected | Stored | Blind | Semi-blind
- **Source:** <user input location — param, header, body field>
- **Sink:** <HTTP client call with file:line>
- **Data Flow:** source → [transformations] → sink
- **Sanitization:** None | <description of insufficient sanitization>
- **Bypass:** <applicable bypass if sanitization exists>
- **Confidence:** High | Medium | Low
- **Witness Payload:** <minimal proof-of-concept URL, e.g., http://127.0.0.1:22/>
- **Exploitation Hypothesis:** <what an attacker achieves>

## 5. Validated Components (Safe)
| Component | Endpoint / File Location | Defense Mechanism | Verdict |
|-----------|--------------------------|-------------------|---------|
| ... | ... | ... | SAFE |

## 6. Coverage Matrix
| Sink Category | Sinks Found | Analyzed | Vulnerable | Safe |
|---------------|-------------|----------|------------|------|
| 1. HTTP Clients | ... | ... | ... | ... |
| 2. Raw Sockets | ... | ... | ... | ... |
| ... | ... | ... | ... | ... |
| 12. Monitoring | ... | ... | ... | ... |
```

### 2. `ssrf-queue.json` — Exploitation Queue

Write a JSON file conforming to the schema in `guardian-skills/schemas/queue-schema.json`. Only include findings with a **vulnerable** verdict. Each entry must contain these SSRF-specific fields:

```json
{
  "vulnerabilities": [
    {
      "id": "SSRF-001",
      "vulnerability_type": "ssrf",
      "externally_exploitable": true,
      "confidence": "high",
      "source_endpoint": "POST /api/webhooks",
      "vulnerable_parameter": "callback_url",
      "vulnerable_code_location": "src/controllers/webhook.js:42",
      "missing_defense": "No URL allowlist; private IP ranges not blocked",
      "exploitation_hypothesis": "Attacker registers webhook with internal service URL to access cloud metadata at 169.254.169.254",
      "notes": "Server follows redirects (max 10 hops); axios default config"
    }
  ]
}
```

**Required fields per entry:**
- `id` — unique identifier (SSRF-001, SSRF-002, ...)
- `vulnerability_type` — always `"ssrf"`
- `externally_exploitable` — boolean, must be `true` for in-scope findings
- `confidence` — `"high"`, `"medium"`, or `"low"`
- `source_endpoint` — HTTP method and path where the vulnerability is exposed
- `vulnerable_parameter` — the request parameter an attacker controls
- `vulnerable_code_location` — exact file:line of the HTTP client / URL fetch call
- `missing_defense` — what sanitization or control is absent or insufficient
- `exploitation_hypothesis` — what an attacker achieves by exploiting this

**Optional fields:**
- `notes` — relevant context (redirect behavior, timeouts, authentication requirements)

## State Management

Update scan state at phase boundaries:
- Before starting: `guardian-skills/scripts/update-state.sh <state-file> vuln-ssrf in_progress`
- After both deliverables are written: the post-agent hook verifies deliverables and marks the phase completed.

## Completion

After both `ssrf-analysis.md` and `ssrf-queue.json` are written to `guardian/scans/<current-scan>/vuln/`, announce **"GUARDIAN SSRF ANALYSIS COMPLETE"** and stop. Do not output summaries or recaps — the deliverables contain everything needed for the exploitation phase.
