# AI Sherpa — How to Report AI Errors

If Claude gives incorrect, unsafe, or unhelpful advice, report it so the AI Sherpa team can improve the rules.

---

## When to Report

Report when Claude:
- Ignores a CLAUDE.md rule (e.g. skips the pre-flight check)
- Gives unsafe advice for your domain (e.g. suggests dynamic allocation in embedded code without a hardware-critical warning)
- Suggests code that is wrong for your specific toolchain or framework
- Misses a security issue that AI Sherpa rules should have caught
- Gets stuck in a loop or refuses a reasonable request

Do NOT report general Claude limitations (it doesn't know your internal APIs, it can't test on hardware, it makes occasional mistakes) — those are expected.

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
