```
                                                                      /\
   █████╗ ██╗    ███████╗██╗  ██╗███████╗██████╗ ██████╗  █████╗     /  \
  ██╔══██╗██║    ██╔════╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗   / /\ \
  ███████║██║    ███████╗███████║█████╗  ██████╔╝██████╔╝███████║  /_/  \_\
  ██╔══██║██║    ╚════██║██╔══██║██╔══╝  ██╔══██╗██╔═══╝ ██╔══██║
  ██║  ██║██║    ███████║██║  ██║███████╗██║  ██║██║     ██║  ██║
  ╚═╝  ╚═╝╚═╝    ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝
```

> _Guiding your team's Claude Code expedition._

Company-wide Claude Code setup for all development teams. One command installs
plugins, skills, CLI tools, and domain-specific rules — fully declared in
[`plugins.json`](plugins.json) so admins curate once and every machine stays
in sync.

---

## What you get

| Layer | Source of truth | Examples |
|---|---|---|
| **Global plugins** (everyone) | `plugins.json` → `global[]` | `superpowers`, `fullstack-dev-skills`, `claude-mem`, `agent-browser` |
| **Domain plugins** (per team) | `plugins.json` → `domains.<x>[]` | Embedded: `antigravity-bundle-systems-programming`. Web: `figma`, `vercel`, `frontend-design` |
| **Raw skills** (auto-activating) | `plugins.json` → `skills.*[]` | 21 Zephyr skills for embedded; addyosmani + styleseed for web |
| **CLI tools** (PyPI / cargo / git-clone) | `plugins.json` → `tools.*[]` | `code-review-graph` (Tree-sitter intelligence, auto-mode), `rtk` (token compression), `claude-usage` (cost dashboard) |
| **Domain rules** | `domains/<x>/CLAUDE.md` | Embedded toolchain conventions, frontend a11y rules, AI eval discipline, etc. |
| **Secrets protection** | `settings/settings-template.json` | Read/Write deny patterns for `.env`, `*.pem`, AWS creds, etc. |
| **Auto-install toolchains** | setup scripts | Node.js, Git, Claude Code, Python (PyPI tools), Rust (cargo tools) — installed only when needed |

---

## Quick Start

### Native Windows
```powershell
git clone <this-repo-url>
cd ai-sherpa
.\setup.bat
```

### Linux / macOS / WSL
```bash
git clone <this-repo-url>
cd ai-sherpa
bash setup.sh
```

You'll be prompted for a domain (1–11). The script auto-installs every
prerequisite that's missing.

```bash
claude    # start using it; code-review-graph runs in auto mode via SessionStart hook
```

---

## Domains

| # | Domain | For |
|---|---|---|
| 1 | Embedded Software | C/C++, firmware, RTOS, MCUs |
| 2 | Web (full-stack) | Frontend + backend + UI/UX |
| 3 | Data Science / ML | Pipelines, RAG, fine-tuning |
| 4 | DevOps / Platform | Terraform, K8s, CI/CD, SRE |
| 5 | Marketing | Campaigns, content, SEO, analytics |
| 6 | Sales | Outreach, prospecting, CRM |
| 7 | Finance / Accounting | Month-end, financial analysis |
| 8 | Customer Service / Support | Tickets, escalation, KB |
| 9 | Procurement / Operations | Sourcing, vendors, workflows |
| 10 | AI / ML Agents | RAG, evals, prompt engineering, Anthropic SDK |
| 11 | Frontend + UI/UX | Component libraries, design systems, accessibility, Core Web Vitals |

---

## Other commands

```bash
setup.bat --update            # refresh plugins + skills + tools to latest
setup.bat --uninstall         # remove everything setup wrote (requires typed confirmation)
```

`--update` is domain-aware: it reads `~/.claude/.ai-sherpa-state.json` (written
on install) and refreshes only that domain's plugins, skills, and tools.

---

## Structure

| Path | Holds |
|---|---|
| [`plugins.json`](plugins.json) | The single source of truth for what every machine installs |
| [`setup.ps1`](setup.ps1) / [`setup.sh`](setup.sh) | Setup, update, and uninstall logic for both platforms |
| [`core/CLAUDE.md`](core/CLAUDE.md) | Global rules for every domain |
| [`domains/<x>/CLAUDE.md`](domains/) | Per-domain rules (Embedded, Web, AI, etc.) |
| [`skills/`](scripts/) → `generate-skills-inventory.ps1` | Walks plugins.json and emits the full per-domain rollup |
| [`templates/`](templates/) | Project CLAUDE.md template, `code-review-graphignore` defaults |
| [`settings/`](settings/) | Secrets-protection settings template + SessionStart hook |
| [`docs/`](docs/) | User and admin guides |

---

## Docs

- [User Guide](docs/user-guide.md) — running setup, picking a domain, invoking plugins/skills
- [Admin Guide](docs/admin-guide.md) — how to add or remove plugins, skills, and tools in `plugins.json`
- [Skills & Plugins Inventory](docs/skills-inventory.md) — generated per-domain rollup of everything installed
- [Do's & Don'ts](docs/dos-and-donts.md) — quick reference card
- [Troubleshooting](docs/troubleshooting.md) — common issues + fixes

---

## Maintained By

AI Sherpa team. Raise issues via GitHub Issues.
