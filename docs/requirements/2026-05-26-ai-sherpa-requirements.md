# AI Sherpa — Requirements Document
**Version:** 0.9 (Pre-Final Draft)
**Date:** 2026-05-26
**Status:** Ready for Review

---

## 1. Executive Summary

AI Sherpa is a standardized, company-wide setup system that enables development teams across all domains to adopt AI coding tools (Claude Code) with zero friction. It provides pre-configured skills, guardrails, do's and don'ts, and a project-specific knowledge base — deployable to any new or existing project via a single setup script.

---

## 2. Objectives

- Enable all development teams to start using AI coding tools without requiring deep AI expertise
- Enforce consistent guardrails and best practices across all projects
- Provide domain-specific configurations (embedded, web, data science, DevOps)
- Build a project-level knowledge base automatically so AI understands the codebase context
- Integrate with existing git workflows (MR/PR) for AI-assisted review and reporting
- Stay current: updates to the central AI Sherpa repo propagate to all teams

---

## 3. Scope

### 3.1 Supported Development Domains
| Domain | Notes |
|---|---|
| Embedded Software | C/C++, firmware, RTOS. AI effective for review, debugging, tests. Not recommended for real-time critical hardware logic without human review. |
| Backend / Software | APIs, services, business logic. Full AI assistance applicable. |
| Frontend / Web | UI, web apps. Full AI assistance applicable. |
| Data Science / ML | Python, notebooks, pipelines. AI effective for code review and refactoring. |
| DevOps / Platform | Infrastructure-as-code, CI/CD, cloud. AI effective for review and security audits. |

### 3.2 Out of Scope (v1)
- Automated feedback loop (deferred — manual feedback only in v1)
- iOS/mobile-specific tooling
- Marketing or content-generation workflows
- High-security project teams (excluded by design — see §3.3)

### 3.3 Access Control Policy — High-Security Projects
Teams working on high-security, classified, or export-controlled projects will **not be provisioned Claude Code access** by management. This is enforced at the Claude Teams Plan admin level — no seat assigned means no access possible.

This is the primary control. The Pre-Flight NDA check in §7.0 acts as a secondary safety net for all other teams — catching cases where a developer may inadvertently work on confidential code without realising it.

**Two-layer protection:**
| Layer | Mechanism | Who enforces |
|---|---|---|
| Primary | No Claude seat provisioned for high-security teams | Management / IT admin |
| Secondary | Pre-Flight NDA check — Claude asks permission and scans for NDA files every session | Claude Code (§7.0) |

---

## 4. System Architecture

### 4.1 Repository Structure
```
ai-sherpa/                          ← Central company Git repo (internal)
├── setup.sh                        ← Entry point for Linux/macOS developers
├── setup.bat                       ← Entry point for Windows developers
├── core/                           ← Universal config for ALL teams
│   ├── CLAUDE.md                   ← Global do's/don'ts, guardrails, behavior rules
│   ├── skills/                     ← Universal skills (debugging, TDD, review, planning)
│   └── hooks/                      ← PreToolUse / PostToolUse safety hooks
├── domains/
│   ├── embedded/
│   │   ├── CLAUDE.md               ← Embedded-specific rules (MISRA, no dynamic alloc, etc.)
│   │   └── skills/                 ← Embedded-specific skills
│   ├── web/
│   │   ├── CLAUDE.md
│   │   └── skills/
│   ├── data/
│   │   ├── CLAUDE.md
│   │   └── skills/
│   └── devops/
│       ├── CLAUDE.md
│       └── skills/
├── docs/
│   ├── user-guide.md               ← 1-2 page quick start for developers
│   ├── dos-and-donts.md            ← Printable reference card (domain versions)
│   ├── windows-setup.md            ← Windows-specific install instructions
│   ├── troubleshooting.md          ← Common issues and fixes
│   └── feedback-guide.md           ← How to submit feedback (v2)
└── feedback/
    └── template.md                 ← Feedback submission template (v2)
```

### 4.2 Three-Layer CLAUDE.md Design
| Layer | File | Max Lines | Purpose |
|---|---|---|---|
| 1 — Global | `core/CLAUDE.md` | 150 lines | Company-wide rules, guardrails, NDA check, universal do's/don'ts |
| 2 — Domain | `domains/<domain>/CLAUDE.md` | 80 lines | Domain-specific rules (embedded, web, backend, data, devops) |
| 3 — Project | `<project>/CLAUDE.md` | 100 lines | Project-specific context, stack, known issues, team conventions |

All three layers are active simultaneously. Later layers add to — not override — earlier ones. Combined total must not exceed ~300 lines to avoid Claude deprioritizing later content.

> **Critical:** CLAUDE.md is loaded as context on every AI turn. Keep each layer tight and high-signal — verbose rules get ignored.

---

## 5. Prerequisites & Setup Script Requirements

### 5.1 Prerequisites (Installed Automatically by setup.sh / setup.bat)

**Primary platform: Windows** (majority of developers). Both scripts must be maintained in parallel.

| Tool | Windows (setup.bat) | Linux/macOS (setup.sh) |
|---|---|---|
| Node.js (v20+) | Install via `winget install OpenJS.NodeJS` | Install via `nvm` |
| Git | Install via `winget install Git.Git` | Install via OS package manager |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` | Same |
| PowerShell 5.1+ | Pre-installed on Windows 10/11 | N/A |

**API Access: Claude Teams Plan**
- Company admin purchases seats and assigns to team members
- Each developer authenticates with their company account — no shared API keys
- Billing is per-seat, per team, centrally managed
- Admin can deactivate seats immediately when someone leaves
- **Do NOT use a single shared API key** — no per-user tracking, shared budget exhausted by one team affects all others

> **Claude Teams Plan:** Company manages billing and seat assignment centrally. Each developer logs in with their company account — no personal API keys, no key rotation risk, admin retains control.

### 5.2 setup.sh Behaviour
1. Check and install prerequisites (Node.js, Git, Claude Code CLI)
2. Prompt: `"Which domain? [1] Embedded [2] Web/Frontend [3] Data Science [4] DevOps [5] Backend"`
3. Prompt: `"New project or existing project? [1] New [2] Existing"`
4. Install core skills from approved whitelist (mandatory for all)
5. Install domain-specific skills from approved whitelist
6. Write global secrets protection rules to `~/.claude/settings.json`
7. Write project-level `.claude/settings.json` with deny rules
8. Run `graphify` to index the project codebase into a knowledge graph
9. Copy domain `CLAUDE.md` into project root (merge non-destructively if existing project)
10. Print quick start summary to terminal
11. On error: print clear failure message, roll back partial installs, exit cleanly

### 5.3 Update Command
```bash
# Linux/macOS
./setup.sh --update

# Windows
setup.bat --update
```
- Does NOT overwrite project-specific CLAUDE.md customisations
- Shows diff of what will change before applying
- Teams can pin to a release tag: `setup.bat --version v1.2`

### 5.4 Update Cadence
- **Phase 1 (Pilot + early rollout):** Frequent updates — weekly or as issues are found. Embedded pilot teams will surface the most issues early.
- **Phase 2 (Mature):** Less frequent — monthly or on-demand. Updates reserved for new domain configs, security fixes, or new approved plugins.
- Teams are notified of updates via a Git release tag + internal announcement. Pull is manual (`--update`) unless admin decides to push.

### 5.5 Pilot Plan
- **First pilot:** Embedded software projects (2-3 projects selected by management)
- Duration: 2-4 weeks
- Goal: Validate setup.bat works on Windows, test embedded CLAUDE.md rules, measure friction points
- Feedback from pilot directly informs v1.1 rules and script fixes before broader rollout

### 5.6 Script Size Limits
- `setup.bat` / `setup.sh` max **300 lines** each — split into called sub-scripts if larger
- Each domain install script max **100 lines**

---

## 6. Skills & Plugins

### 6.1 Mandatory — All Domains

| Skill | Source | Install Command | Purpose |
|---|---|---|---|
| superpowers | obra/superpowers | `npx skillsadd obra/superpowers` | Full workflow suite: planning, debugging, review, TDD |
| graphify | safishamsi/graphify | `npx skillsadd safishamsi/graphify` | Codebase knowledge graph — reduces token cost 6x–49x |
| tdd | mattpocock/skills | `npx skillsadd mattpocock/skills` | Test-driven development workflow |
| improve-codebase-architecture | mattpocock/skills | (same package) | Architecture review |
| diagnose | mattpocock/skills | (same package) | Systematic root cause diagnosis |
| triage | mattpocock/skills | (same package) | Issue triage |
| harden | pbakaus/impeccable | `npx skillsadd pbakaus/impeccable` | Code hardening |
| audit | pbakaus/impeccable | (same package) | Code audit |
| sentry-cli | sentry/dev | `npx skillsadd sentry/dev` | Error tracking & monitoring |

**Superpowers sub-skills included:**
- `systematic-debugging`
- `test-driven-development`
- `writing-plans`
- `executing-plans`
- `verification-before-completion`
- `requesting-code-review`
- `receiving-code-review`
- `brainstorming`
- `subagent-driven-development`

### 6.2 Domain-Specific Skills

**Web / Frontend**
| Skill | Source |
|---|---|
| frontend-design | anthropics/skills |
| web-design-guidelines | vercel-labs/agent-skills |
| webapp-testing | anthropics/skills |
| next-best-practices | vercel-labs/next-skills |
| agent-browser | vercel-labs/agent-browser |
| shadcn | shadcn/ui |

**Data Science / ML**
> No suitable third-party skills found for enterprise data science use. `lllllllama/ai-paper-reproduction-skill` was evaluated and rejected — it is built for academic paper reproduction (arXiv, DOI lookups), not enterprise ML engineering. Data science teams are covered by core skills (graphify, systematic-debugging, tdd) plus custom CLAUDE.md rules in §7.4.

**DevOps / Platform**
| Skill | Source |
|---|---|
| azure-deploy | microsoft/azure-skills |
| azure-diagnostics | microsoft/azure-skills |
| azure-kubernetes | microsoft/azure-skills |
| azure-compliance | microsoft/azure-skills |

> `xixu-me/skills` was evaluated and rejected. The package contains `running-claude-code-via-litellm-copilot` which routes Claude Code requests through a third-party LiteLLM proxy — a serious enterprise security risk. The `github-actions-docs` skill from this package is not worth the risk of installing the full package. GitHub Actions guidance will be covered by CLAUDE.md rules instead.

**Embedded Software**
> No skills.sh skills exist for embedded. Custom CLAUDE.md rules are the mechanism here (see Section 7.3).

---

## 6A. Plugin Security Vetting

All plugins must pass security vetting before being added to the AI Sherpa approved list. No plugin may be added to `setup.sh` without passing these criteria.

### Vetting Criteria
| Criteria | Requirement |
|---|---|
| Publisher trust | Must be from a verified publisher: `anthropics`, `vercel-labs`, `microsoft`, `sentry`, `supabase`, `firebase`, `obra`, `mattpocock`, `pbakaus`, or explicitly reviewed |
| Install count | Minimum **50,000 installs** as a signal of community trust |
| Open source | Source code must be publicly auditable on GitHub |
| No undeclared network calls | Plugin must not call external APIs beyond what is documented |
| No secret access | Plugin must not read `.env`, credential files, or system secrets |
| Review date | Must be reviewed by AI Sherpa admin team before inclusion |

### Current Approved List
| Plugin | Publisher | Status |
|---|---|---|
| superpowers | obra | Approved |
| graphify | safishamsi | Approved — reviewed, open source |
| tdd, diagnose, triage, improve-codebase-architecture | mattpocock | Approved |
| harden, audit | pbakaus/impeccable | Approved |
| openclaw-secure-linux-cloud | xixu-me | **Rejected** — entire xixu-me package rejected (see Rejected Plugins below) |
| sentry-cli | sentry | Approved — official publisher |
| frontend-design, webapp-testing, mcp-builder | anthropics | Approved — official publisher |
| vercel-labs skills | vercel-labs | Approved — official publisher |
| azure-* skills | microsoft | Approved — official publisher |

### Rejected Plugins (Reviewed and Removed)
| Plugin | Reason Rejected |
|---|---|
| `lllllllama/ai-paper-reproduction-skill` | Wrong purpose — built for academic paper reproduction, not enterprise data science. Makes external calls to arXiv/DOI. Not useful for engineering teams. |
| `xixu-me/skills` | Contains `running-claude-code-via-litellm-copilot` which routes all Claude Code requests through a third-party proxy (LiteLLM). Enterprise security risk — code would leave Anthropic's infrastructure. Entire package rejected. |

> **Rule:** If a plugin is not on the approved list, `setup.bat` / `setup.sh` will not install it. Teams cannot add unapproved plugins without AI Sherpa team sign-off.

---

## 7. CLAUDE.md Rules

### 7.0 Mandatory Pre-Flight Check (Before EVERY Session)

Before touching any code on any project, Claude must perform the following checks in order:

**Step 1 — NDA & Confidentiality Permission**
Claude must ask the developer:
> "Before we start — can this project's code be shared with Anthropic's API for processing? Does this project have any NDA, confidentiality agreement, or export control restrictions?"

Claude must also scan the repository for any of the following files:
- `NDA.md`, `NDA.txt`, `CONFIDENTIAL.md`, `CONFIDENTIAL.txt`
- Any file with "confidential", "proprietary", "nda", or "trade-secret" in the filename
- `LICENSE` files that contain "proprietary" or "all rights reserved"

If any such file is found, Claude must stop and report it to the developer before proceeding:
> "⚠ Found a file that may indicate confidentiality restrictions: `[filename]`. Please confirm it is safe to send this project's code to Anthropic's API before we continue."

**Claude must never assume permission — explicit developer confirmation is required every session.**

**Step 2 — Architecture Understanding**
Read and understand the existing architecture before any task. Use `graphify` to explore. If architecture is unclear or not documented, ask the developer to explain it before writing any code.

---

### 7.1 Global Do's (All Domains)
1. Always complete the Pre-Flight Check (§7.0) before starting any session
2. Always write tests before or alongside new code
3. Always request code review before marking a task complete
4. Always plan before implementing (use `/writing-plans`)
5. Always state what you are about to do before doing it
6. Always prefer editing existing files over creating new ones
7. Always flag when you are uncertain — do not guess silently
8. Always confirm your understanding of the task with the developer if requirements are ambiguous

### 7.1A Secrets & File Protection (Enforced via settings.json — NOT .claudeignore)

> **Critical:** `.claudeignore` does NOT reliably prevent Claude from reading sensitive files (confirmed January 2026). The only reliable mechanism is deny rules in `settings.json`. Both global and project-level settings files are written by `setup.sh`.

**`~/.claude/settings.json` (global — applies to ALL projects on the machine):**
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

**Additional CLAUDE.md rule (probabilistic layer — belt and suspenders):**
- Never read, display, or log the contents of `.env`, `.env.*`, `*.key`, `*.pem`, or any file that contains credentials or API keys
- If a test or command prints secrets to stdout, stop immediately and do not include the output in your response

> **Known limitation:** When Claude runs tests or dev servers, it captures all terminal output. If your tests print environment variables or secrets to stdout, those will be in Claude's context window. Developers must ensure test output does not print secrets — this is a development practice requirement, not fixable by tooling alone.

### 7.2 Global Don'ts (All Domains)
1. Never run destructive commands (rm -rf, DROP TABLE, force-push, reset --hard) without explicit confirmation
2. Never commit secrets, credentials, API keys, or passwords
3. Never skip tests or mark work complete without verification
4. Never generate code for unknown APIs without checking documentation
5. Never make architectural changes without a written plan reviewed by a human
6. Never add features beyond what was explicitly requested
7. Never add error handling for scenarios that cannot happen
8. Never add comments explaining WHAT the code does — only WHY if non-obvious
9. Never push to main/master directly
10. Never assume a task is done without running it

### 7.3 Embedded-Specific Rules

**Architecture-first rule (critical for embedded):**
Before any task on an embedded project, Claude must:
1. Ask which toolchain is being used (GCC ARM / IAR / Keil / MPLAB / other) if not documented
2. Ask which RTOS or bare-metal framework is in use if not clear
3. Ask about target hardware constraints (RAM, flash, clock speed) if not documented
4. Only proceed once these are confirmed — do not assume or guess hardware context

**Hardware-critical code — human approval required:**
Any AI suggestion that affects the following must be reviewed and approved by a human before implementation:
- Interrupt service routines (ISRs)
- Memory-mapped hardware register access
- Real-time scheduling or timing logic
- Boot/startup code
- Safety-critical control loops
- DMA configuration
- Power management

Claude must explicitly flag these with: `⚠ HUMAN REVIEW REQUIRED — hardware-critical change`

**General embedded rules:**
1. Never use dynamic memory allocation (malloc/free) unless explicitly approved by the developer
2. Always annotate ISRs with timing constraints
3. Never suggest hardware register access without referencing the project's datasheet or HAL
4. Never assume code correctness without hardware-in-the-loop testing — say so explicitly
5. Apply MISRA-C guidelines for safety-critical modules
6. Always consider stack depth — prefer iterative over recursive
7. AI is effective for: logic bugs, test coverage, code style, unit tests. NOT suitable as final authority for: timing analysis, hardware-specific optimisation, real-time behaviour.

### 7.4 Data Science-Specific Rules
1. Never load full datasets into memory without checking size first
2. Always version data and models alongside code
3. Never hardcode file paths — use config or environment variables
4. Flag any data leakage risk in train/test splits

### 7.5 Backend-Specific Rules (Node.js / Python)

**Universal Backend (both Node.js and Python):**
1. Never hardcode credentials, API keys, or connection strings — always use environment variables
2. Always use parameterized queries — never concatenate user input into SQL strings (SQL injection)
3. Always validate and sanitize all external inputs at the boundary (API request, file upload, form data)
4. Never log passwords, tokens, PII, or secrets — even in debug logs
5. Always handle errors explicitly — never silently swallow exceptions
6. Always pin dependency versions — no wildcards (`*` or `^latest`)
7. Never expose internal error details (stack traces, DB errors) to API responses

**Node.js Specific:**
1. Always use `const`/`let` — never `var`
2. Use `async/await` over `.then()` chains for readability
3. Always handle unhandled Promise rejections (`process.on('unhandledRejection', ...)`)
4. Use `helmet.js` for HTTP security headers in Express apps
5. Never use `eval()` or `new Function()` with any user-supplied input
6. Always specify exact versions in `package.json` for production dependencies

**Python Specific:**
1. Always use type hints on function signatures
2. Never install packages globally — always use `venv` or `poetry`
3. Use `requirements.txt` or `pyproject.toml` with pinned versions
4. Never use bare `except:` — always catch specific exception types
5. Never use `eval()` or `exec()` with user-supplied input
6. Follow PEP 8 — AI must not generate non-PEP 8 code

### 7.5A Web / Frontend-Specific Rules
1. Never store sensitive data in `localStorage` or `sessionStorage` — use httpOnly cookies
2. Always sanitize user-generated content before rendering in DOM (XSS prevention)
3. Never use `dangerouslySetInnerHTML` without explicit sanitization
4. Always use HTTPS — never mixed content
5. Never expose API keys in frontend code or public repositories
6. Always set Content Security Policy (CSP) headers
7. Prefer server-side rendering for sensitive data — do not pass secrets as props

### 7.6 DevOps-Specific Rules
1. Never hardcode environment-specific values (IPs, credentials, region names)
2. Always use IaC (Terraform/Ansible) — never manual cloud console changes
3. Never delete infrastructure without a documented rollback plan
4. Always check blast radius before applying infrastructure changes

---

## 8. GitHub PR Integration

**Git platform: GitHub** (company-hosted or GitHub.com)

- Central AI Sherpa repo hosted on GitHub — teams clone via `git clone`
- Before opening a PR: developer runs `/requesting-code-review` — AI posts review as PR comment
- Failed security checks (`/audit`, `/harden`) flagged as PR review comments
- `graphify` knowledge graph re-indexed on merge to main via GitHub Actions workflow
- Feedback submissions (v2) will use GitHub Issues with the `ai-sherpa-feedback` label

**GitHub Actions integration (future — not v1):**
- CI step that runs AI code review automatically on every PR
- Requires a **dedicated service API key** stored as a GitHub Actions secret — separate from developer Teams Plan seats. Teams Plan seats are for human developers only; CI automation requires a separate Anthropic API key with its own spending limit.

---

## 9. Feedback Mechanism

**Status: Deferred to v2.** Not in scope for v1.

Placeholder for v2 design: lightweight manual process where developers flag incorrect AI decisions via GitHub Issues, reviewed weekly by admin team, converted into CLAUDE.md rule updates.

---

## 10. User Documentation

Each team receives:
1. **Quick Start Guide** (1 page): run `setup.bat` (Windows) or `setup.sh` (Linux/macOS), pick your domain, start working
2. **Do's & Don'ts Card** (1 page): printable reference, domain-specific version
3. **Windows Setup Guide** (0.5 page): Windows-specific steps, winget, PowerShell requirements
4. **Troubleshooting Guide**: common install failures and fixes
5. **Feedback Guide** (0.5 page): how to report AI errors (v2)

---

## 11. Centralized Update Mechanism

- All teams install from the central `ai-sherpa` GitHub repo
- `setup.bat --update` (Windows) or `setup.sh --update` (Linux/macOS) pulls latest skills, CLAUDE.md rules, and graphify updates
- Admin team controls what goes into the repo — no team can bypass rules
- Version-tagged GitHub releases so teams can pin to a stable version: `setup.bat --version v1.2`
- Updates do not overwrite project-specific CLAUDE.md customisations

---

## 12. Known Limitations (Document Honestly)

| Limitation | Impact | Mitigation |
|---|---|---|
| AI weak on large embedded codebases | Suggestions may be incorrect for 100k+ line C/C++ projects | Graphify + mandatory human review for hardware-critical code |
| CLAUDE.md rules are probabilistic, not enforced | AI may occasionally not follow rules | Regular audits, feedback mechanism catches recurring violations |
| No automated feedback loop in v1 | Errors propagate until manually caught | Manual template, weekly admin review |
| No embedded-specific skills on skills.sh | Less AI support for embedded vs web | Custom CLAUDE.md rules compensate partially |
| Setup requires Node.js for npx skillsadd | Some embedded teams may not have Node.js | setup.bat (Windows) and setup.sh (Linux/macOS) both install Node.js automatically via winget/nvm |

---

## 13. Open Questions

### Still Open
*None — all questions resolved.*

### All Resolved Decisions
- [x] **Git platform:** GitHub
- [x] **CI/CD:** GitHub Actions (developer workflow); dedicated service API key for future CI automation
- [x] **Backend languages:** Node.js and Python — rules in §7.5
- [x] **Admin owner:** AI Sherpa team
- [x] **Embedded toolchains:** Project-specific — Claude asks developer before starting (§7.3)
- [x] **Embedded hardware-critical approval:** Human review required, flagged with ⚠ warning (§7.3)
- [x] **Primary OS:** Windows — setup.bat required alongside setup.sh
- [x] **Prerequisites:** Node.js and Git auto-installed by setup.bat / setup.sh
- [x] **API access:** Claude Teams Plan per-seat (recommended); or dedicated API keys per team with spending caps
- [x] **Single shared API key:** Explicitly rejected — no per-user tracking, budget exhaustion risk
- [x] **Plugin security:** Approved whitelist in §6A — `lllllllama` and `xixu-me` reviewed and rejected
- [x] **High-security teams:** No seat provisioned by management — excluded at access level, not config level
- [x] **NDA/confidentiality:** Pre-flight check every session — Claude asks permission + scans repo (§7.0)
- [x] **Feedback mechanism:** Deferred to v2
- [x] **.env protection:** settings.json deny rules — `.claudeignore` confirmed unreliable
- [x] **Network access:** Developer machines have direct Anthropic API access
- [x] **Update cadence:** Frequent during pilot, less frequent as system matures
- [x] **Pilot:** Embedded software projects first (2-3 projects, 2-4 weeks)
- [x] **gstack:** Used as design reference/inspiration only — not an installed dependency. Risk: personal repo, breaks on Claude Code updates, optimised for solo founders not enterprise teams.
