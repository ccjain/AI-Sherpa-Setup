# AI Sherpa

Company-wide Claude Code setup for all development teams.

## What This Is
AI Sherpa gives every developer a pre-configured Claude Code environment with:
- Company guardrails and do's/don'ts built in
- Domain-specific rules (Embedded, Web, Backend, Data Science, DevOps)
- Automatic secrets protection
- Codebase knowledge graph via graphify

## Quick Start (Windows)
**Prerequisites:** Git and Node.js (v20+) must be installed. `setup.bat` will install Claude Code CLI automatically.

1. Clone this repo: `git clone <this-repo-url>`
2. Run: `setup.bat`
3. Choose your domain when prompted
4. Start Claude Code: `claude`

## Quick Start (Linux/macOS)
**Prerequisites:** Git and Node.js (v20+) must be installed. `setup.sh` will install Claude Code CLI automatically.

1. Clone this repo: `git clone <this-repo-url>`
2. Run: `./setup.sh`
3. Choose your domain when prompted
4. Start Claude Code: `claude`

## Structure
- `core/` — Global rules for all teams
- `domains/` — Domain-specific rules
- `templates/` — Project CLAUDE.md template
- `settings/` — Secrets protection settings template
- `docs/` — User guides and documentation

## Maintained By
AI Sherpa team. Raise issues via GitHub Issues.
