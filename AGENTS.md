# AI Sherpa — Agent Guide

> This file is for AI coding agents. Read it before making any changes.

---

## Project Overview

AI Sherpa is a company-wide Claude Code configuration and distribution system. It is **not a traditional software application** — it is a collection of setup scripts, rule files, and documentation that gives every developer a pre-configured Claude Code environment with guardrails, domain-specific rules, secrets protection, and a codebase knowledge graph.

When a developer runs the setup script, the script:
1. Installs missing prerequisites (Node.js 20+, Git, Claude Code CLI)
2. Registers Claude Code plugin marketplaces and installs core + domain-specific plugins
3. Writes secrets-protection deny rules to `~/.claude/settings.json` (active for every Claude session)
4. Writes the merged core + domain `CLAUDE.md` rules to `~/.claude/CLAUDE.md` (active for every Claude session)
5. Installs the code-review-graph Python package (auto-mode via SessionStart hook)

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
| 1 — Global | `core/CLAUDE.md` | ~230 | Company-wide guardrails, NDA check, universal do's/don'ts, **Global Plugin & Skill Invocation Contract** |
| 2 — Domain | `domains/<domain>/CLAUDE.md` | ~275 | Domain-specific rules (embedded, web, backend, data, devops, etc.), **Domain Plugin & Skill Invocation Contract** |
| 3 — Project | `<project>/CLAUDE.md` (template) | ~100 | Project-specific context, stack, known issues |

**Critical:** Combined total of Layers 1 + 2 (the merged `~/.claude/CLAUDE.md`) must stay under **~500 lines** to avoid Claude deprioritizing later content. Layer 3 lives in the project repo and is not counted against this budget — Claude Code stacks it on top per-project. Keep each layer tight and high-signal — verbose rules get ignored. (Previous target was ~300 lines combined; raised after empirical testing showed Claude reliably honors longer files. See `docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md`.)

**Layer 1 + Layer 2 merge at setup time.** `setup.ps1` and `setup.sh` concatenate `core/CLAUDE.md` + `domains/<chosen>/CLAUDE.md` (with a `---` separator) and write the result to `~/.claude/CLAUDE.md`. The user's installed file is the merge, not a single layer.

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
- Setup scripts write these rules globally to `~/.claude/settings.json`. The rules apply to every Claude session regardless of project.
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

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.
