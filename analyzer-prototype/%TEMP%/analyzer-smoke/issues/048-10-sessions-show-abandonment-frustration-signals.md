# [add-rule] 10 sessions show abandonment / frustration signals

**Scenario:** scenario-8 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** high

## Suggested change

**10 sessions** ended in `/clear` / `/restart` loops or stopped mid-task without an assistant response. This is a signal that a recurring task pattern is not well covered by current rules or skills.

**Suggested change:** sample the abandoned sessions to identify the common task pattern, then add a rule or skill covering it.

## Sample sessions

- `tests\fixtures\abandonment\session.jsonl`
- `tests\fixtures\skill-roi\session.jsonl`
- `tests\fixtures\repeated-priming\session.jsonl`
