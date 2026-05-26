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
Before any task, read and understand the existing architecture. Use graphify to explore the codebase (graphify is the codebase knowledge-graph tool — installed by setup.bat/setup.sh, invoked via `/graphify` in Claude Code). If the architecture is unclear or undocumented, ask the developer to explain it before writing any code.

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
9. Add error handling for scenarios that are provably impossible given the current system design — if unsure, ask before skipping
10. Add comments explaining WHAT code does — only WHY if non-obvious
11. Push to main/master directly
12. Assume a task is done without running it

---

## Secrets Protection

`.claudeignore` is unreliable for blocking file access. Protection is enforced via `settings.json` deny rules (written by setup script). As an additional layer, never read or reference the content of any file matching: `.env`, `.env.*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, files in `secrets/`, `credentials/`, `.aws/`, `.ssh/`.
