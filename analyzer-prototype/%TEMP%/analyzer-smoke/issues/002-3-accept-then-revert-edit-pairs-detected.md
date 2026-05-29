# [refine-rule] 3 accept-then-revert edit pairs detected

**Scenario:** scenario-10 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** medium

## Suggested change

**3 cases** where the same file was edited again within 60 seconds of the previous edit. This pattern indicates Claude was close but not quite right, and the user finished the job manually.

**Suggested change:** sample these sessions; if there's a recurring pattern in what Claude got almost-right, refine the relevant rule.

## Sample sessions

- `tests\fixtures\accept-revert\session.jsonl`
