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
