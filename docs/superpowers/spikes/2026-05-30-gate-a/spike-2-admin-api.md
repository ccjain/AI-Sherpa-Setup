# Spike 2 — Anthropic Admin API schema confirmation

**Duration:** 3 working days.
**Owner:** TBA (someone with org-admin credentials on the Anthropic console).
**Goal:** Confirm the Anthropic Admin API delivers the org-level acceptance / sessions / cost / LOC-accepted metrics the previous Phase 2a plan assumed, with the actual schema documented and rate-limits understood.

This spike retires the single largest hand-wave in the previous program plan ("the Admin API will give us those metrics") and decides whether the org-level metrics tier needs *any* custom build or is one API call.

## Prerequisites

- Anthropic Admin API credentials (org-admin role). If we don't have these, step 1 stops the spike.
- An Anthropic console account with visibility into the central team's actual Claude Code usage (so step 4's reasonableness check has signal).
- Familiarity with the archived `2026-05-29-phase2a-design.md` §7.1 (Admin API consumer assumptions) and §16.1 (admitted-unconfirmed schema).

## Steps

1. **(½ day)** Obtain Admin API credentials. Document the auth flow (token type, scope, rotation cadence, who else has access).
2. **(½ day)** Call every Admin API endpoint that touches per-user, per-session, per-org metrics. Capture the actual response schema as JSON Schema files in `spike-2-schemas/`.
3. **(1 day)** Build a coverage matrix: rows = metrics the previous Phase 2a plan assumed (acceptance rate per developer, sessions per developer per day, daily cost, lines of code accepted, PRs assisted), columns = `assumed schema`, `actual schema`, `match / mismatch / absent`.
4. **(½ day)** Spot-check 5 central-team developers: does the Admin API report match what they remember of their last week's usage? Look for clearly-wrong numbers — these are the most informative.
5. **(½ day)** Document rate limits empirically. Find the documented limit; verify by hitting it (in a fork test, not against production budgets); document recovery behavior (429 backoff?).

## Exit criteria

A 1-page coverage matrix at `docs/superpowers/spikes/2026-05-30-gate-a/spike-2-results.md` with:

- The matrix.
- A one-line verdict per metric: covered / partial / absent / mismatch.
- Confirmed auth + token scope notes (without the token itself).
- A rate-limit summary: requests/window, retry behavior, daily cost ceiling.
- A list of metrics we wanted but the API does not provide — feeds the decision on whether Langfuse-derived metrics need to fill the gap.

## Kill criterion

If neither acceptance-rate nor sessions-per-developer is available from the Admin API in any form, the v2 brief's claim that "Phase 1.5 was eliminated by Admin API coverage" no longer holds and the Phase 2 scope expands. Escalate before committing the row to the decision matrix.

## Output (Gate A decision-matrix row)

| Spike | Outcome (one sentence) | Confidence | Affects | Decision |
|---|---|---|---|---|
| 2 — Admin API | *e.g. "Admin API delivers acceptance rate + sessions + cost; LOC accepted is absent."* | high / medium / low | Org-level metrics tier | adopt as-is / wrap with normalizer / abandon and use Langfuse-derived metrics |

## Cost note

Be conservative with API calls. Use a fork or test workspace where possible. Do not enable Admin API polling on production org credentials during this spike — the puller is a Gate E artifact, not a Gate A one.
