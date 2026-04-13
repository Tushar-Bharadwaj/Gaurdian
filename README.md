# Guardian Skills

Guardian is an AI-powered penetration testing plugin for Claude Code. It automates vulnerability assessment by combining source code analysis, reconnaissance tools, and AI-powered exploitation across 5 security domains (injection, XSS, authentication, authorization, SSRF).

## Installation

### From local directory

```bash
claude plugin add /path/to/guardian
```

### From GitHub (when published)

```bash
claude plugin add @CaptainClaude/guardian
```

## Quick Start

1. Run `/guardian-setup` to install dependencies and configure your target.
2. Run `/guardian` to execute the full automated pipeline.

## Available Skills

| Skill | Description |
|-------|-------------|
| `/guardian` | Full automated pipeline (orchestrator) |
| `/guardian-setup` | Dependency install + interactive config |
| `/guardian-recon` | Pre-recon + reconnaissance (phases 1-2) |
| `/guardian-vuln-injection` | Injection vulnerability analysis |
| `/guardian-vuln-xss` | XSS vulnerability analysis |
| `/guardian-vuln-auth` | Authentication vulnerability analysis |
| `/guardian-vuln-authz` | Authorization vulnerability analysis |
| `/guardian-vuln-ssrf` | SSRF vulnerability analysis |
| `/guardian-exploit-injection` | Injection exploitation |
| `/guardian-exploit-xss` | XSS exploitation |
| `/guardian-exploit-auth` | Authentication exploitation |
| `/guardian-exploit-authz` | Authorization exploitation |
| `/guardian-exploit-ssrf` | SSRF exploitation |
| `/guardian-report` | Executive security report |

## Requirements

- Claude Code with auto-accept permissions enabled
- Recommended tools: `nmap`, `subfinder`, `whatweb`

## Security Notice

For authorized security testing only. Use only on systems you own or have explicit permission to test.

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
