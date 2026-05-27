# AI Sherpa — Plan 3: User Documentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create all five user-facing documentation files that developers need to adopt AI Sherpa: quick-start guide, Windows setup guide, domain do's & don'ts reference card, troubleshooting guide, and feedback guide.

**Architecture:** All docs live in `docs/`. Pure Markdown, no build step. Each file has one audience and one job. `user-guide.md` is the entry point; all other docs are linked from it. Content is grounded in the actual behaviour of `setup.sh`/`setup.ps1` and the CLAUDE.md rules already in the repo.

**Tech Stack:** Markdown only. No tooling required.

**Plans in this series:**
- Plan 1: Repository structure + config files ✅ DONE (v0.1.0)
- Plan 2: Setup scripts ✅ DONE (v0.2.0)
- **Plan 3 (this plan):** User documentation ← START HERE

---

## File Map

| File | Action | Audience | Max Length |
|---|---|---|---|
| `docs/user-guide.md` | Create | All developers — first doc they read | ~80 lines |
| `docs/windows-setup.md` | Create | Windows developers needing step-by-step | ~70 lines |
| `docs/dos-and-donts.md` | Create | All developers — printable reference card | ~100 lines |
| `docs/troubleshooting.md` | Create | Developers hitting install or runtime errors | ~90 lines |
| `docs/feedback-guide.md` | Create | Developers wanting to report AI errors | ~30 lines |

---

## Design Notes (Read Before Implementing)

**Ground every claim in actual system behaviour.** Do not describe what the system "will" do or "should" do — describe what it actually does based on the scripts and CLAUDE.md files already in the repo. If a step isn't in the scripts, don't document it.

**Actual repo URL is not known yet.** Use `<ai-sherpa-repo-url>` as a placeholder everywhere a git clone URL is needed.

**Primary OS is Windows.** The user-guide leads with Windows. Linux/macOS is secondary.

**Domain names must match exactly:** `embedded`, `web`, `backend`, `data`, `devops` — these are the exact values used in setup.sh/setup.ps1 and the domains/ folder names.

**Skills installed by setup:** obra/superpowers (which includes systematic-debugging, writing-plans, requesting-code-review, tdd, brainstorming), safishamsi/graphify, mattpocock/skills (tdd, diagnose, triage, improve-codebase-architecture), pbakaus/impeccable (harden, audit), sentry/dev.

**Verification approach for docs:** Instead of unit tests, each task ends with a content checklist — a set of topics that MUST be present. The implementer reads the finished doc and confirms each topic is covered before committing.

---

## Task 1: user-guide.md — Developer Quick Start

**Files:**
- Create: `docs/user-guide.md`

- [ ] **Step 1: Create `docs/user-guide.md` with the following exact content**

```markdown
# AI Sherpa — Developer Quick Start

AI Sherpa configures Claude Code for your project in 5 minutes: guardrails, domain-specific rules, secrets protection, and a codebase knowledge graph — all set up automatically.

---

## What Setup Does

When you run `setup.bat` (Windows) or `setup.sh` (Linux/macOS), it:

1. Installs Node.js, Git, and Claude Code CLI if missing
2. Installs core AI skills: systematic debugging, TDD, code review, planning, graphify
3. Installs domain-specific skills (web and DevOps only)
4. Writes secrets protection rules to `~/.claude/settings.json` (global) and `.claude/settings.json` (project)
5. Copies your domain's CLAUDE.md rules into your project root

---

## Quick Start — Windows

> **Run setup from your project directory, not from inside the AI Sherpa repo.**

```
cd C:\path\to\your-project
C:\tools\ai-sherpa\setup.bat
```

Answer two prompts: domain (1–5) and new or existing project (1–2). Setup takes 2–5 minutes.

After setup, restart your terminal, then:
```
claude
```

Inside Claude Code, index your codebase once:
```
/graphify
```

---

## Quick Start — Linux / macOS

```bash
cd ~/path/to/your-project
bash ~/tools/ai-sherpa/setup.sh
```

After setup:
```bash
claude
/graphify
```

---

## Domain Options

| Number | Domain | For |
|---|---|---|
| 1 | Embedded | C/C++, firmware, RTOS |
| 2 | Web / Frontend | React, Vue, Angular, HTML/CSS |
| 3 | Backend | Node.js, Python APIs |
| 4 | Data Science / ML | Python notebooks, pipelines |
| 5 | DevOps / Platform | Terraform, Ansible, CI/CD |

---

## Skills Available After Setup

| Skill | Type inside Claude Code | Purpose |
|---|---|---|
| `/graphify` | `/graphify` | Index codebase — run once, reduces token cost 6x–49x |
| Systematic debugging | `/systematic-debugging` | Structured root-cause diagnosis |
| Writing plans | `/writing-plans` | Step-by-step implementation plan before coding |
| Code review | `/requesting-code-review` | AI reviews your code before you mark it done |
| TDD | `/tdd` | Test-driven development workflow |
| Harden | `/harden` | Security hardening review |
| Audit | `/audit` | Full code audit |

---

## The Pre-Flight Check

At the start of every Claude Code session, Claude asks:

> "Before we start — can this project's code be shared with Anthropic's API? Does this project have any NDA, confidentiality agreement, or export control restrictions?"

Answer honestly. Claude also scans automatically for `NDA.md`, `CONFIDENTIAL.md`, and similar files. If found, it stops and asks for explicit confirmation before proceeding.

**High-security projects:** Do not use Claude Code on projects that management has flagged as restricted. Access is controlled at the seat level — if you were not given a Claude Code seat for a project, that is intentional.

---

## Updating AI Sherpa

```
C:\tools\ai-sherpa\setup.bat --update          (Windows)
bash ~/tools/ai-sherpa/setup.sh --update        (Linux/macOS)
```

Updates core skills and secrets settings. Your project's CLAUDE.md is never overwritten.

---

## More Guides

- [Windows Setup (step-by-step)](windows-setup.md)
- [Do's & Don'ts Reference Card](dos-and-donts.md)
- [Troubleshooting](troubleshooting.md)
- [How to Report AI Errors](feedback-guide.md)
```

- [ ] **Step 2: Verify content checklist (read the file, confirm each item is present)**

Check all of the following are present in `docs/user-guide.md`:
- [ ] Describes what setup does (numbered list of steps)
- [ ] Windows quick start with correct commands
- [ ] Linux/macOS quick start
- [ ] Domain table (5 domains, numbers match setup prompts)
- [ ] Skills table with slash-command names
- [ ] Pre-flight check explained
- [ ] Update command for both platforms
- [ ] Links to the other 4 docs

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs: add developer quick start guide"
```

---

## Task 2: windows-setup.md — Windows Step-by-Step

**Files:**
- Create: `docs/windows-setup.md`

- [ ] **Step 1: Create `docs/windows-setup.md` with the following exact content**

```markdown
# AI Sherpa — Windows Setup Guide

For the quick-start version, see [user-guide.md](user-guide.md). This guide covers Windows-specific steps and common issues.

---

## What Gets Installed Automatically

`setup.bat` installs the following if not already present:

| Tool | How installed | Required |
|---|---|---|
| Node.js 20 | winget (Microsoft app store CLI) | Yes |
| Git | winget | Yes |
| Claude Code CLI | npm install -g | Yes |
| AI skills | npx skillsadd | Yes |

You do not need to install these manually unless `setup.bat` fails. See [Troubleshooting](troubleshooting.md) if it does.

---

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (pre-installed on Windows 10/11 — no action needed)
- `winget` (pre-installed on Windows 11; available on Windows 10 via Microsoft Store)
- Internet access

---

## Step-by-Step

### Step 1 — Verify winget is available

Open Command Prompt or PowerShell and run:
```
winget --version
```
Expected: `v1.x.x`

If you get "winget is not recognized", see [winget-not-found](troubleshooting.md#winget-not-found).

### Step 2 — Clone AI Sherpa (one-time, anywhere on your machine)

```
git clone <ai-sherpa-repo-url> C:\tools\ai-sherpa
```

If Git is not yet installed, download from https://git-scm.com and install it first.

### Step 3 — Open a terminal in your project directory

In File Explorer: navigate to your project folder, hold **Shift**, right-click the folder → "Open PowerShell window here" or "Open Command Prompt here".

Or from any terminal:
```
cd C:\path\to\your-project
```

**Do NOT run setup.bat from inside `C:\tools\ai-sherpa`.** Run it from your project directory.

### Step 4 — Run setup.bat

```
C:\tools\ai-sherpa\setup.bat
```

You will be asked two questions:
1. Which domain? (Enter 1–5)
2. New or existing project? (Enter 1 or 2)

Setup takes 2–5 minutes. You will see `[AI Sherpa] Setup Complete` when done.

### Step 5 — Restart your terminal

Close and reopen your terminal. This is required for Node.js and Git to appear on your PATH.

### Step 6 — Verify the installation

```powershell
node --version      # Expected: v20.x.x
git --version       # Expected: git version 2.x.x
claude --version    # Expected: a version number
```

Check secrets protection is active:
```powershell
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json
```
Expected: shows a `permissions.deny` array containing `.env` rules.

Check CLAUDE.md was installed in your project:
```powershell
Test-Path ".\CLAUDE.md"
```
Expected: `True`

### Step 7 — Index your codebase

Start Claude Code:
```
claude
```

Inside Claude Code, run:
```
/graphify
```

This indexes your codebase and dramatically reduces token cost for future sessions. Run it once after setup, and again after large codebase changes.

---

## Updating AI Sherpa

```
C:\tools\ai-sherpa\setup.bat --update
```

Run this when the AI Sherpa team announces an update. It updates skills and settings but never touches your project's CLAUDE.md.
```

- [ ] **Step 2: Verify content checklist**

Check all of the following are present in `docs/windows-setup.md`:
- [ ] Lists what gets installed automatically (table)
- [ ] System requirements (Windows version, PowerShell, winget)
- [ ] Step 1: verify winget
- [ ] Step 2: clone repo
- [ ] Step 3: open terminal in project dir (with the "do NOT run from inside AI Sherpa" warning)
- [ ] Step 4: run setup.bat with expected output
- [ ] Step 5: restart terminal
- [ ] Step 6: verification commands (node, git, claude, settings.json, CLAUDE.md)
- [ ] Step 7: start claude + /graphify
- [ ] Update command

- [ ] **Step 3: Commit**

```bash
git add docs/windows-setup.md
git commit -m "docs: add Windows step-by-step setup guide"
```

---

## Task 3: dos-and-donts.md — Domain Reference Cards

**Files:**
- Create: `docs/dos-and-donts.md`

This is a printable reference card. Each section is one domain. Rules are taken directly from the CLAUDE.md files in `core/` and `domains/`.

- [ ] **Step 1: Create `docs/dos-and-donts.md` with the following exact content**

```markdown
# AI Sherpa — Do's & Don'ts Reference

These rules are enforced in all AI Sherpa-configured projects via CLAUDE.md. Rules marked **[ALL]** apply to every domain. Domain-specific rules are additive.

---

## [ALL DOMAINS] — Universal Rules

### Always Do
- Complete the pre-flight NDA check before starting any session
- Write tests before or alongside new code
- Request code review before marking a task complete (`/requesting-code-review`)
- Plan before implementing non-trivial tasks (`/writing-plans`)
- State what you are about to do before doing it
- Flag uncertainty explicitly — never guess silently

### Never Do
- Run destructive commands (`rm -rf`, `DROP TABLE`, force-push, `reset --hard`) without explicit confirmation
- Commit secrets, credentials, API keys, or passwords
- Read, display, or log `.env`, `*.key`, `*.pem`, or credential files
- Skip tests or mark work complete without running them
- Make architectural changes without a written plan reviewed by a human
- Add features beyond what was explicitly requested
- Push to main/master directly

---

## [EMBEDDED] — C/C++, Firmware, RTOS

### Always Do
- Ask about toolchain, RTOS, RAM/flash/clock constraints before starting any task
- Annotate ISRs with timing constraints and expected execution time
- State explicitly: "This suggestion requires hardware-in-the-loop testing to verify"
- Prefer iterative over recursive — consider stack depth impact

### Never Do
- Use dynamic memory allocation (`malloc`/`free`) without explicit developer approval
- Suggest hardware register access without referencing the project's datasheet or HAL
- Claim code correctness without hardware-in-the-loop testing

### Hardware-Critical Flag
Any change to the following must be flagged with `⚠ HUMAN REVIEW REQUIRED — hardware-critical change` before proceeding:
- Interrupt service routines (ISRs)
- Memory-mapped hardware register access
- Real-time scheduling or timing logic
- Boot/startup code
- Safety-critical control loops
- DMA configuration
- Power management sequences

---

## [WEB / FRONTEND] — React, Vue, Angular, HTML/CSS

### Always Do
- Sanitize all user-generated content before rendering to the DOM
- Set Content Security Policy (CSP) headers on all responses
- Use HTTPS everywhere — flag any mixed content immediately
- Use `httpOnly` cookies for session tokens
- Add `rel="noopener noreferrer"` to external links (`target="_blank"`)
- Validate file type AND size on file upload inputs

### Never Do
- Store sensitive data (tokens, PII, API keys) in `localStorage` or `sessionStorage`
- Use `dangerouslySetInnerHTML` without explicit sanitization — flag and ask developer
- Expose API keys or secrets in frontend source code or public repos
- Use inline `<script>` blocks that bypass CSP
- Pass secrets or credentials as React/Vue props or component state

---

## [BACKEND] — Node.js, Python

### Always Do
- Use parameterized queries — never concatenate user input into SQL strings
- Validate and sanitize all external inputs at the system boundary
- Handle errors explicitly — never silently swallow exceptions
- Pin all dependency versions — no wildcards (`*`, `^latest`)
- Return generic error messages to API consumers — never expose stack traces

### Never Do
- Hardcode credentials, API keys, or connection strings
- Log passwords, tokens, PII, or secrets — even at DEBUG level
- Use `eval()` or `exec()` with any user-supplied input
- Expose stack traces or DB errors in API responses

**Node.js also:** always `const`/`let` (never `var`), use `async/await`, use `helmet` for HTTP headers.

**Python also:** always type hints, always specific exception types (never bare `except:`), always PEP 8.

---

## [DATA SCIENCE / ML] — Python, Notebooks, Pipelines

### Always Do
- Check dataset size before loading (`df.shape`, `wc -l`, file size check)
- Version data and models alongside code (DVC, MLflow, or equivalent)
- Use environment variables or config files for file paths — never hardcode
- Flag any risk of data leakage between train/test splits
- Set reproducible random seeds (`random.seed()`, `np.random.seed()`, `torch.manual_seed()`)

### Never Do
- Load a full dataset without first checking its size
- Hardcode absolute file paths — use `pathlib.Path` or config variables
- Commit large data files or model weights to Git — use DVC or cloud storage
- Use the same data split for both hyperparameter tuning and final evaluation
- Process datasets that may contain PII without confirming anonymization

---

## [DEVOPS / PLATFORM] — Terraform, Ansible, CI/CD

### Always Do
- Use Infrastructure-as-Code — never make manual cloud console changes
- Estimate and state blast radius before any infrastructure change
- Document a rollback plan before deleting or modifying infrastructure
- Store all secrets in a secrets manager — never in code or config files
- Tag all cloud resources with environment, owner, and cost-centre

### Never Do
- Hardcode environment-specific values (IPs, credentials, region names) in IaC files
- Run `terraform apply` without first reviewing `terraform plan`
- Delete databases, queues, or storage buckets without an approved rollback plan
- Store secrets as plaintext in CI/CD pipeline YAML — use the platform's secret store
- Give IAM roles more permissions than needed (principle of least privilege)
- Add secrets or credentials as plaintext values in `docker-compose.yml`

**GitHub Actions also:** always pin actions to a SHA (`uses: actions/checkout@abc1234`), never print secrets to logs.
```

- [ ] **Step 2: Verify content checklist**

Check all of the following are present in `docs/dos-and-donts.md`:
- [ ] Universal [ALL] always/never rules
- [ ] Embedded rules + hardware-critical flag list (7 categories)
- [ ] Web/Frontend always/never rules
- [ ] Backend always/never rules (with Node.js and Python addendums)
- [ ] Data Science always/never rules including PII rule
- [ ] DevOps always/never rules including docker-compose plaintext rule and GitHub Actions SHA pin

- [ ] **Step 3: Commit**

```bash
git add docs/dos-and-donts.md
git commit -m "docs: add domain do's and don'ts reference card"
```

---

## Task 4: troubleshooting.md — Common Issues and Fixes

**Files:**
- Create: `docs/troubleshooting.md`

Every issue listed here must be something that can actually happen given the setup scripts. No invented scenarios.

- [ ] **Step 1: Create `docs/troubleshooting.md` with the following exact content**

```markdown
# AI Sherpa — Troubleshooting

---

## Installation Issues

### `node` not found after setup completes

**Symptom:** After `setup.bat` or `setup.sh` finishes, running `node --version` gives "command not found" or "not recognized".

**Cause:** Node.js was just installed, but your current terminal session was open before the PATH was updated.

**Fix:** Close the terminal completely and open a new one. Then run `node --version` again.

---

### `winget` not found (Windows) {#winget-not-found}

**Symptom:** `winget --version` gives "'winget' is not recognized as an internal or external command".

**Cause:** winget is not installed or not on PATH.

**Fix:**
1. Open the Microsoft Store
2. Search for "App Installer"
3. Install or update it
4. Restart your terminal and try again

---

### PowerShell execution policy error (Windows)

**Symptom:** Running `setup.bat` produces: "cannot be loaded because running scripts is disabled on this system".

**Cause:** Your machine's PowerShell execution policy blocks script execution. `setup.bat` uses `-ExecutionPolicy Bypass` to handle this, but some corporate group policies override it.

**Fix:** Ask your IT admin to allow script execution for your user account, or run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Then re-run `setup.bat`.

---

### `setup.bat` flashes and closes immediately (Windows)

**Symptom:** A black window appears and disappears in under a second.

**Cause:** PowerShell is not available, or the script failed immediately.

**Fix:**
1. Open PowerShell manually: Start → search "PowerShell" → Open
2. Run: `powershell --version` — expected output: `PowerShell 5.x`
3. Then run setup manually: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\tools\ai-sherpa\setup.ps1`
4. The error message will now be visible in the window.

---

### `npx skillsadd` fails during setup

**Symptom:** Setup prints "npx skillsadd: command failed" or hangs during skill installation.

**Cause:** Network error, npm misconfiguration, or a temporary issue with skills.sh.

**Fix:**
1. Check your internet connection
2. Run the failed command manually: `npx skillsadd obra/superpowers`
3. If it fails with a proxy error, ask IT to whitelist `registry.npmjs.org` and `skills.sh`
4. Re-run setup: `setup.bat` (setup is idempotent — safe to run again)

---

### `claude` not found after setup

**Symptom:** `claude --version` gives "not recognized" even after setup finished successfully.

**Fix:**
1. Restart your terminal (most common fix)
2. If still not found, run manually: `npm install -g @anthropic-ai/claude-code`
3. If npm itself is not found, ensure Node.js 20+ is installed: `node --version`

---

### CLAUDE.md was not created in my project

**Symptom:** After setup completes, `CLAUDE.md` does not exist in your project directory.

**Likely causes:**
1. You ran `setup.bat` from inside the AI Sherpa repo directory — it detects this and exits with a warning
2. You ran setup from a different directory than your project

**Fix:** Navigate to your actual project directory and re-run setup:
```
cd C:\path\to\your-project
C:\tools\ai-sherpa\setup.bat
```

---

### `.claude/settings.json` was not created

**Symptom:** After setup, `$env:USERPROFILE\.claude\settings.json` (Windows) or `~/.claude/settings.json` (Linux/macOS) does not exist.

**Fix:** Re-run setup. If it still fails, create the directory and copy manually:

```powershell
# Windows
$dir = "$env:USERPROFILE\.claude"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir }
Copy-Item "C:\tools\ai-sherpa\settings\settings-template.json" "$dir\settings.json"
```

```bash
# Linux/macOS
mkdir -p ~/.claude
cp ~/tools/ai-sherpa/settings/settings-template.json ~/.claude/settings.json
```

---

## Runtime Issues

### `/graphify` command not found inside Claude Code

**Symptom:** Typing `/graphify` in Claude Code gives an error or does nothing.

**Cause:** The graphify skill was not installed, or Claude Code was not restarted after skill installation.

**Fix:**
1. Exit Claude Code: `Ctrl+C`
2. Run: `npx skillsadd safishamsi/graphify`
3. Restart Claude Code: `claude`
4. Try `/graphify` again

---

### Claude ignores CLAUDE.md rules

**Symptom:** Claude does not follow rules in CLAUDE.md — for example, skips the pre-flight check.

**Cause:** Very long CLAUDE.md files can cause Claude to deprioritize content near the end. AI Sherpa keeps each layer under its line limit to prevent this.

**Fix:**
1. Check line count: the combined total of all three CLAUDE.md layers should be under ~300 lines
2. Run `/reading-claude-md` if available, or start a fresh session
3. Keep project CLAUDE.md under 100 lines — move verbose notes to a separate doc

---

### Secrets protection not blocking `.env` access

**Symptom:** Claude reads a `.env` file when it should be blocked.

**Cause:** The `settings.json` deny rules may not have been written, or were overwritten.

**Fix:** Verify the settings file exists and has deny rules:
```powershell
# Windows
Get-Content "$env:USERPROFILE\.claude\settings.json" | ConvertFrom-Json
```
```bash
# Linux/macOS
cat ~/.claude/settings.json | python3 -m json.tool
```
Expected: `permissions.deny` array with at least 13 entries.

If missing, re-run setup or copy manually (see `.claude/settings.json` was not created above).
```

- [ ] **Step 2: Verify content checklist**

Check all of the following issues are documented in `docs/troubleshooting.md`:
- [ ] `node` not found after setup (restart terminal)
- [ ] winget not found (Microsoft Store)
- [ ] PowerShell execution policy error
- [ ] setup.bat flashes and closes
- [ ] npx skillsadd network failure
- [ ] claude not found after setup
- [ ] CLAUDE.md not created (wrong directory)
- [ ] settings.json not created (manual copy fix)
- [ ] /graphify not found (reinstall skill)
- [ ] Claude ignoring CLAUDE.md rules (line count too long)
- [ ] Secrets protection not blocking .env

- [ ] **Step 3: Commit**

```bash
git add docs/troubleshooting.md
git commit -m "docs: add troubleshooting guide"
```

---

## Task 5: feedback-guide.md — How to Report AI Errors

**Files:**
- Create: `docs/feedback-guide.md`

This is a short guide. The automated feedback mechanism is v2 — not built yet. v1 is a manual process via GitHub Issues.

- [ ] **Step 1: Create `docs/feedback-guide.md` with the following exact content**

```markdown
# AI Sherpa — How to Report AI Errors

If Claude gives incorrect, unsafe, or unhelpful advice, report it so the AI Sherpa team can improve the rules.

---

## When to Report

Report when Claude:
- Ignores a CLAUDE.md rule (e.g. skips the pre-flight check)
- Gives unsafe advice for your domain (e.g. dynamic allocation in embedded code without warning)
- Suggests code that is wrong for your specific toolchain or framework
- Misses a security issue that AI Sherpa rules should have caught
- Gets stuck in a loop or refuses a reasonable request

Do NOT report general Claude limitations (it doesn't know your internal APIs, it can't test on hardware, etc.) — those are expected.

---

## How to Report (v1 — Manual)

1. Open a GitHub Issue in the AI Sherpa repo
2. Add the label `ai-sherpa-feedback`
3. Include:
   - **What you asked Claude to do** (1–2 sentences)
   - **What Claude did** (copy the problematic response or describe it)
   - **What it should have done instead** (your expectation)
   - **Your domain** (embedded / web / backend / data / devops)
   - **Which CLAUDE.md rule was violated** (if you can identify it)

**Example issue title:** `[feedback] Claude suggested malloc in embedded ISR without hardware-critical flag`

The AI Sherpa team reviews feedback weekly. High-quality feedback (with clear examples) is converted into updated CLAUDE.md rules within 1–2 weeks.

---

## What Happens With Your Feedback

1. AI Sherpa admin reviews the report
2. If the rule gap is confirmed: CLAUDE.md is updated in the repo
3. All teams get the fix on their next `setup.bat --update`

---

## Automated Feedback (Coming in v2)

A structured in-tool feedback mechanism is planned for v2. It will let developers flag issues directly inside Claude Code without leaving the terminal. Until then, GitHub Issues is the process.
```

- [ ] **Step 2: Verify content checklist**

Check all of the following are present in `docs/feedback-guide.md`:
- [ ] When to report (with examples)
- [ ] When NOT to report
- [ ] Step-by-step issue filing process (label, 5 required fields)
- [ ] Example issue title
- [ ] What happens with feedback (SLA and propagation)
- [ ] v2 placeholder

- [ ] **Step 3: Commit**

```bash
git add docs/feedback-guide.md
git commit -m "docs: add feedback submission guide"
```

---

## Task 6: Verification Pass

Run all checks before tagging Plan 3 complete.

- [ ] **Step 1: Verify all 5 docs exist**

```powershell
@("docs\user-guide.md","docs\windows-setup.md","docs\dos-and-donts.md",
  "docs\troubleshooting.md","docs\feedback-guide.md") | ForEach-Object {
    "$_`: $(if (Test-Path $_) { 'EXISTS' } else { 'MISSING' })"
}
```

Expected: all 5 show `EXISTS`

- [ ] **Step 2: Check line counts**

```powershell
Get-ChildItem docs\*.md | Where-Object { $_.Name -ne "*.md" } |
  ForEach-Object { "$($_.Name): $((Get-Content $_.FullName).Count) lines" }
```

Expected approximate ranges:
- `user-guide.md` → 60–90 lines
- `windows-setup.md` → 60–80 lines
- `dos-and-donts.md` → 90–110 lines
- `troubleshooting.md` → 80–110 lines
- `feedback-guide.md` → 25–40 lines

- [ ] **Step 3: Verify all internal links resolve**

Check that every `[link text](filename.md)` in user-guide.md points to a file that exists:

```powershell
$content = Get-Content "docs\user-guide.md" -Raw
$links = [regex]::Matches($content, '\[.*?\]\((.*?\.md.*?)\)')
$links | ForEach-Object {
  $target = $_.Groups[1].Value -split '#' | Select-Object -First 1
  $path = "docs\$target"
  "$target`: $(if (Test-Path $path) { 'OK' } else { 'BROKEN' })"
}
```

Expected: all links show `OK`

- [ ] **Step 4: Verify domain names are consistent**

Domain names in user-guide.md must match exactly: embedded, web, backend, data, devops (lowercase, matching the domains/ folder names and setup script domain map).

```powershell
Select-String -Path docs\user-guide.md -Pattern "embedded|web|backend|data|devops" | Select-Object -ExpandProperty Line
```

Expected: all domain references use lowercase names matching the table in Task 1.

- [ ] **Step 5: Verify dos-and-donts.md matches actual CLAUDE.md rules**

Spot-check 3 rules:
1. The hardware-critical flag wording in dos-and-donts.md must match `domains/embedded/CLAUDE.md`:
   ```powershell
   Select-String "HUMAN REVIEW REQUIRED" docs\dos-and-donts.md, domains\embedded\CLAUDE.md
   ```
   Expected: same phrase in both files.

2. The `docker-compose` rule in DevOps section must match `domains/devops/CLAUDE.md`:
   ```powershell
   Select-String "docker-compose" docs\dos-and-donts.md, domains\devops\CLAUDE.md
   ```
   Expected: both files reference it.

3. The PII rule in Data Science must match `domains/data/CLAUDE.md`:
   ```powershell
   Select-String "PII" docs\dos-and-donts.md, domains\data\CLAUDE.md
   ```
   Expected: both files reference it.

- [ ] **Step 6: Final commit and tag**

```bash
git add .
git commit -m "chore: plan 3 verification pass — all docs complete"
git tag v0.3.0
```

---

## Self-Review: Spec Coverage Check

| Requirement (from §10) | Covered by Task |
|---|---|
| Quick Start Guide — run setup, pick domain, start working | Task 1 (user-guide.md) |
| Do's & Don'ts Card — printable, domain-specific | Task 3 (dos-and-donts.md) |
| Windows Setup Guide — Windows-specific steps | Task 2 (windows-setup.md) |
| Troubleshooting Guide — common install failures and fixes | Task 4 (troubleshooting.md) |
| Feedback Guide — how to report AI errors | Task 5 (feedback-guide.md) |

All 5 doc types from §10 are covered.

**Not covered (out of scope for docs):**
- Automated feedback mechanism (v2, deferred per §9)
- GitHub Actions CI workflow (referenced in §8, but it's infrastructure not docs)
