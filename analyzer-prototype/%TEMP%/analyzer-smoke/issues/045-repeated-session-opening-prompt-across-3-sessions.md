# [add-rule] Repeated session-opening prompt across 3 sessions

**Scenario:** scenario-5 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** medium

## Suggested change

**3 sessions** open with a near-identical prompt opening. This is a strong signal that the content belongs in a CLAUDE.md rule or a skill's `description:` instead of being re-typed each session.

**Sample opening (cluster centroid):**

```
do a thing
```

**Suggested change:** review the sample sessions, distill the recurring context into a one-paragraph rule, and add it to the appropriate `domains/<X>/CLAUDE.md` or `core/CLAUDE.md`.

## Sample sessions

- `tests\fixtures\skill-roi\session.jsonl`
- `tests\fixtures\skill-roi\session.jsonl`
- `tests\fixtures\skill-roi\session.jsonl`
