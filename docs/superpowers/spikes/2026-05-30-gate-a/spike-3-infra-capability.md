# Spike 3 — Infrastructure capability

**Duration:** 1 working day.
**Owner:** TBA (ops / infrastructure lead).
**Goal:** Decide where to host the Gate E server stack (Langfuse + ClickHouse + OTel gateway). The options are: (a) Docker on the existing Windows on-prem server, (b) a new Linux VM beside it, (c) managed Langfuse Cloud (~$2.5k/mo).

Every credible self-hosted option requires Docker. The existing server is Windows-only today. This spike answers a single ops question that gates the server-side architecture decision.

## Prerequisites

- Conversation with whoever owns the existing on-prem Windows server (admin rights, hardware specs, change-management posture).
- v2 brief §5.8 (cost envelope) and §1 Q4 (budget posture) read.

## Steps

1. **(1 hour)** Confirm the existing server's specs: CPU cores, RAM, disk, OS version, virtualization capability (Hyper-V enabled? Nested virt?).
2. **(2 hours)** Determine the constraint set: is Docker Desktop allowed by org policy? Is WSL2 allowed? Is Hyper-V enabled and can it host a Linux guest? Is there a corporate-image Linux template we'd be required to use?
3. **(2 hours)** Estimate cost + lead time per option:
   - Docker Desktop on existing Windows host: license cost (Docker Desktop is paid for orgs > 250 employees), CPU/RAM ceiling, change-management lead time.
   - New Linux VM beside it (Hyper-V or hypervisor): provisioning time, ongoing patching ownership, network/firewall changes needed.
   - Managed Langfuse Cloud: ~$2.5k/mo + procurement + data-locality review.
4. **(2 hours)** Sanity-check ClickHouse footprint vs available headroom: ~7.5 GB hot tier at 150 devs × 10 sessions/day × 7-day rolling, plus 4–6 GB RAM for Langfuse worker + web + Postgres + Redis. Will the chosen target host this comfortably with 50% headroom?
5. **(1 hour)** Document the recommendation.

## Exit criteria

A 1-page recommendation at `docs/superpowers/spikes/2026-05-30-gate-a/spike-3-results.md` with:

- The three options scored on: cost, lead time, ongoing ops burden, change-management risk.
- A named recommendation with rationale.
- A list of dependencies the recommendation introduces (e.g., "need works-council review for new Linux VM", "need procurement for managed plan", "need Docker Desktop license").
- An estimated **earliest date** the chosen platform could host the Gate E stack — feeds the Gate D scoping.

## Kill criterion

If all three options have lead times > 6 weeks, the program owner must decide whether to delay Gate E or accept managed Langfuse Cloud as a 12-month bridge while the longer-term platform is sorted. Escalate before committing the row to the decision matrix.

## Output (Gate A decision-matrix row)

| Spike | Outcome (one sentence) | Confidence | Affects | Decision |
|---|---|---|---|---|
| 3 — Infra | *e.g. "Hyper-V on existing host can run a Linux guest; 2-week provisioning lead time; ops will own patching."* | n/a | Server hosting model | host on Windows + Docker / stand up Linux VM / accept managed Langfuse Cloud |
