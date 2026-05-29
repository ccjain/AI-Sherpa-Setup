# [setup-fix] Configured domain `embedded` but file extensions suggest `data`

**Scenario:** scenario-3 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** medium

## Suggested change

The current AI Sherpa install is configured for domain `embedded`, but the files touched across the analyzed sessions match the `data` domain.

**Suggested change:** re-run `setup --reconfigure` and pick `data`, or update the onboarding doc if this is intentional mixed work.

## Sample sessions

- `tests\fixtures\accept-revert\session.jsonl`
- `tests\fixtures\mixed\session.jsonl`
