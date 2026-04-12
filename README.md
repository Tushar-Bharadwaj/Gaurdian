# Guardian Skills

Guardian is an AI-powered penetration testing plugin for Claude Code. It automates vulnerability assessment by combining source code analysis, reconnaissance tools, and AI-powered exploitation across 5 security domains (injection, XSS, authentication, authorization, SSRF).

## Installation

```bash
claude plugin add @CaptainClaude/guardian-skills
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
