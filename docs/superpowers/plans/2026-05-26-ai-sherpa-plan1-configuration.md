# AI Sherpa — Plan 1: Repository Structure & Configuration Files

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the complete AI Sherpa repository skeleton with all CLAUDE.md files, settings.json template, and project template — deployable by any developer even before setup scripts exist.

**Architecture:** Three-layer CLAUDE.md design (Global → Domain → Project). Each layer is a standalone file with a hard line limit. A settings.json template enforces secrets protection via deny rules. All content is committed to a central GitHub repo that teams clone.

**Tech Stack:** Markdown (CLAUDE.md files), JSON (settings.json), Git (version control). No build tools required — this plan is pure content/configuration.

**Plans in this series:**
- **Plan 1 (this plan):** Repository structure + all configuration files ← START HERE
- Plan 2: Setup scripts (setup.bat + setup.sh)
- Plan 3: User documentation

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `core/CLAUDE.md` | Create | Global rules for all teams — pre-flight check, universal do's/don'ts, secrets protection |
| `domains/embedded/CLAUDE.md` | Create | Embedded-specific rules — architecture check, hardware-critical flags, MISRA |
| `domains/web/CLAUDE.md` | Create | Web/frontend-specific rules — XSS, CSP, no secrets in localStorage |
| `domains/backend/CLAUDE.md` | Create | Backend rules — Node.js and Python variants, SQL injection, input validation |
| `domains/data/CLAUDE.md` | Create | Data science rules — memory, versioning, data leakage |
| `domains/devops/CLAUDE.md` | Create | DevOps rules — IaC, no hardcoded values, blast radius |
| `templates/project-CLAUDE.md` | Create | Blank project-level CLAUDE.md template teams fill in per project |
| `settings/settings-template.json` | Create | Global secrets deny rules written to ~/.claude/settings.json during setup |
| `.github/CODEOWNERS` | Create | Restrict changes to core/ and domains/ to AI Sherpa team only |
| `README.md` | Create | Repo landing page — purpose, quick start, link to docs |

---

## Task 1: Initialise Repository Structure

**Files:**
- Create: `README.md`
- Create: `.github/CODEOWNERS`
- Create: `core/.gitkeep`, `domains/embedded/.gitkeep`, `domains/web/.gitkeep`, `domains/backend/.gitkeep`, `domains/data/.gitkeep`, `domains/devops/.gitkeep`, `templates/.gitkeep`, `settings/.gitkeep`

- [ ] **Step 1: Create the top-level README.md**

```markdown
# AI Sherpa

Company-wide Claude Code setup for all development teams.

## What This Is
AI Sherpa gives every developer a pre-configured Claude Code environment with:
- Company guardrails and do's/don'ts built in
- Domain-specific rules (Embedded, Web, Backend, Data Science, DevOps)
- Automatic secrets protection
- Codebase knowledge graph via graphify

## Quick Start (Windows)
1. Clone this repo: `git clone <this-repo-url>`
2. Run: `setup.bat`
3. Choose your domain when prompted
4. Start Claude Code: `claude`

## Quick Start (Linux/macOS)
1. Clone this repo: `git clone <this-repo-url>`
2. Run: `./setup.sh`
3. Choose your domain when prompted
4. Start Claude Code: `claude`

## Structure
- `core/` — Global rules for all teams
- `domains/` — Domain-specific rules
- `templates/` — Project CLAUDE.md template
- `settings/` — secrets protection settings template
- `docs/` — User guides and documentation

## Maintained By
AI Sherpa team. Raise issues via GitHub Issues.
```

- [ ] **Step 2: Create directory skeleton**

```bash
mkdir -p core domains/embedded domains/web domains/backend domains/data domains/devops templates settings .github
```

For Windows:
```bat
mkdir core
mkdir domains\embedded domains\web domains\backend domains\data domains\devops
mkdir templates settings .github
```

- [ ] **Step 3: Create .github/CODEOWNERS**

```
# AI Sherpa team owns all core config — changes require their review
/core/          @ai-sherpa-team
/domains/       @ai-sherpa-team
/settings/      @ai-sherpa-team
/templates/     @ai-sherpa-team
```

> Replace `@ai-sherpa-team` with your actual GitHub team handle.

- [ ] **Step 4: Verify structure**

```bash
ls -R
```

Expected output shows all directories created: `core/`, `domains/embedded/`, `domains/web/`, `domains/backend/`, `domains/data/`, `domains/devops/`, `templates/`, `settings/`, `.github/`

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: initialise ai-sherpa repository structure"
```

---

## Task 2: Settings JSON Template (Secrets Protection)

**Files:**
- Create: `settings/settings-template.json`

- [ ] **Step 1: Verify the deny rule format works**

Open any project and check that `~/.claude/settings.json` accepts this format by looking at existing Claude Code documentation or checking the file if already present on your machine.

- [ ] **Step 2: Create settings/settings-template.json**

```json
{
  "permissions": {
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(**/*.p12)",
      "Read(**/*.pfx)",
      "Read(**/secrets/**)",
      "Read(**/credentials/**)",
      "Read(**/.aws/**)",
      "Read(**/.ssh/**)",
      "Read(**/config/database.yml)",
      "Read(**/docker-compose*.yml)",
      "Write(**/.env)",
      "Write(**/.env.*)"
    ]
  }
}
```

- [ ] **Step 3: Verify line count is correct**

Count: the JSON above has 20 deny rules. Confirm no rules are missing by checking against the requirements doc §7.1A.

- [ ] **Step 4: Manually test one deny rule**

On a machine with Claude Code installed, temporarily copy this to `~/.claude/settings.json`, then ask Claude to read a `.env` file. Expected: Claude reports a permission denied error. Revert after testing.

- [ ] **Step 5: Commit**

```bash
git add settings/settings-template.json
git commit -m "feat: add secrets protection settings template"
```

---

## Task 3: Global CLAUDE.md (core/CLAUDE.md)

**Files:**
- Create: `core/CLAUDE.md`

**Hard limit: 150 lines.** Count lines before committing.

- [ ] **Step 1: Create core/CLAUDE.md**

```markdown
# AI Sherpa — Global Rules

These rules apply to ALL projects and ALL domains. Do not remove or override them.

---

## Pre-Flight Check (Run Before EVERY Session)

Before touching any code, complete both steps:

### Step 1 — NDA & Confidentiality
Ask the developer:
> "Before we start — can this project's code be shared with Anthropic's API? Does this project have any NDA, confidentiality agreement, or export control restrictions?"

Also scan the repository for: `NDA.md`, `NDA.txt`, `CONFIDENTIAL.md`, `CONFIDENTIAL.txt`, any file with "confidential", "proprietary", "nda", or "trade-secret" in the filename, or a LICENSE file containing "proprietary" or "all rights reserved".

If found, stop and report:
> "⚠ Found a possible confidentiality file: `[filename]`. Confirm it is safe to send this code to Anthropic's API before continuing."

Never assume permission. Explicit developer confirmation required every session.

### Step 2 — Architecture Understanding
Before any task, read and understand the existing architecture. Use graphify to explore the codebase. If the architecture is unclear or undocumented, ask the developer to explain it before writing any code.

---

## Always Do

1. Complete the Pre-Flight Check before starting any session
2. Write tests before or alongside new code
3. Request code review before marking a task complete — use `/requesting-code-review`
4. Plan before implementing — use `/writing-plans` for non-trivial tasks
5. State what you are about to do before doing it
6. Prefer editing existing files over creating new ones
7. Flag uncertainty explicitly — never guess silently
8. Confirm task understanding with the developer if requirements are ambiguous

---

## Never Do

1. Run destructive commands (rm -rf, DROP TABLE, force-push, reset --hard) without explicit developer confirmation
2. Commit secrets, credentials, API keys, or passwords
3. Read, display, or log contents of `.env`, `*.key`, `*.pem`, or credential files
4. If a command prints secrets to stdout — stop and do not include the output in your response
5. Skip tests or mark work complete without running and verifying
6. Generate code for unknown APIs without checking their documentation first
7. Make architectural changes without a written plan reviewed by a human
8. Add features beyond what was explicitly requested (YAGNI)
9. Add error handling for scenarios that cannot happen
10. Add comments explaining WHAT code does — only WHY if non-obvious
11. Push to main/master directly
12. Assume a task is done without running it

---

## Secrets Protection

`.claudeignore` is unreliable for blocking file access. Protection is enforced via `settings.json` deny rules (written by setup script). As an additional layer, never read or reference the content of any file matching: `.env`, `.env.*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, files in `secrets/`, `credentials/`, `.aws/`, `.ssh/`.
```

- [ ] **Step 2: Count lines**

```bash
wc -l core/CLAUDE.md
```

Expected: under 150 lines. If over, trim verbose sentences without losing meaning.

- [ ] **Step 3: Read through for clarity**

Read every rule. Ask: could a developer misinterpret this? Rewrite any ambiguous rule in plain English.

- [ ] **Step 4: Commit**

```bash
git add core/CLAUDE.md
git commit -m "feat: add global CLAUDE.md with pre-flight check and universal rules"
```

---

## Task 4: Embedded Domain CLAUDE.md

**Files:**
- Create: `domains/embedded/CLAUDE.md`

**Hard limit: 80 lines.**

- [ ] **Step 1: Create domains/embedded/CLAUDE.md**

```markdown
# AI Sherpa — Embedded Software Rules

These rules apply to all embedded software projects (C/C++, firmware, RTOS).
They extend the global rules in core/CLAUDE.md — do not remove global rules.

---

## Architecture Check (Before Every Embedded Task)

Before writing any code, ask the developer if not already documented:
1. Which toolchain is in use? (GCC ARM / IAR / Keil / MPLAB / other)
2. Which RTOS or bare-metal framework? (FreeRTOS / Zephyr / bare-metal / other)
3. Target hardware constraints — RAM, flash size, CPU clock speed
4. Any MISRA-C compliance requirement?

Do not assume or guess hardware context. Proceed only once confirmed.

---

## Hardware-Critical Code — Human Approval Required

Flag ANY suggestion that touches the following with: `⚠ HUMAN REVIEW REQUIRED — hardware-critical change`

Do not proceed until the developer explicitly approves:
- Interrupt service routines (ISRs)
- Memory-mapped hardware register access
- Real-time scheduling or timing logic
- Boot/startup code
- Safety-critical control loops
- DMA configuration
- Power management sequences

---

## Always Do (Embedded)

1. Annotate ISRs with their timing constraints and expected execution time
2. Prefer iterative over recursive — always consider stack depth impact
3. Reference the project's datasheet or HAL before suggesting register access
4. State explicitly: "This suggestion requires hardware-in-the-loop testing to verify"

---

## Never Do (Embedded)

1. Use dynamic memory allocation (malloc/free) unless developer explicitly approves
2. Suggest hardware register access without a datasheet/HAL reference
3. Claim code correctness without hardware-in-the-loop testing
4. Apply MISRA-C suggestions to non-safety-critical modules without asking first

---

## AI Effectiveness Boundaries

Effective: logic bugs, unit tests, code style, test coverage gaps, static analysis
Not suitable as final authority: timing analysis, hardware-specific optimisation, real-time behaviour, physical signal integrity
```

- [ ] **Step 2: Count lines**

```bash
wc -l domains/embedded/CLAUDE.md
```

Expected: under 80 lines.

- [ ] **Step 3: Commit**

```bash
git add domains/embedded/CLAUDE.md
git commit -m "feat: add embedded domain CLAUDE.md with hardware-critical rules"
```

---

## Task 5: Web/Frontend Domain CLAUDE.md

**Files:**
- Create: `domains/web/CLAUDE.md`

**Hard limit: 80 lines.**

- [ ] **Step 1: Create domains/web/CLAUDE.md**

```markdown
# AI Sherpa — Web / Frontend Rules

These rules apply to all web and frontend projects (React, Vue, Angular, HTML/CSS/JS).
They extend the global rules in core/CLAUDE.md.

---

## Always Do (Web)

1. Sanitize all user-generated content before rendering to the DOM
2. Set Content Security Policy (CSP) headers on all responses
3. Use HTTPS everywhere — flag any mixed content immediately
4. Use httpOnly cookies for session tokens and sensitive data
5. Prefer server-side rendering for pages that handle sensitive data

---

## Never Do (Web)

1. Store sensitive data (tokens, PII, API keys) in `localStorage` or `sessionStorage`
2. Use `dangerouslySetInnerHTML` without explicit sanitization — flag and ask developer
3. Expose API keys or secrets in frontend source code or public repos
4. Use inline `<script>` blocks that bypass CSP
5. Pass secrets or credentials as React/Vue props or component state

---

## Security Defaults

- Always add `rel="noopener noreferrer"` to external links (`target="_blank"`)
- Always validate file type AND size on file upload inputs
- Never trust client-side validation alone — flag where server-side validation is missing
```

- [ ] **Step 2: Count lines and commit**

```bash
wc -l domains/web/CLAUDE.md
git add domains/web/CLAUDE.md
git commit -m "feat: add web/frontend domain CLAUDE.md"
```

---

## Task 6: Backend Domain CLAUDE.md

**Files:**
- Create: `domains/backend/CLAUDE.md`

**Hard limit: 80 lines.**

- [ ] **Step 1: Create domains/backend/CLAUDE.md**

```markdown
# AI Sherpa — Backend Rules (Node.js / Python)

These rules apply to all backend projects. They extend core/CLAUDE.md.

---

## Always Do (All Backend)

1. Use parameterized queries — never concatenate user input into SQL strings
2. Validate and sanitize ALL external inputs at the system boundary (API request, file upload, webhook)
3. Handle errors explicitly — never silently swallow exceptions or reject promises
4. Pin all dependency versions — no wildcards (`*`, `^latest`, `~latest`)
5. Return generic error messages to API consumers — never expose stack traces or DB errors

---

## Never Do (All Backend)

1. Hardcode credentials, API keys, or connection strings — always use environment variables
2. Log passwords, tokens, PII, or secrets — even at DEBUG level
3. Use `eval()` or `exec()` with any user-supplied input
4. Expose internal error details (stack traces, query errors) in API responses

---

## Node.js Specific

- Always use `const`/`let` — never `var`
- Use `async/await` — avoid raw `.then()` chains
- Handle unhandled Promise rejections: `process.on('unhandledRejection', handler)`
- Use `helmet` for HTTP security headers in Express/Fastify apps
- Specify exact versions in `package.json` for all production dependencies

---

## Python Specific

- Always add type hints to function signatures
- Use `venv` or `poetry` — never install packages globally
- Use `requirements.txt` or `pyproject.toml` with pinned versions
- Catch specific exception types — never use bare `except:`
- Follow PEP 8 — flag and fix any non-PEP 8 code you generate
```

- [ ] **Step 2: Count lines and commit**

```bash
wc -l domains/backend/CLAUDE.md
git add domains/backend/CLAUDE.md
git commit -m "feat: add backend domain CLAUDE.md for Node.js and Python"
```

---

## Task 7: Data Science Domain CLAUDE.md

**Files:**
- Create: `domains/data/CLAUDE.md`

**Hard limit: 80 lines.**

- [ ] **Step 1: Create domains/data/CLAUDE.md**

```markdown
# AI Sherpa — Data Science / ML Rules

These rules apply to all data science and ML projects. They extend core/CLAUDE.md.

---

## Always Do (Data Science)

1. Check dataset size before loading — never load full dataset into memory without confirming it fits
2. Version data and models alongside code (use DVC, MLflow, or equivalent)
3. Use environment variables or config files for file paths — never hardcode
4. Flag any risk of data leakage between train/test splits when reviewing ML pipelines
5. Document data sources and schema in code comments when they are non-obvious

---

## Never Do (Data Science)

1. Load a full dataset without first checking its size (`df.shape`, `wc -l`, file size)
2. Hardcode absolute file paths — use `pathlib.Path` or config variables
3. Commit large data files or model weights to Git — use DVC or cloud storage
4. Use the same data split for both hyperparameter tuning and final evaluation (data leakage)
5. Suppress warnings from ML libraries without understanding their cause

---

## Code Quality

- Always use type hints in Python functions
- Always use `venv` or `poetry` — never install packages globally
- Pin all package versions in `requirements.txt` or `pyproject.toml`
- Prefer reproducible random seeds — set `random.seed()`, `np.random.seed()`, `torch.manual_seed()`
```

- [ ] **Step 2: Count lines and commit**

```bash
wc -l domains/data/CLAUDE.md
git add domains/data/CLAUDE.md
git commit -m "feat: add data science domain CLAUDE.md"
```

---

## Task 8: DevOps Domain CLAUDE.md

**Files:**
- Create: `domains/devops/CLAUDE.md`

**Hard limit: 80 lines.**

- [ ] **Step 1: Create domains/devops/CLAUDE.md**

```markdown
# AI Sherpa — DevOps / Platform Rules

These rules apply to all DevOps and platform engineering projects. They extend core/CLAUDE.md.

---

## Always Do (DevOps)

1. Use Infrastructure-as-Code (Terraform, Ansible, Pulumi) — never make manual cloud console changes
2. Estimate blast radius before applying any infrastructure change — state it explicitly
3. Document a rollback plan before deleting or modifying existing infrastructure
4. Store all secrets in a secrets manager (Vault, AWS Secrets Manager, GitHub Secrets) — never in code or config files
5. Tag all cloud resources with environment, owner, and cost-centre

---

## Never Do (DevOps)

1. Hardcode environment-specific values (IP addresses, region names, account IDs, credentials) in IaC files
2. Apply `terraform apply` or equivalent without first running and reviewing `terraform plan`
3. Delete infrastructure (databases, queues, storage buckets) without an explicit rollback plan approved by a human
4. Store secrets in environment variables in CI/CD pipeline YAML files — use the platform's secret store
5. Give IAM roles or service accounts more permissions than they need (principle of least privilege)

---

## GitHub Actions Specific

- Always pin GitHub Actions to a specific SHA, not a mutable tag (`uses: actions/checkout@abc1234` not `@v3`)
- Never print secrets to workflow logs — use `::add-mask::` for sensitive values
- Store all API keys and tokens as GitHub Secrets — never in workflow YAML
```

- [ ] **Step 2: Count lines and commit**

```bash
wc -l domains/devops/CLAUDE.md
git add domains/devops/CLAUDE.md
git commit -m "feat: add devops domain CLAUDE.md"
```

---

## Task 9: Project CLAUDE.md Template

**Files:**
- Create: `templates/project-CLAUDE.md`

- [ ] **Step 1: Create templates/project-CLAUDE.md**

```markdown
# [Project Name] — Project-Specific Rules

> **Instructions for setup:** Fill in each section below. Delete sections that don't apply.
> Max 100 lines. This file lives in the project root as CLAUDE.md alongside core/ rules.

---

## Project Overview

- **What this project does:** [One sentence]
- **Primary language(s):** [e.g. Python 3.11, TypeScript 5.x]
- **Framework(s):** [e.g. FastAPI, React 18]
- **Domain:** [Embedded / Web / Backend / Data / DevOps]

---

## Repository Layout

[Briefly describe the key folders and what each contains — 3 to 8 lines]

```
src/        ← [description]
tests/      ← [description]
docs/       ← [description]
```

---

## Local Development Setup

[Commands to get the project running locally — exact commands, not descriptions]

```bash
# Install dependencies
[command]

# Run tests
[command]

# Start dev server / build
[command]
```

---

## Project-Specific Do's

1. [Rule specific to this project — e.g. "Always use the internal logger, not print()"]
2. [Add more as needed]

---

## Project-Specific Don'ts

1. [e.g. "Never modify the legacy/ folder — it is frozen pending migration"]
2. [Add more as needed]

---

## Known Issues / Gotchas

- [e.g. "The test suite requires a running local Redis instance on port 6379"]
- [e.g. "Module X has a known race condition in tests — run with -p no:randomly"]

---

## Contacts

- **Tech lead:** [Name / GitHub handle]
- **On-call / escalation:** [Slack channel or name]
```

- [ ] **Step 2: Commit**

```bash
git add templates/project-CLAUDE.md
git commit -m "feat: add project CLAUDE.md template"
```

---

## Task 10: Verification Pass

Run these checks on the complete repo before calling Plan 1 done.

- [ ] **Step 1: Check all CLAUDE.md line counts**

```bash
# Linux/macOS
wc -l core/CLAUDE.md domains/*/CLAUDE.md

# Windows PowerShell
Get-ChildItem -Path core, domains -Filter CLAUDE.md -Recurse | ForEach-Object { "$($_.FullName): $($(Get-Content $_.FullName).Count) lines" }
```

Expected limits:
- `core/CLAUDE.md` → under 150 lines
- Each `domains/*/CLAUDE.md` → under 80 lines

If any file exceeds its limit, trim it before proceeding.

- [ ] **Step 2: Verify settings-template.json is valid JSON**

```bash
# Linux/macOS
cat settings/settings-template.json | python3 -m json.tool

# Windows PowerShell
Get-Content settings\settings-template.json | ConvertFrom-Json
```

Expected: no errors, JSON parses cleanly.

- [ ] **Step 3: Check that all deny patterns cover the required files**

Open `settings/settings-template.json` and verify these patterns are present:
- `.env` and `.env.*` (Read AND Write)
- `*.pem`, `*.key`, `*.p12`, `*.pfx`
- `secrets/**`, `credentials/**`
- `.aws/**`, `.ssh/**`

- [ ] **Step 4: Spot-check pre-flight check wording in core/CLAUDE.md**

Read the Pre-Flight Check section. Verify:
- It asks about NDA/confidentiality explicitly
- It lists the exact filenames to scan for
- It includes the exact warning message template with `⚠`
- It says "never assume permission"

- [ ] **Step 5: Final commit and tag**

```bash
git add .
git commit -m "chore: verification pass — all line counts and JSON validated"
git tag v0.1.0
git push origin main --tags
```

---

## Self-Review: Spec Coverage Check

| Requirement (from §) | Covered by Task |
|---|---|
| Three-layer CLAUDE.md design (§4.2) | Tasks 3–9 create all three layers |
| Global pre-flight NDA check (§7.0) | Task 3 |
| Secrets protection via settings.json (§7.1A) | Task 2 |
| Global do's and don'ts (§7.1, §7.2) | Task 3 |
| Embedded architecture check + hardware flag (§7.3) | Task 4 |
| Data science rules (§7.4) | Task 7 |
| Backend Node.js + Python rules (§7.5) | Task 6 |
| Web/frontend rules (§7.5A) | Task 5 |
| DevOps rules (§7.6) | Task 8 |
| Project CLAUDE.md template (gap identified in review) | Task 9 |
| CODEOWNERS protecting core config (§4.1) | Task 1 |
| README with quick start (§4.1) | Task 1 |

**Not covered in Plan 1 (handled in later plans):**
- setup.bat / setup.sh → Plan 2
- User documentation (user-guide.md, troubleshooting.md) → Plan 3
- GitHub Actions workflow for graphify re-indexing → Plan 2
