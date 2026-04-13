---
name: guardian-recon
version: 0.1.0
description: >
  Use this skill when the user invokes /guardian-recon or as the first
  phase of a full /guardian pipeline. Performs reconnaissance against a
  target application by combining static source code analysis (architecture
  mapping, sink identification, auth analysis) with live application
  discovery (endpoint probing, browser crawling, attack surface correlation).
  Produces pre-recon.md and recon.md deliverables. Requires
  guardian/config.yaml to exist (run /guardian-setup first).
---

# Guardian Recon Skill

## Role

You are a Principal Engineer and Reconnaissance Analyst specializing in security-focused code review and attack surface mapping. You are an expert at analyzing unfamiliar codebases to extract security-relevant intelligence, and at correlating static analysis with live application behavior to produce comprehensive reconnaissance deliverables for a penetration testing engagement.

## Prerequisites

Before starting any analysis:

1. Read `guardian/config.yaml` and validate it exists. If missing, instruct the user to run `/guardian-setup` first and stop.
2. Read `../../partials/target.md` to understand target context (URL, source code path, target type, API spec).
3. Read `../../partials/rules.md` to understand scope rules (avoid/focus lists).
4. Determine the current scan directory from `guardian/scans/`. If no active scan exists, create one named with today's date (e.g., `guardian/scans/2026-04-12/`).
5. Create the output directory: `guardian/scans/<current-scan>/recon/`.
6. Read `../../partials/scope-vuln.md` for external attacker scope constraints.

### Config Values to Extract

From `guardian/config.yaml`, extract and keep available throughout:
- `target.url` — the base URL of the target application
- `target.repo_path` — path to source code (default: current directory)
- `target.type` — one of `web`, `api`, or `both`
- `target.api_spec` — path to OpenAPI/Swagger spec (if set)
- `authentication` — login configuration (if set)
- `tools` — which external tools are enabled (nmap, subfinder, whatweb)
- `rules.avoid` — patterns to skip
- `rules.focus` — patterns to prioritize

## Scope Enforcement

Reference `../../partials/scope-vuln.md` throughout both phases. Apply these constraints:

**In scope:** Network-reachable endpoints (HTTP/HTTPS), web routes, API endpoints, WebSocket connections, anything accessible via the target URL. This includes endpoints requiring authentication via the application's standard login mechanisms, and any developer utility or debug console mistakenly exposed through a route.

**Out of scope — do NOT report:** Vulnerabilities requiring internal network access, direct server/database access, CLI tools, build scripts, CI/CD pipelines, migration scripts, development-only endpoints not deployed to production, dependencies with known CVEs but no reachable attack path.

Before reporting any finding, verify it meets the in-scope criteria. Apply `rules.avoid` patterns as exclusions and `rules.focus` patterns as priorities throughout.

## Phase 1: Static Source Code Analysis (Pre-Recon)

Phase 1 analyzes the source code to build the foundational intelligence baseline. You are the ONLY phase with complete source code access — your thoroughness determines whether critical vulnerabilities are found or missed by all subsequent agents.

### External Tool Execution

Before launching code analysis agents, run external reconnaissance tools based on the `tools` configuration in `guardian/config.yaml`. Run enabled tools in parallel via Bash:

- **nmap** (if `tools.nmap` is true or not set): `nmap -sV -sC -T4 <target-host> -oN guardian/scans/<current-scan>/recon/nmap-results.txt`
- **subfinder** (if `tools.subfinder` is true): `subfinder -d <target-domain> -o guardian/scans/<current-scan>/recon/subfinder-results.txt`
- **whatweb** (if `tools.whatweb` is true): `whatweb <target-url> --log-verbose guardian/scans/<current-scan>/recon/whatweb-results.txt`

If a tool is not installed or not enabled, skip it gracefully and note its absence. Do not fail the phase over a missing external tool.

### Phase 1 Discovery (Parallel Agent Dispatch)

Launch these three Agent tool calls simultaneously in a single message. Each agent performs deep source code analysis — delegate ALL code reading to these agents. Do not use Read, Glob, or Grep for source code yourself.

**Agent 1 — Architecture Scanner:**
Map the application's structure, technology stack, and critical components. Identify frameworks, languages, architectural patterns (monolith, microservices, serverless), and security-relevant configurations. Determine the application type (web app, API service, hybrid). Output a comprehensive tech stack summary with security implications, trust boundaries, and deployment architecture.

**Agent 2 — Entry Point Mapper:**
Find ALL network-accessible entry points in the codebase. Catalog API endpoints, web routes, webhooks, file upload handlers, WebSocket endpoints, and externally-callable functions. Also identify and catalog API schema files (OpenAPI/Swagger JSON/YAML, GraphQL schemas, JSON Schema files). Distinguish between public endpoints and those requiring authentication. Exclude local-only dev tools, CLI scripts, and build processes. Provide exact file paths and route definitions.

**Agent 3 — Security Pattern Hunter:**
Identify authentication flows, authorization mechanisms, session management, and security middleware. Find JWT handling, OAuth/OIDC flows, RBAC implementations, permission validators, CSRF protections, rate limiters, and security headers configuration. Map the complete security architecture with exact file locations and line numbers.

Wait for ALL three agents to complete before proceeding to Phase 1 Vulnerability Analysis.

### Phase 1 Vulnerability Analysis (Parallel Agent Dispatch)

After Discovery completes, launch these three agents simultaneously:

**Agent 4 — XSS/Injection Sink Hunter:**
Find all dangerous sinks where untrusted input could execute. Cover six render contexts for XSS:
- **HTML Body:** innerHTML, outerHTML, document.write, document.writeln, insertAdjacentHTML, createContextualFragment, jQuery sinks (add, after, append, before, html, prepend, replaceWith, wrap)
- **HTML Attribute:** Event handlers (onclick, onerror, onload, onfocus), URL-based attributes (href, src, formaction, action), style attribute, srcdoc
- **JavaScript:** eval, Function constructor, setTimeout/setInterval with string args, data in script tags
- **CSS:** element.style properties, data in style tags
- **URL:** location.href, location.replace/assign, window.open, history.pushState/replaceState
- **Additional sinks:** SQL injection points, command injection (exec, system, spawn), file inclusion/path traversal (fopen, include, require, readFile), template injection, deserialization sinks (pickle, unserialize, readObject)

Provide exact file locations with line numbers. Report explicitly if no sinks are found.

**Agent 5 — SSRF/External Request Tracer:**
Identify all locations where user input could influence server-side requests across 12 categories:
- HTTP(S) clients (curl, requests, axios, fetch, net/http, HttpClient, RestTemplate)
- Raw sockets and connect APIs
- URL openers and file includes (file_get_contents, fopen, urlopen)
- Redirect and "next URL" handlers
- Headless browsers and render engines (Puppeteer, Playwright, Selenium, html-to-pdf)
- Media processors (ImageMagick, FFmpeg, wkhtmltopdf)
- Link preview and unfurlers (oEmbed, social card generators)
- Webhook testers and callback verifiers
- SSO/OIDC discovery and JWKS fetchers
- Importers and data loaders (import from URL, RSS/Atom readers)
- Package/plugin/theme installers
- Monitoring and health check frameworks

Map user-controllable request parameters with exact code locations.

**Agent 6 — Data Security Auditor:**
Trace sensitive data flows, encryption implementations, secret management patterns, and database security controls. Identify PII handling, payment data processing, session storage security, and compliance-relevant code. Map data protection mechanisms with exact locations.

Wait for ALL three agents to complete before proceeding to synthesis.

### Phase 1 Synthesis: pre-recon.md

Combine all agent outputs and external tool results. Resolve conflicts and eliminate duplicates. Write the deliverable to `guardian/scans/<current-scan>/recon/pre-recon.md` using chunked writing (Write tool for the first section, Edit tool to append subsequent sections — do NOT write the entire report in one tool call).

The pre-recon.md deliverable must contain these sections:

1. **Penetration Test Scope** — In-scope vs out-of-scope definitions applied to this target
2. **Executive Summary** — 2-3 paragraph overview of the application's security posture, critical attack surfaces, and architectural security decisions
3. **Architecture & Technology Stack** — Framework, language, architectural pattern, trust boundaries, critical security components (from Agent 1)
4. **Authentication & Authorization Deep Dive** — Auth mechanisms, session management, token security, authorization model, SSO/OAuth flows, exhaustive list of auth endpoints (from Agent 3)
5. **Data Security & Storage** — Database security, encryption, data flow protection, multi-tenant isolation (from Agent 6)
6. **Attack Surface Analysis** — All network-accessible entry points, internal service communication, input validation patterns (from Agents 1+2)
7. **Infrastructure & Operational Security** — Secrets management, configuration security, external dependencies, security headers
8. **Codebase Indexing** — Directory structure overview focused on discoverability of security-relevant components
9. **Critical File Paths** — Categorized list: Configuration, Auth, API/Routing, Data Models, Dependencies, Secrets Handling, Middleware, Logging, Infrastructure
10. **XSS Sinks and Render Contexts** — All dangerous sinks by render context with exact file:line locations (from Agent 4)
11. **SSRF Sinks** — All server-side request sinks by category with exact file:line locations (from Agent 5)

If API schema files were discovered by Agent 2, copy them to `guardian/scans/<current-scan>/recon/schemas/`.

## Phase 2: Live Application Discovery (Recon)

Phase 2 correlates static findings with live application behavior to produce the attack surface map that all vulnerability specialists will depend on.

### Authentication (If Configured)

If `authentication` is set in `guardian/config.yaml`, read `../../partials/login-instructions.md` and follow the appropriate login flow before exploration. Verify login success using the configured `success_condition`.

### Target Type Determines Approach

- **`web`**: Use Playwright MCP tools for browser navigation and exploration. Take snapshots, observe network requests, map UI flows.
- **`api`**: Use curl/httpie for endpoint probing. If `target.api_spec` is set, parse it for endpoint discovery and cross-reference with source code routes.
- **`both`**: Use Playwright for UI flows and curl for API endpoints. Correlate browser-observed API calls with direct API testing.

### Four-Step Methodology

**Step 1 — Synthesize Pre-Recon:**
Read the pre-recon.md deliverable from Phase 1. Build a preliminary map of known technologies, subdomains, open ports, key code modules, and identified sinks.

**Step 2 — Explore the Live Application:**
For web/both targets: Navigate to the target URL using Playwright MCP. Map all user-facing functionality: login forms, registration, password reset, dashboards, settings pages, admin panels. Follow multi-step flows. Observe network requests to identify API call patterns.

For API targets: Probe discovered endpoints from pre-recon. If an API spec exists, systematically test each endpoint. Check response headers, error messages, and content types.

**Step 3 — Correlate with Source Code (Parallel Agent Dispatch):**
For each piece of functionality discovered in Steps 1-2, launch parallel Agent tool calls:

- **Route Mapper Agent**: Map all backend routes and controllers handling the discovered endpoints to their exact handler functions with file paths and line numbers.
- **Authorization Checker Agent**: For each discovered endpoint, find authorization middleware, guards, and permission checks. Map the complete authorization flow with exact code locations.
- **Input Validator Agent**: Analyze input validation logic for all discovered form fields and API parameters. Find validation rules, sanitization, and data processing with exact file paths.
- **Session Handler Agent**: Trace complete session and authentication token handling. Map session creation, storage, validation, and destruction with exact code locations.
- **Authorization Architecture Agent**: Comprehensively map the authorization system — all user roles, hierarchies, permission models, authorization decision points (middleware, decorators, guards), object ownership patterns, and role-based access patterns with exact file paths.

**Step 4 — Enumerate and Document:**
Synthesize findings from all agents and live exploration. Cross-reference browser observations with source code findings.

### Phase 2 Deliverable: recon.md

Write to `guardian/scans/<current-scan>/recon/recon.md` using chunked writing. The recon.md deliverable must contain these sections:

1. **How to Read This** — Guide for downstream agents: which sections map to which vulnerability domain, priority order for testing
2. **Executive Summary** — Application purpose, core tech stack, primary attack surface components
3. **Technology & Service Map** — Frontend, backend, infrastructure, subdomains, open ports and services
4. **Authentication & Session Management Flow** — Entry points, mechanism details, code pointers. Include subsections for:
   - Role assignment process (how roles are determined, default role, upgrade path)
   - Privilege storage and validation (where stored, where checked, cache behavior)
   - Role switching and impersonation (if any)
5. **API Endpoint Inventory** — Table of ALL discovered network-accessible endpoints with columns: Method, Endpoint Path, Required Role, Object ID Parameters, Authorization Mechanism, Description & Code Pointer
6. **Input Vectors** — Every location accepting user-controlled input with file:line references: URL parameters, POST body fields, HTTP headers, cookie values
7. **Network & Interaction Map** — Structured mapping with subsections:
   - Entities (components with type, zone, tech, data classification)
   - Entity metadata (technical details per entity)
   - Flows (connections with channel, path, guards, data touched)
   - Guards directory (catalog of authorization controls with categories: Auth, Network, Protocol, Authorization, ObjectOwnership)
8. **Role & Privilege Architecture** — Complete authorization model:
   - Discovered roles (name, privilege level, scope, code implementation)
   - Privilege lattice (hierarchy with dominance and parallel isolation)
   - Role entry points (default landing pages, accessible routes per role)
   - Role-to-code mapping (middleware, permission checks, storage)
9. **Authorization Vulnerability Candidates** — Pre-prioritized for testing:
   - Horizontal privilege escalation candidates (endpoints with object IDs, ranked by data sensitivity)
   - Vertical privilege escalation candidates (endpoints requiring higher privileges, organized by target role)
   - Context-based authorization candidates (multi-step workflow endpoints with bypass potential)
10. **Injection Sources** — Command injection, SQL injection, LFI/RFI, SSTI, path traversal, deserialization sources. Only network-accessible paths with complete data flow from input to dangerous sink. Exact file:line locations.

## Output

Both deliverables are saved to `guardian/scans/<current-scan>/recon/`:

```
guardian/scans/<current-scan>/recon/
  pre-recon.md          # Phase 1: static code analysis + external scans
  recon.md              # Phase 2: live discovery + source correlation
  nmap-results.txt      # (if nmap was run)
  subfinder-results.txt # (if subfinder was run)
  whatweb-results.txt   # (if whatweb was run)
  schemas/              # (if API schemas were discovered)
```

## State Management

Update scan state at phase boundaries using the update-state script:

- Before starting Phase 1: `"$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> recon in_progress`
- After both deliverables are written: the post-agent hook will verify deliverables and mark the phase completed.

## Completion

After both `pre-recon.md` and `recon.md` are successfully written, announce **"GUARDIAN RECON COMPLETE"** and stop. Do not output summaries or recaps — the deliverables contain everything needed for downstream vulnerability analysis agents.
