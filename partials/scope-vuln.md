## External Attacker Scope

**CONSTRAINT:** Only report vulnerabilities exploitable from the target URL as an external attacker over the internet.

**In scope:**
- Network-reachable endpoints (HTTP/HTTPS)
- Web routes, API endpoints, WebSocket connections
- Anything accessible via the target URL

**Out of scope — do NOT report:**
- Vulnerabilities requiring internal network access (VPN, Tailscale, private subnets)
- Vulnerabilities requiring direct server/database access
- CLI tools, build scripts, CI/CD pipelines, migration scripts
- Development-only endpoints not deployed to production
- Dependencies with known CVEs but no reachable attack path
