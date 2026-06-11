# CLAUDE.md

Engineering guidelines for AI-assisted development across our **embedded**,
**web**, and **AI** domains.

## Purpose & Philosophy

We are a mid-sized company building across embedded systems, web platforms, and
AI. These guidelines exist to make AI-assisted coding *more* effective, not to
box it in. The intent is to reduce common failure modes while leaving room for
the model to apply judgment, propose better approaches, and use the full power
of AI on each task.

**Default posture:** bias toward completeness. Do the complete thing — full
implementations, full test coverage, all edge cases — because AI-assisted coding
makes the marginal cost of completeness near-zero. This applies across all work,
not just large tasks. The model is trusted to use the full power of AI; these
guidelines steer that power toward thorough, finished work rather than limiting
it.

---

## Hard Constraints

These are non-negotiable structural rules.

- **Modularity:** Code must be modular. Decompose by responsibility, not
  convenience.
- **File size:** No single source file may exceed **2000 lines**. Approaching
  the limit is a signal to split along clean boundaries — not to compress.
- **Domain awareness:** Embedded, web, and AI code have different constraints
  (memory/timing for embedded, security/UX for web, reproducibility/data for
  AI). Apply the conventions of the domain you're working in.

---

## Guardrails

Non-negotiable operational rules. These sit alongside Hard Constraints.

### Secrets Protection

- Never read, display, or log the contents of files matching: `.env`, `.env.*`,
  `*.key`, `*.pem`, `*.p12`, `*.pfx`, or anything under `secrets/`,
  `credentials/`, `.aws/`, `.ssh/`.
- If a command prints secrets to stdout — stop and do not include the output in
  your response.
- `.claudeignore` is unreliable for blocking file access. Protection is enforced
  via `settings.json` deny rules (written by the setup script); the rules above
  are an additional behavioral layer.
- Never commit secrets, credentials, API keys, or passwords.

### Destructive-Command Gate

- Require explicit developer confirmation before running destructive commands:
  `rm -rf`, `DROP TABLE`, `git push --force`, `git reset --hard`.
- Never push to `main` / `master` directly.

---

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If something is unclear, stop. Name what's confusing. Ask.

---

## 2. Simplicity First (subordinate to Boil the Lake)

**No speculative complexity — but never at the cost of completeness.**

- No abstractions for single-use code.
- No error handling for genuinely impossible scenarios.
- **Precedence:** When simplicity and completeness conflict, completeness wins.
  This principle only forbids *speculative* complexity — abstractions and code
  paths nothing actually needs. It must never be used to justify skipping real
  requirements, edge cases, or tests. If in doubt, build the complete version
  (see "Boil the Lake").

---

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't refactor things that aren't broken.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

---

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria enable independent looping. Weak criteria ("make it
work") require constant clarification.

---

## 5. Boil the Lake (Completeness) — Primary Principle

**This is our team's core inclination.** When in doubt, do the complete thing.

AI-assisted coding makes the marginal cost of completeness near-zero. When the
complete implementation costs minutes more than the shortcut, take the complete
path — every time.

- **Lake vs. ocean:** A "lake" is boilable — full test coverage for a module,
  all edge cases, complete error paths. An "ocean" is not — full-system
  rewrites, multi-quarter migrations. Boil lakes. Flag oceans as out of scope.
- **Completeness is cheap.** Prefer the full implementation over the 90% one
  when the delta is small. Don't defer tests to a "follow-up" — tests are the
  cheapest lake to boil.
- When estimating, frame both costs: e.g. "~2 weeks human / ~1 hour
  AI-assisted."

---

## 6. Search Before Building

First instinct: "has someone already solved this?" — not "let me design it from
scratch." Before building anything involving unfamiliar patterns,
infrastructure, or runtime capabilities, check first. The cost of checking is
near-zero; the cost of reinventing a worse version is not.

**Three layers of knowledge:**
- **Layer 1 — Tried and true.** Standard, battle-tested patterns. Risk: assuming
  the obvious answer is right when occasionally it isn't.
- **Layer 2 — New and popular.** Current best practices and ecosystem trends.
  Search for these, but scrutinize — the crowd can be wrong about new things.
- **Layer 3 — First principles.** Original reasoning about the specific problem.
  The most valuable layer. Prize it.

The best work avoids reinventing the wheel (Layer 1) *and* makes out-of-
distribution observations (Layer 3). When the conventional approach is provably
wrong for our case, name it and build on that insight.

---

## 7. User Sovereignty

**AI recommends. Users decide. This rule overrides all others.**

Model agreement is a strong signal, not a mandate. Engineers hold context the
model lacks: domain specifics, business relationships, timing, taste, unshared
plans. When the model is confident a change is better but it diverges from the
engineer's stated direction:

1. Present the recommendation.
2. Explain why it seems better.
3. State what context might be missing.
4. **Ask. Never act unilaterally.**

The pattern is generation → verification: AI generates, the human verifies and
decides. Never skip verification out of confidence.

---

## How These Work Together

- *Think Before Coding* and *Search Before Building* run first: understand the
  problem and the landscape.
- *Simplicity First* is subordinate to *Boil the Lake*: avoid speculative
  complexity, but when the two conflict, completeness always wins. Build the
  full version of what's needed.
- *Surgical Changes* and *Goal-Driven Execution* govern how changes are made and
  verified.
- *User Sovereignty* sits above all of them: search first, build the complete
  version of the *right* thing — but the engineer makes the final call.

The worst outcome is a complete version of something that already exists as a
one-liner. The best outcome is a complete version of something nobody thought of
yet — because you searched, understood the landscape, and saw what others missed.

---

## Plugin & Skill Invocation Contract — Global

These plugins ship with AI Sherpa globally. Reach for them by default; the rules
below override any defaults from their `SKILL.md` descriptions.

### MANDATORY — invoke without asking

| When the user…                                          | Invoke                                  | Why                                  |
|---------------------------------------------------------|-----------------------------------------|--------------------------------------|
| says "build a feature", "add X", or "modify behavior"   | `superpowers:brainstorming`             | Hard gate before any implementation  |
| asks to write tests for new code                        | `superpowers:test-driven-development`   | Test-first standard                  |
| asks for code review on current branch or a PR          | `superpowers:requesting-code-review`    | Mandatory pre-merge                  |

> **Domain-specific contracts** live in `ai-sherpa-<domain>` skills installed under `~/.claude/skills/`. Each fires when a task matches its domain (e.g. `ai-sherpa-embedded` for Zephyr/firmware tasks). Domain MANDATORY tables, Always-Do / Never-Do rules, and toolchain lookups are inside those skill bodies, not in this file.

### Self-described — auto-fires for its listed use cases, no override needed

- `superpowers` — workflow skills (brainstorming, writing-plans, executing-plans, verification-before-completion, ...); the MANDATORY rules above cover the cases where this project has an opinion.
- `fullstack-dev-skills` — ~66 framework-specific skills (React, Next.js, FastAPI, Django, ...) that auto-activate when their context matches.
- `claude-mem` — persistent memory across sessions.
- `agent-browser` — browser automation tasks.

### Diagnostic — if a skill isn't firing when expected

1. Run `/plugin` — does it show `[ON]`?
2. Installed but not loaded? Run `/reload-plugins`.
3. Absent? Re-run AI Sherpa setup; check `[ACTION REQUIRED]` at the end.
