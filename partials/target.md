## Target Context

**URL:** Read from `guardian/config.yaml` field `target.url`

**Source Code:** Read from `guardian/config.yaml` field `target.repo_path` (default: current directory)

**Filesystem Boundaries:**
- Source code directory — **read only**. Analyze but never modify.
- `guardian/scans/<current-scan>/` — **read-write**. All deliverables go here.

**Target Type:** Read from `guardian/config.yaml` field `target.type` (web | api | both)
- `web`: Has a browser UI. Use Playwright MCP for navigation.
- `api`: REST/GraphQL only. Use curl/httpie for requests.
- `both`: Has both. Use Playwright for UI flows, curl for API endpoints.

**API Specification:** If `target.api_spec` is set in config, read and parse it for endpoint discovery. Cross-reference with source code routes.
