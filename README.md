# Guardian

Guardian is an AI-powered penetration testing plugin for Claude Code. It automates vulnerability assessment by combining source code analysis, live browser testing, and AI-powered exploitation across 5 security domains: injection, XSS, authentication, authorization, and SSRF.

## Installation

Guardian uses Claude Code's plugin marketplace system. Choose **global** (available in all projects) or **project-scoped** (only in the current directory).

### Global install

```bash
# Register Guardian as a local marketplace
claude plugin marketplace add /path/to/guardian

# Install for all projects
claude plugin install guardian
```

### Project-scoped install

```bash
cd /your/pentest/project

# Register and install for this project only
claude plugin marketplace add /path/to/guardian --scope project
claude plugin install guardian --scope project
```

Project-scoped installation creates a `.claude/settings.json` in the current directory. Guardian skills and hooks activate only when Claude Code is opened from that directory.

### Verify installation

```bash
claude plugin list
# guardian@guardian  Version: 0.1.0  Scope: project  Status: ✔ enabled
```

### From GitHub (when published)

```bash
claude plugin install guardian@CaptainClaude
```

---

## Requirements

**Required** (Guardian will not start without these):

| Tool | Install |
|------|---------|
| `git` | pre-installed on macOS/Linux |
| `curl` | pre-installed on macOS/Linux |
| `jq` | `brew install jq` / `apt-get install jq` |

**Recommended** (installed automatically by `/guardian-setup`):

| Tool | macOS | Debian/Ubuntu | Purpose |
|------|-------|---------------|---------|
| `nmap` | `brew install nmap` | `apt-get install nmap` | Port scanning |
| `subfinder` | `brew install subfinder` | `go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest` | Subdomain enumeration |
| `whatweb` | `gem install whatweb` | `apt-get install whatweb` | Technology fingerprinting |

**YAML parsing** (required by `validate-config.sh`):

Guardian's config validator needs one of the following to parse YAML:

```bash
brew install yq          # macOS (recommended)
pip3 install pyyaml      # any platform
```

**Claude Code permissions**: Run with auto-accept enabled or configure `allowedTools` in `~/.claude/settings.json` to include `Bash`, `Read`, `Write`, `Edit`, `Glob`, `Grep`, and the Playwright MCP tools.

---

## SSL / TLS

All HTTP tools skip certificate verification so self-signed and expired certificates never block a scan:

- **curl** — `-k` flag on every invocation
- **whatweb** — `--no-check-certificate`
- **Playwright** — requires `--ignore-https-errors` in the MCP server config:

  ```json
  // ~/.claude/settings.json  →  mcpServers.playwright
  "playwright": { "args": ["--ignore-https-errors"] }
  ```

---

## Quick Start

```bash
# 1. Open Claude Code in your pentest project directory
cd /your/pentest/project
claude

# 2. Configure the target (interactive)
/guardian-setup

# 3. Run the full automated pipeline
/guardian
```

`/guardian-setup` walks through: dependency check, target URL, app type, source code path, authentication, scope rules. It creates `guardian/config.yaml`, `guardian/.env` (credentials, chmod 0600), and an initial state file.

`/guardian` orchestrates all 13 phases and resumes from the last completed phase if interrupted.

---

## Available Skills

| Skill | Phase | Description |
|-------|-------|-------------|
| `/guardian-setup` | 0 | Dependency check + interactive target configuration |
| `/guardian` | — | Full pipeline orchestrator with resume support |
| `/guardian-recon` | 1–2 | Static source analysis + live attack surface mapping |
| `/guardian-vuln-injection` | 3 | SQL / command / LDAP injection analysis |
| `/guardian-vuln-xss` | 4 | Reflected, stored, and DOM XSS analysis |
| `/guardian-vuln-auth` | 5 | Authentication weakness analysis |
| `/guardian-vuln-authz` | 6 | Authorization and access control analysis |
| `/guardian-vuln-ssrf` | 7 | Server-side request forgery analysis |
| `/guardian-exploit-injection` | 8 | Injection exploitation + PoC |
| `/guardian-exploit-xss` | 9 | XSS exploitation + PoC |
| `/guardian-exploit-auth` | 10 | Authentication exploitation + PoC |
| `/guardian-exploit-authz` | 11 | Authorization exploitation + PoC |
| `/guardian-exploit-ssrf` | 12 | SSRF exploitation + PoC |
| `/guardian-report` | 13 | Executive security assessment report |

---

## Pipeline Overview

```
/guardian-setup  →  config.yaml + .env + .state.json
      ↓
/guardian-recon  →  recon/pre-recon.md + recon/recon.md
      ↓
  [5 parallel vuln agents]
  injection │ xss │ auth │ authz │ ssrf
      ↓
  vuln/<domain>-analysis.md + vuln/<domain>-queue.json
      ↓
  [5 parallel exploit agents — skipped if queue is empty]
  injection │ xss │ auth │ authz │ ssrf
      ↓
  exploit/<domain>-evidence.md
      ↓
/guardian-report  →  report/security-assessment.md
```

Each phase writes deliverables to `guardian/scans/<date>_<host>/`. The Stop hook validates deliverables and updates `.state.json` after every session. `/guardian` resumes from the last completed phase automatically.

---

## Output Structure

```
guardian/
├── config.yaml                          # Target configuration
├── .env                                 # Credentials (gitignored, chmod 0600)
├── .gitignore
└── scans/
    └── YYYY-MM-DD_<hostname>/
        ├── .state.json                  # Phase state tracker
        ├── recon/
        │   ├── pre-recon.md             # Static source analysis
        │   ├── recon.md                 # Live app discovery
        │   ├── nmap-results.txt
        │   ├── subfinder-results.txt
        │   └── whatweb-results.txt
        ├── vuln/
        │   ├── injection-analysis.md + injection-queue.json
        │   ├── xss-analysis.md + xss-queue.json
        │   ├── auth-analysis.md + auth-queue.json
        │   ├── authz-analysis.md + authz-queue.json
        │   └── ssrf-analysis.md + ssrf-queue.json
        ├── exploit/
        │   ├── injection-evidence.md
        │   ├── xss-evidence.md
        │   ├── auth-evidence.md
        │   ├── authz-evidence.md
        │   └── ssrf-evidence.md
        └── report/
            └── security-assessment.md  # Final executive report
```

---

## Plugin Structure

```
guardian/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace manifest (local install)
├── hooks/
│   ├── hooks.json           # Hook configuration (SessionStart + Stop)
│   ├── session-start.sh     # Exports $GUARDIAN_ROOT on session start
│   └── post-agent.sh        # Validates deliverables + updates state on Stop
├── partials/                # Shared documentation fragments
│   ├── target.md
│   ├── rules.md
│   ├── scope-vuln.md
│   ├── scope-exploit.md
│   └── login-instructions.md
├── schemas/
│   ├── config-schema.json   # config.yaml schema
│   └── queue-schema.json    # vuln queue schema
├── scripts/
│   ├── check-dependencies.sh
│   ├── validate-config.sh
│   ├── update-state.sh
│   └── check-queue.sh
└── skills/                  # 14 skill directories
    ├── guardian/
    ├── guardian-setup/
    ├── guardian-recon/
    ├── guardian-vuln-{injection,xss,auth,authz,ssrf}/
    ├── guardian-exploit-{injection,xss,auth,authz,ssrf}/
    └── guardian-report/
```

---

## Security Notice

For authorized security testing only. Use exclusively on systems you own or have explicit written permission to test. Unauthorized use may violate computer fraud laws.
