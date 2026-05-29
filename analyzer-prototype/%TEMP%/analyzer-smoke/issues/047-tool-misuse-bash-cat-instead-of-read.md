# [add-rule] Tool misuse: Bash + cat instead of Read

**Scenario:** scenario-7 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** medium

## Suggested change

Across the analyzed corpus, `Bash cat` was invoked **6 times**.

Each call could have been handled by the `Read` tool directly, avoiding a shell escape and the associated permission prompt.

**Suggested change:** add a rule to `core/CLAUDE.md` discouraging `Bash cat` when the equivalent first-class tool exists.

## Sample sessions

- `tests\fixtures\minimal-session.jsonl`
- `tests\fixtures\tool-misuse\session.jsonl`
