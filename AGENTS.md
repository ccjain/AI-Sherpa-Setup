# AI Sherpa — Agent Guide

> This file is for AI coding agents. Read it before making any changes.

---

## Project Overview

AI Sherpa is a company-wide Claude Code configuration and distribution system. It is **not a traditional software application** — it is a collection of setup scripts, rule files, and documentation that gives every developer a pre-configured Claude Code environment with guardrails, domain-specific rules, secrets protection, and a codebase knowledge graph.

When a developer runs the setup script from their project directory, the script:
1. Installs missing prerequisites (Node.js 20+, Git, Claude Code CLI)
2. Registers Claude Code plugin marketplaces and installs core + domain-specific plugins
3. Writes secrets-protection deny rules to `~/.claude/settings.json` (global) and `.claude/settings.json` (project-level)
4. Copies the selected domain's `CLAUDE.md` rules into the project root
5. Optionally installs the Graphify Python package for codebase indexing

---

## Technology Stack

| Layer | Technology |
|---|---|
| Setup scripts | Bash (`setup.sh`), PowerShell (`setup.ps1`), Batch (`setup.bat`) |
| Runtime deps | Node.js 20+ (for Claude Code CLI and npm plugins), Git, Python 3 with pip (optional, for Graphify) |
| Configuration | JSON (`plugins.json`, `settings-template.json`) |
| Documentation | Markdown (all docs and `CLAUDE.md` rule files) |
| Testing | Bash (`scripts/test-setup.sh`) |

There is **no** `package.json`, `pyproject.toml`, `Cargo.toml`, `Makefile`, or similar build-system file. The project is pure configuration and shell scripting.

---

## Repository Layout

```
.
├── setup.sh                 ← Linux/macOS entry point (idempotent setup)
├── setup.ps1                ← Windows PowerShell entry point
├── setup.bat                ← Windows launcher (delegates to setup.ps1)
├── plugins.json             ← Plugin marketplace definitions and per-domain plugin lists
├── core/
│   ├── CLAUDE.md            ← Global rules for ALL domains (~171 lines)
│   └── CLAUDE_old.md        ← Previous iteration of global rules (reference only)
├── domains/
│   ├── backend/CLAUDE.md    ← Backend (Node.js / Python) rules
│   ├── data/CLAUDE.md       ← Data Science / ML rules
│   ├── devops/CLAUDE.md     ← DevOps / Platform rules
│   ├── embedded/CLAUDE.md   ← Embedded (C/C++, firmware, RTOS) rules
│   ├── finance/CLAUDE.md    ← Finance / Accounting rules
│   ├── marketing/CLAUDE.md  ← Marketing rules
│   ├── procurement/CLAUDE.md← Procurement / Supply-chain rules
│   ├── sales/CLAUDE.md      ← Sales rules
│   ├── service/CLAUDE.md    ← Customer Service / Support rules
│   ├── uiux/CLAUDE.md       ← UI/UX Design rules
│   └── web/CLAUDE.md        ← Web / Frontend rules
├── templates/
│   └── project-CLAUDE.md    ← Template for project-specific CLAUDE.md (Layer 3)
├── settings/
│   └── settings-template.json← Secrets-protection deny rules injected by setup
├── docs/
│   ├── dos-and-donts.md     ← Printable reference card
│   ├── feedback-guide.md    ← How to report AI errors
│   ├── troubleshooting.md   ← Common issues and fixes
│   ├── user-guide.md        ← 1-page quick start
│   ├── windows-setup.md     ← Windows-specific install instructions
│   ├── management/          ← Management discussion documents
│   └── requirements/        ← Requirements documents
├── scripts/
│   └── test-setup.sh        ← Unit tests for setup.sh helper functions
└── .github/CODEOWNERS       ← All changes require @ai-sherpa-team review
```

---

## Build and Test Commands

There is no compilation step. To validate changes, run the test suite:

```bash
bash scripts/test-setup.sh
```

The test script:
- Sources `setup.sh` (the `main()` function is guarded so it does not run on source)
- Tests helper functions (`check_command`, `write_settings`, `write_project_settings`, `copy_claude_md`, `install_core_skills`, `install_domain_skills`, `run_update`)
- Uses temporary directories and mocked `claude` commands
- Prints a pass/fail summary at the end

**Before modifying `setup.sh` or `setup.ps1`, run the tests and ensure they pass.**

---

## Code Style Guidelines

### Scripts
- Keep `setup.sh` and `setup.ps1` under **300 lines** each. Split into called sub-functions if needed.
- Keep domain-specific install logic under **100 lines**.
- Both Windows and Linux/macOS scripts must be maintained **in parallel**. A change to one likely requires a matching change to the other.
- `setup.sh` uses `set -euo pipefail`, color-coded logging (`log_info`, `log_warn`, `log_error`), and helper functions for each phase.
- `setup.ps1` uses `$ErrorActionPreference = "Stop"` and equivalent colored logging.

### CLAUDE.md Rules (Three-Layer Design)
| Layer | Location | Max Lines | Purpose |
|---|---|---|---|
| 1 — Global | `core/CLAUDE.md` | ~150 | Company-wide guardrails, NDA check, universal do's/don'ts |
| 2 — Domain | `domains/<domain>/CLAUDE.md` | ~80 | Domain-specific rules (embedded, web, backend, data, devops, etc.) |
| 3 — Project | `<project>/CLAUDE.md` (template) | ~100 | Project-specific context, stack, known issues |

**Critical:** Combined total must stay under **~300 lines** to avoid Claude deprioritizing later content. Keep each layer tight and high-signal — verbose rules get ignored.

### Documentation
- All docs are in **English**.
- Use Markdown with `---` section dividers.
- Prefer numbered lists for do's/don'ts (easy to scan, easy to reference in feedback).

---

## Testing Instructions

1. Run the bash test suite:
   ```bash
   bash scripts/test-setup.sh
   ```
2. If you change `setup.ps1`, manually test on Windows (there is no automated PowerShell test yet).
3. If you change `plugins.json`, validate it is well-formed JSON:
   ```bash
   node -e "JSON.parse(require('fs').readFileSync('plugins.json'))"
   ```
4. If you add or modify a domain's `CLAUDE.md`, check the line count stays under the limit:
   ```bash
   wc -l domains/<domain>/CLAUDE.md
   ```

---

## Security Considerations

- **Secrets protection is enforced via `settings.json` deny rules, NOT `.claudeignore`.** `.claudeignore` is confirmed unreliable for blocking file access.
- The `settings-template.json` denies `Read` and `Write` operations on `.env`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `secrets/`, `credentials/`, `.aws/`, `.ssh/`, and `config/database.yml`.
- Setup scripts write these rules both globally (`~/.claude/settings.json`) and project-level (`.claude/settings.json`).
- The Pre-Flight Check in `core/CLAUDE.md` requires explicit developer confirmation before sending code to Anthropic's API, and scans for `NDA.md`, `CONFIDENTIAL.md`, and similar files.
- All plugins in `plugins.json` must pass security vetting (verified publisher, 50k+ installs, open source, no undeclared network calls, no secret access). Rejected plugins are documented in `docs/requirements/`.
- High-security projects are excluded by design — no Claude Code seat is provisioned for those teams.

---

## How Setup Works

### Normal Run (first-time setup)
```bash
# Windows (run from the target project directory, NOT from inside ai-sherpa)
C:\tools\ai-sherpa\setup.bat

# Linux/macOS
bash ~/tools/ai-sherpa/setup.sh
```

Flow:
1. Check/install Node.js, Git, Claude Code CLI
2. Prompt for domain (1–11 options: embedded, web, backend, data, devops, marketing, sales, finance, service, procurement, uiux)
3. Prompt for new vs. existing project
4. Register marketplaces from `plugins.json`
5. Install global plugins, then domain-specific plugins
6. Write `settings.json` (global + project)
7. Copy domain `CLAUDE.md` into project root (appends if existing project)
8. Install Graphify (if Python pip is available)
9. Print summary

### Update Run
```bash
setup.bat --update      # Windows
./setup.sh --update     # Linux/macOS
```

Updates core skills and settings only. **Does NOT overwrite project-specific CLAUDE.md customisations.**

### Guardrails
- Setup refuses to run if executed from inside the AI Sherpa repo itself (detects `core/CLAUDE.md` in `$PWD`).
- Existing `settings.json` and `CLAUDE.md` files are backed up (`.bak`) before overwriting.

---

## Key Files to Know

| File | Purpose | Change Frequency |
|---|---|---|
| `plugins.json` | Plugin marketplace and per-domain install lists | When adding/removing plugins |
| `settings/settings-template.json` | Secrets-protection deny rules | When adding new secret patterns |
| `core/CLAUDE.md` | Global AI behaviour rules | When changing universal guardrails |
| `domains/<domain>/CLAUDE.md` | Domain-specific rules | When refining domain guidance |
| `setup.sh` / `setup.ps1` | Setup logic | When changing install flow or prerequisites |
| `scripts/test-setup.sh` | Unit tests for bash helpers | When adding new setup features |
| `docs/` | User-facing documentation | When process or troubleshooting info changes |

---

## Deployment Process

- The repository is hosted on GitHub (central company repo).
- Teams clone it once and run setup from their project directories.
- Updates are distributed via Git — teams pull latest and run with `--update`.
- Version-tagged releases allow teams to pin to a stable version.
- `CODEOWNERS` routes all changes to `@ai-sherpa-team` for review.
