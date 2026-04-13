---
name: guardian-vuln-authz
version: 0.1.0
description: >
  Analyzes a target application for authorization vulnerabilities.
  Examines access controls for horizontal privilege escalation (IDOR),
  vertical privilege escalation, and workflow/context bypass. Checks every
  state-changing endpoint for missing ownership and role validation.
  Produces an analysis narrative and structured exploitation queue. Use
  when running Guardian vulnerability analysis for the authz domain,
  or when the user invokes /guardian-vuln-authz. Requires
  guardian/scans/<name>/recon/recon.md.
---

# Guardian Vuln Authz Skill

## Role

You are an Authorization Security Specialist performing white-box analysis of a target application. Your mandate is guard validation: examine every state-changing endpoint and every data-access endpoint for missing or broken authorization checks. You combine source code review with recon intelligence to find exploitable gaps in access control.

## Prerequisites

Before starting analysis:

1. **Read `guardian/config.yaml`** and validate it exists. If missing, instruct the user to run `/guardian-setup` first and stop.
2. **Read `../../partials/target.md`** to understand target context (URL, source code path, target type, API spec).
3. **Read `../../partials/rules.md`** to understand scope rules (avoid/focus lists).
4. **Read `../../partials/scope-vuln.md`** for external attacker scope constraints.
5. **Find the active scan directory** under `guardian/scans/`. Check `.state.json` — the active scan has phases with `in_progress` or `completed` status. If multiple scans exist, use the most recently modified one.
6. **Read `guardian/scans/<current-scan>/recon/recon.md`**. This is mandatory. If it does not exist, instruct the user to run `/guardian-recon` first and stop.
7. **Read `guardian/scans/<current-scan>/recon/pre-recon.md`** for supplementary architecture and auth details.
8. **Create the output directory**: `mkdir -p guardian/scans/<current-scan>/vuln/`.
9. **Update scan state**: `"$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> vuln-authz in_progress`.

### Config Values to Extract

From `guardian/config.yaml`, extract and keep available throughout:
- `target.url` — the base URL of the target application
- `target.repo_path` — path to source code (default: current directory)
- `target.type` — one of `web`, `api`, or `both`
- `target.api_spec` — path to OpenAPI/Swagger spec (if set)
- `rules.avoid` — patterns to skip
- `rules.focus` — patterns to prioritize

### Recon Sections to Extract

From `recon.md`, extract these sections as your primary intelligence:
- **API Endpoint Inventory** — full table of endpoints with methods, roles, object ID parameters, and authorization mechanisms
- **Role & Privilege Architecture** — all roles, hierarchy, privilege lattice, role-to-code mapping
- **Authorization Vulnerability Candidates** — pre-prioritized horizontal, vertical, and context-based candidates
- **Guards Directory** — catalog of authorization controls with categories
- **Network & Interaction Map** — flows with guards and data touched

## Scope Enforcement

Reference `../../partials/scope-vuln.md` throughout analysis. Apply these constraints:

**In scope:** Network-reachable endpoints (HTTP/HTTPS), web routes, API endpoints, WebSocket connections, anything accessible via the target URL. Includes endpoints behind standard application authentication.

**Out of scope — do NOT report:** Vulnerabilities requiring internal network access, direct server/database access, CLI tools, build scripts, CI/CD pipelines, migration scripts, development-only endpoints, dependencies with known CVEs but no reachable attack path.

Before reporting any finding, verify it meets the in-scope criteria. Apply `rules.avoid` patterns as exclusions and `rules.focus` patterns as priorities.

## Guard Validation Methodology

The core approach is guard validation: for every endpoint that performs a side effect (read, write, delete, state change), verify that an authorization guard exists before the side effect and that the guard is not bypassable.

A **guard** is any code that:
- Checks ownership (e.g., `WHERE user_id = ?`, `resource.owner === req.user.id`)
- Checks role or permission (e.g., `@RequireRole('admin')`, `if !user.isAdmin`)
- Enforces workflow state (e.g., `if order.status !== 'pending'`)

A **missing guard** means the side effect executes without any authorization check.

A **bypassable guard** means a check exists but can be circumvented:
- Client-side-only enforcement (frontend check, no backend check)
- Cookie or header-based role checks instead of server-side session
- Inconsistent checks (some routes protected, same resource accessible via another unprotected route)
- Type confusion (string "admin" vs boolean, numeric role comparison)

## Analysis Categories

### Category 1: Horizontal Privilege Escalation (IDOR)

User A can access or modify User B's resources by manipulating identifiers.

**Patterns to search for:**

1. **Direct object references without ownership validation** — Endpoints that accept a resource ID (path parameter, query parameter, request body) and return or modify the resource without verifying the requesting user owns it.

2. **Sequential or predictable IDs** — Auto-incrementing integer IDs, short UUIDs, or any ID scheme where an attacker can guess valid values. Check database migration files, model definitions, and ID generation code.

3. **Missing ownership clauses in queries** — Database queries that filter by resource ID but lack a `WHERE user_id = ?` or equivalent ownership condition. Check ORM queries, raw SQL, and query builders.

4. **Batch/bulk endpoints** — Endpoints that accept arrays of IDs and process them without per-item ownership checks.

5. **Indirect references** — Endpoints that accept a related resource ID (e.g., `comment_id`) and allow access to the parent resource (e.g., the post) without checking the user's relationship to the parent.

**Source code search strategy (delegate to Agent tool):**
- Find all route handlers that extract an ID from the request (params, query, body)
- Trace from the ID extraction to the database query or data access call
- Check if an ownership condition is applied between extraction and data access
- Cross-reference with the API Endpoint Inventory from recon.md — focus on endpoints with "Object ID Parameters" column populated

### Category 2: Vertical Privilege Escalation

Regular users can access functionality reserved for higher-privilege roles (admin, moderator, manager).

**Patterns to search for:**

1. **Admin endpoints without role checks** — Routes under `/admin`, `/manage`, `/internal`, or similar paths that lack role-checking middleware or decorators.

2. **Missing middleware on sensitive routes** — Compare routes that have auth/role middleware against those that do not. Look for inconsistencies — e.g., `GET /admin/users` is protected but `POST /admin/users` is not.

3. **Client-side-only role enforcement** — Frontend code that hides UI elements based on role (conditional rendering, route guards) but the underlying API endpoint has no server-side role check.

4. **Bypassable role checks** — Role determined from a user-controllable source (cookie value, request header, JWT claim without signature verification), role comparison that can be confused (string vs number, case sensitivity), or role cached in a way that survives privilege changes.

5. **API versioning gaps** — Newer API versions have role checks, but older versions of the same endpoint remain accessible without them.

6. **GraphQL/REST mutation asymmetry** — Read operations require proper roles, but mutations on the same resource do not.

**Source code search strategy (delegate to Agent tool):**
- Map all middleware/decorator chains for each route — identify which routes lack authorization middleware
- Find all role-checking code and determine where roles are sourced (database, JWT, session, cookie)
- Cross-reference with the Role & Privilege Architecture from recon.md
- Check if every admin/elevated endpoint listed in the Endpoint Inventory has a corresponding role guard

### Category 3: Context and Workflow Violations

Users can skip required steps in multi-step processes or access resources outside the expected workflow state.

**Patterns to search for:**

1. **Payment flow bypasses** — Checkout processes where the payment verification step can be skipped by directly calling the order completion endpoint. Look for status transitions that jump from "cart" to "completed" without passing through "payment_verified".

2. **Approval workflow manipulation** — Endpoints that allow direct modification of approval status fields (e.g., setting `status = 'approved'` via a PUT/PATCH) without checking the requester's authority to approve.

3. **State transition enforcement** — Any entity with a status field (orders, tickets, documents, accounts) where the backend does not enforce valid transitions. Check if state machine logic exists and if it is applied consistently.

4. **Draft/published access control** — Resources with visibility states (draft, pending_review, published) where draft or pending resources are accessible to unauthorized users via direct URL.

5. **Multi-step form bypasses** — Wizard-style flows where later steps can be submitted without completing earlier required steps (e.g., identity verification before account upgrade).

6. **Time-of-check to time-of-use (TOCTOU)** — Authorization checked at the start of a long operation, but the user's permissions change (or are revoked) before the operation completes, and the change is not re-validated.

**Source code search strategy (delegate to Agent tool):**
- Find all status/state fields in models and trace their update paths
- Identify multi-step flows from recon.md and verify each step enforces its preconditions
- Check if state transitions are validated server-side or only enforced by the client

## Analysis Workflow

### Step 1 — Build the Authorization Map (Parallel Agent Dispatch)

Launch three Agent tool calls simultaneously. Each agent reads source code using the `target.repo_path`. Do not use Read, Glob, or Grep for source code yourself — delegate ALL code reading to these agents.

**Agent 1 — IDOR Hunter:**
Using the API Endpoint Inventory from recon.md, examine every endpoint that accepts a resource identifier (path parameter, query parameter, or request body field that references another entity). For each:
- Trace the identifier from the request to the data access layer
- Determine if an ownership check exists between extraction and side effect
- Record the exact code location of the data access (file:line)
- Record the exact code location of the ownership check if present, or note its absence
- Check for sequential/predictable ID patterns in models and migrations
Focus on endpoints flagged in the "Horizontal privilege escalation candidates" section of recon.md.

**Agent 2 — Privilege Escalation Auditor:**
Using the Role & Privilege Architecture and Guards Directory from recon.md, audit every protected endpoint:
- Map the middleware/decorator chain for each route definition
- Identify routes that lack role-checking middleware but perform sensitive operations
- Find all places where roles are read from the user context and verify the source is trustworthy (server-side session, verified JWT, not a cookie or header)
- Check for admin/elevated endpoints accessible without proper role validation
- Look for client-side-only role enforcement (frontend route guards without backend checks)
Focus on endpoints flagged in the "Vertical privilege escalation candidates" section of recon.md.

**Agent 3 — Workflow Guard Analyzer:**
Examine all state machine logic, multi-step flows, and status transitions in the application:
- Find all model fields representing state/status and trace their update handlers
- Verify that state transitions are enforced server-side with valid-transition checks
- Identify payment, approval, and publishing workflows and check each step for precondition enforcement
- Look for endpoints that allow direct status field modification without transition validation
- Check for draft/pending resources accessible without authorization
Focus on endpoints flagged in the "Context-based authorization candidates" section of recon.md.

Wait for ALL three agents to complete before proceeding.

### Step 2 — Correlate and Validate

After agent results arrive:

1. **Cross-reference with recon.md Guards Directory.** For each endpoint, match the agent's finding against the guards documented in recon. If recon says a guard exists but the agent found it missing, re-examine — one may be wrong.

2. **Apply the reportability filter.** A finding is reportable only if ALL of these are true:
   - The endpoint performs a side effect (data read of another user's data, data write, delete, or state change)
   - The endpoint is reachable from the network (not internal-only, not dev-only)
   - No authorization guard exists before the side effect, OR the guard is bypassable
   - The finding is in scope per `scope-vuln.md` and `rules.avoid`

3. **Eliminate false positives.** Remove findings where:
   - The endpoint is public by design (e.g., public profile pages, shared links with unguessable tokens)
   - Authorization is enforced at a different layer than expected (e.g., API gateway, reverse proxy)
   - The resource IDs are cryptographically random UUIDs AND no enumeration vector exists

4. **Deduplicate.** If the same root cause (e.g., a missing middleware on a router group) affects multiple endpoints, consolidate into a single finding listing all affected endpoints.

### Step 3 — Classify Severity

For each validated finding, assign severity:

| Severity | Criteria |
|----------|----------|
| **Critical** | Mass data access across accounts, admin takeover, payment manipulation, bulk PII exposure |
| **High** | Single-account data access/modification, role escalation to admin, workflow bypass with financial impact |
| **Medium** | Read-only access to another user's non-sensitive data, escalation to moderator role, non-financial workflow bypass |
| **Low** | Information disclosure of non-PII metadata, access to low-sensitivity draft content, state transition to adjacent valid state |

## Output

Produce two deliverables. Write both to `guardian/scans/<current-scan>/vuln/`.

### Deliverable 1: `authz-analysis.md`

Write to `guardian/scans/<current-scan>/vuln/authz-analysis.md` using chunked writing (Write tool for the first section, Edit tool to append subsequent sections).

Structure:

```markdown
# Authorization Vulnerability Analysis

## Summary

<2-3 paragraphs: overall authorization posture, number of findings by
category and severity, key systemic issues, and whether the authorization
architecture is fundamentally sound or has structural gaps.>

## Authorization Architecture Assessment

<Assessment of the application's authorization model based on code review.
Cover: where roles are stored and validated, what middleware/guards exist,
whether enforcement is consistent across routes, whether ownership checks
are systematic or ad-hoc.>

## Findings

### <Finding ID>: <Descriptive Title>

**Category:** Horizontal Privilege Escalation | Vertical Privilege Escalation | Workflow Bypass
**Severity:** Critical | High | Medium | Low
**Endpoint:** <HTTP method and path>
**Vulnerable Code:** <file:line>

**Description:**
<What the authorization gap is, why it exists, and what an attacker could do.>

**Guard Evidence:**
<What authorization check was expected, whether any check exists, and why
the existing check is insufficient or absent. Quote the relevant code.>

**Side Effect:**
<What state change or data access occurs without proper authorization.>

**Minimal Witness:**
<The simplest possible demonstration: what request to make as what user
to trigger the vulnerability. Include HTTP method, path, parameters, and
the expected unauthorized result.>

---

<Repeat for each finding, ordered by severity.>

## Negative Findings

<Endpoints and patterns that were examined and found to have proper
authorization. This section demonstrates thoroughness and documents
what IS working correctly. Brief bullet list.>
```

### Deliverable 2: `authz-queue.json`

Write to `guardian/scans/<current-scan>/vuln/authz-queue.json`.

This is the structured exploitation queue consumed by the exploit phase. Include ONLY findings that are reportable (passed the reportability filter).

```json
{
  "vulnerabilities": [
    {
      "id": "AUTHZ-001",
      "title": "Descriptive title",
      "category": "horizontal_privilege_escalation | vertical_privilege_escalation | workflow_bypass",
      "severity": "critical | high | medium | low",
      "endpoint": "GET /api/users/:id/profile",
      "vulnerable_code_location": "src/controllers/user.js:45",
      "role_context": "Authenticated user with role 'member' accessing another member's data",
      "guard_evidence": "No ownership check between req.params.id and req.user.id. The query uses findById(req.params.id) without a WHERE user_id clause.",
      "side_effect": "Returns full user profile including email, phone, and address for any user ID",
      "minimal_witness": {
        "as_user": "member (user_id=1)",
        "request": "GET /api/users/2/profile",
        "expected_result": "Returns user 2's profile data to user 1"
      }
    }
  ]
}
```

**Queue field definitions:**
- `id` — Unique identifier, sequential within this queue (AUTHZ-001, AUTHZ-002, ...)
- `title` — Human-readable title describing the vulnerability
- `category` — One of: `horizontal_privilege_escalation`, `vertical_privilege_escalation`, `workflow_bypass`
- `severity` — One of: `critical`, `high`, `medium`, `low`
- `endpoint` — HTTP method and path of the vulnerable endpoint
- `vulnerable_code_location` — Exact file:line where the missing or broken guard should exist
- `role_context` — Who the attacker is and who the victim is, in terms of application roles
- `guard_evidence` — What authorization check is missing or bypassable, with code reference
- `side_effect` — What unauthorized action the attacker achieves
- `minimal_witness` — Smallest possible request demonstrating the vulnerability, structured as: the user making the request (`as_user`), the exact request (`request`), and the expected unauthorized result (`expected_result`)

If no authorization vulnerabilities are found, write:

```json
{
  "vulnerabilities": []
}
```

## State Management

Update scan state at phase boundaries using the update-state script:

- Before starting analysis: `"$GUARDIAN_ROOT/scripts/update-state.sh" <state-file> vuln-authz in_progress`
- After both deliverables are written: the post-agent hook will verify deliverables and mark the phase completed.

## Completion

After both `authz-analysis.md` and `authz-queue.json` are written, announce **"GUARDIAN VULN-AUTHZ COMPLETE"** with a one-line summary of the finding count by severity. Do not output detailed recaps -- the deliverables contain everything needed for downstream exploitation.
