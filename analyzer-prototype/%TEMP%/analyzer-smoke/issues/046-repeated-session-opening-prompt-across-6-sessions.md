# [add-rule] Repeated session-opening prompt across 6 sessions

**Scenario:** scenario-5 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** high

## Suggested change

**6 sessions** open with a near-identical prompt opening. This is a strong signal that the content belongs in a CLAUDE.md rule or a skill's `description:` instead of being re-typed each session.

**Sample opening (cluster centroid):**

```
Help me bring up a new STM32H7 board using Zephyr
```

**Suggested change:** review the sample sessions, distill the recurring context into a one-paragraph rule, and add it to the appropriate `domains/<X>/CLAUDE.md` or `core/CLAUDE.md`.

## Sample sessions

- `tests\fixtures\minimal-session.jsonl`
- `tests\fixtures\repeated-priming\session.jsonl`
- `tests\fixtures\repeated-priming\session.jsonl`
- `tests\fixtures\repeated-priming\session.jsonl`
- `tests\fixtures\repeated-priming\session.jsonl`
