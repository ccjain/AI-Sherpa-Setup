# AI Sherpa Feedback & Learning Program — Requirements Summary (v2)

**Date:** 2026-05-30
**Audience:** AI Sherpa team, engineering management, central platform team, InfoSec, legal, works-council reps where applicable
**Status:** Stakeholder-facing digest of the v2 program brief at `docs/superpowers/2026-05-30-program-v2.md`. Supersedes the archived 2026-05-29 summary (`archive/2026-05-30-pre-v2/2026-05-29-program-requirements-summary.md`), which overcommitted relative to what the underlying specs deliver.

---

## 1. Executive summary

AI Sherpa is the company's pre-configured Claude Code environment, deployed to ~150 developers across 10+ domains (embedded, web, data, devops, marketing, sales, finance, etc.). It ships rules (`CLAUDE.md` per domain), plugins, skills, and a setup pipeline. The rules need to keep improving as the team learns what works and what doesn't.

This program adds a **closed-loop feedback and learning system** so AI Sherpa improves continuously:

- Developers can report problems with one keystroke (`/ai-sherpa-feedback`).
- The system observes Claude sessions (after opt-in) and detects patterns the manual channel can't see — silent failures, repeated corrections, rules that should have fired but didn't.
- The central team triages both channels through a single GitHub workflow and ships weekly improvements.
- Every developer receives updates via a brief release email and a `setup --update` command.

The program is intentionally **adoption-first**: ~80% of the underlying plumbing (collector, transport, storage, dashboards) is open-source software (OpenTelemetry Collector, Langfuse, GitHub-native release tooling). The genuinely-novel work is a narrow **Scorer Registry** that measures rule effectiveness — the one capability the AI-coding-tool OSS ecosystem does not currently ship.

**Status today:** Phase 0.5 prototype ran against one engineer's local Claude session corpus (12 candidate findings produced). The detector model is computable; thresholds are not yet calibrated. Everything else is designed and gated on the spike outcomes described in §7.

---

## 2. The problem

Three observations drive the program:

1. **AI Sherpa rules are static, but the work isn't.** Domain rules need to evolve as the team learns. Today there's no systematic way to capture that learning and feed it back into the rules.
2. **Engineers don't notice when Claude is wrong.** Our developers are domain experts (firmware, web, finance) but not AI-native. They accept plausible-looking Claude suggestions and move on. Most "Claude got it wrong" moments are silent — not surfaced, not reported, not learned from.
3. **A single manual feedback channel can't see everything.** Manual reports surface the obvious failures (estimated 5–10/week at most across 150 devs). The silent failures — same correction repeated across sessions, missing context-priming, rules that should have fired but didn't — only surface from telemetry analysis. Both channels are needed.

---

## 3. Who this is for

| Stakeholder | What they get | What they commit |
|---|---|---|
| **Individual developers (~150)** | One-keystroke feedback (`/ai-sherpa-feedback`); local session analyzer they can run on their own data with no opt-in; weekly auto-updates | Honest signal when something is wrong |
| **Central AI Sherpa team (3–5)** | Single GitHub triage queue; weekly release cadence; managed analyzer dashboards | Documented runbooks; 5-day triage SLO |
| **AI Sherpa repo on-call rotation** | Defined paging contact, escalation path, runbooks | Respond to release / ingest incidents within 1 business day; postmortem on every P0 |
| **Domain leads** | Auto-routed Issues for their domain via labels | Triage participation once per week |
| **Engineering management** | Quarterly KPI digest from analyzer dashboards | Budget approval for adopted SaaS/infra |
| **InfoSec** | Bounded data model, documented retention via ClickHouse TTL, mTLS-authenticated ingest | Quarterly review |
| **Legal** | Privacy disclosure, consent posture, right-to-delete and right-to-access endpoints | Sign-off on consent flow before any fleet telemetry starts |
| **Works council / employee reps** (jurisdictions that require it) | Pre-rollout briefing on telemetry collection | Co-determination sign-off before fleet telemetry starts |
| **Anthropic** *(dependency, not stakeholder)* | — | Admin API + Claude Code OTel + claude-code-sdk; we document graceful-degrade behavior |

---

## 4. Use cases

### Core flows (what most stakeholders see)

**UC1 — Developer reports a Claude mistake.** Developer types `/ai-sherpa-feedback`. The skill auto-collects environment context (AI Sherpa version, OS, active plugins, domain) and captures the current session ID. Asks four short questions (what did you ask, what did Claude do, what should it have done, which rule was violated if known). Developer reviews the assembled Issue body and confirms. A labeled, structured GitHub Issue lands in the AI Sherpa repo within ~45 seconds.

**UC2 — System detects a silent failure pattern.** After Gate E (see §7), the Scorer Registry runs nightly over the fleet's telemetry and detects clusters — e.g. "self-admitted errors elevated across 6 embedded developers in sessions involving ISR-related context." If confidence is high enough, a candidate-change Issue is auto-filed into the same triage queue as manual feedback, tagged `source/telemetry` and carrying a `session_ref` link to the source traces.

**UC3 — Central team triages and ships.** Friday triage meeting: each Issue is approved, rejected, or marked duplicate. Approved Issues become PRs with `release-note` labels. Monday morning, the weekly release Action tags `v2026.MM.DD`, generates grouped release notes via GitHub-native tooling, and updates the Releases Atom feed.

**UC4 — Developer receives the update.** The `ai-sherpa-announce` Google Group is subscribed to the GitHub Releases Atom feed. Developer reads the Monday email summarizing the new release, runs `setup --update` (or `--update --pin=<tag>` to stay on an older version). New rules are active in the next Claude session.

### Operational flows (often missed in the original summary)

**UC5 — A release breaks something and we yank it.** On-call runs `gh release delete <bad-tag>` with rationale; publishes a `<bad-tag>-rollback-1` release pointing `rollback_to` at the prior good tag; developers running `setup --update` are restored. Postmortem follows.

**UC6 — A developer revokes consent.** One config flag stops uploads on their laptop; one CLI invocation (`ai-sherpa wipe-me`) triggers server-side deletion of every trace tied to their machine ID.

**UC7 — A developer exercises right-to-access.** `ai-sherpa what-do-you-have-on-me` returns a JSON snapshot of every trace, finding, and Issue tied to them. (Regulatory requirement in several jurisdictions; not optional.)

**UC8 — On-prem server is down for 3 days.** Laptop OTel Collectors buffer locally via the `file_storage` extension; uploads resume on reconnect. The runbook documents the RPO/RTO and which week-1 ingest can be considered lost if the gap exceeds the buffer.

---

## 5. Functional requirements

Every requirement here is matched to a specific commitment in `2026-05-30-program-v2.md`. Items the previous summary listed but v2 does not deliver are not repeated here.

### 5.1 Feedback intake (Phase 1)

- **FR-1** A developer can file structured feedback from inside Claude Code with one slash command (`/ai-sherpa-feedback`).
- **FR-2** The intake auto-collects environment context per `schemas/feedback_issue.schema.json` (`environment.*` fields).
- **FR-3** The developer reviews and approves the assembled Issue body before submission. The skill never auto-submits.
- **FR-4** A fallback path exists for non-Claude-Code submission (GitHub Issue form rendering the same schema).
- **FR-5** Every feedback Issue carries a `session_ref` field (the triage-pivot contract — v2 §3.3). Manual-source Issues include at minimum the session ID; auto-filed Issues include the trace URL.

### 5.2 Triage and release (Phase 1)

- **FR-6** Both manual and auto-detected Issues land in the same GitHub triage queue, distinguished only by `source/manual` vs `source/telemetry` labels per `schemas/label_taxonomy.yml`.
- **FR-7** The system supports the label namespaces in `schemas/label_taxonomy.yml`: `source/*`, `domain/*`, `type/*`, `severity/*`, `confidence/*`, `status/*`. Only the triage workflow may set `status/*`.
- **FR-8** A weekly cron-scheduled GitHub Action discovers merged PRs with the `release-note` label and creates a CalVer-tagged GitHub Release using the native `.github/release.yml` category grouping. No custom release-notes generator is built.
- **FR-9** Every release writes a manifest conforming to `schemas/release_manifest.schema.json`.
- **FR-10** Notification flows through the GitHub Releases Atom feed subscribed to the `ai-sherpa-announce` Google Group. No bespoke mailer is built.
- **FR-11** `setup --update` supports `--pin=<tag>` for explicit version selection and respects `rollback_to` in the release manifest.

### 5.3 Telemetry collection (Gate E, not yet committed)

The following requirements are scoped at v2 Gate E and contingent on Gate A spike outcomes:

- **FR-12** Per-laptop collection uses the OpenTelemetry Collector contrib distribution (MSI installer). Source: Anthropic's native Claude Code OTel export and/or filelog tailing of session JSONLs (decided by Spike 1).
- **FR-13** Projects containing `NDA.md`, `CONFIDENTIAL.md`, or `.ai-sherpa-noupload` are excluded at the producer side (OTTL filter).
- **FR-14** Ingest is authenticated via mTLS + bearer token. Identity is cryptographically asserted, not header-based.
- **FR-15** Sessions are retained 7 days (ClickHouse TTL). Derived findings persist longer.
- **FR-16** A developer can flip a config flag to stop their machine uploading; takes effect within one sweep.

### 5.4 Detection (Gate E, not yet committed)

- **FR-17** The Scorer Registry contains N rule-effectiveness Scorers, where N is derived from Phase 1 evidence at Gate D — not pre-committed to 14 detectors as in the archived plan.
- **FR-18** Each Scorer ships with: golden corpus (20–50 hand-labeled fixtures), property tests, nightly calibration, 14-day shadow mode before eligibility to auto-file, adversarial test set, and PII fixture scan in CI (v2 §5.7).
- **FR-19** Auto-filing requires: confidence ≥ `auto_file_min_confidence` (default high); contributing developers ≥ `auto_file_min_developers` (default 2); fingerprint not previously filed (deterministic dedup).
- **FR-20** Findings that don't auto-file are surfaced on a Langfuse dashboard for human review.

---

## 6. Non-functional requirements

Every NFR is matched to a v2 commitment. The architect review surfaced several gaps in the original summary; those are added here.

| ID | Category | Requirement |
|---|---|---|
| NFR-1 | Scale | Support ~150 developers × ~10 sessions/day at steady state |
| NFR-2 | Storage | 7-day rolling raw sessions (~7.5 GB hot tier in ClickHouse); derived findings persist on a separate table with no TTL |
| NFR-3 | Cost | Self-host path: $110–250/mo + ops time. Managed Langfuse Cloud: ~$2,600/mo (v2 §5.8 has full decomposition) |
| NFR-4 | Privacy | NDA-flagged projects never leave the laptop. PII sanitization is a tested component, not a regex pass — adversarial corpus runs in CI |
| NFR-5 | Network | Intranet only in v1; mTLS not "intranet trust" as a security control |
| NFR-6 | Reliability | Collector buffers via `file_storage` extension; analyzer continues if one Scorer throws (logged + dashboard-surfaced) |
| NFR-7 | Auth | mTLS + bearer-token; no plaintext identity headers. Token rotation cadence documented |
| NFR-8 | Audit | Ingest + LLM calls logged to ClickHouse; `/metrics` endpoint exposes ingest rate, detector latency, auto-file counts, triage backlog age |
| NFR-9 | Recoverability | All indexes rebuildable from raw JSONL via documented procedure that has been *tested* on a fork before declaration of NFR-9 met |
| NFR-10 | Config | Every threshold, retention window, schedule, and gate is configurable via versioned config — no recompile needed |
| NFR-11 | Cadence | Weekly release rhythm; triage on Fridays; ship on Mondays |
| NFR-12 | Triage SLO | Manual feedback Issues triaged within 5 business days at the 95th percentile. Backlog age is a dashboard metric |
| NFR-13 | Release reliability | Release Action success rate ≥ 95% over rolling 8-week window |
| NFR-14 | Right-to-access | Per-developer endpoint returns all data tied to their machine ID + Claude session IDs in JSON |
| NFR-15 | Right-to-delete | One CLI invocation triggers server-side deletion; completion within 24 hours |

---

## 7. Program shape — gates, not phases

The program proceeds as a sequence of **gates** (conditional transitions), not phases (time-boxed deliverables). Every gate has explicit kill criteria. See v2 §4 for full detail.

| Gate | Timing | Purpose | Status |
|---|---|---|---|
| **A — Spikes** | Week 0–1 | Three parallel investigations: Anthropic OTel coverage, Admin API schema, infra capability. Output: 1-page decision matrix | Playbooks ready at `docs/superpowers/spikes/2026-05-30-gate-a/` |
| **B — Phase 1** | Weeks 2–4 | Manual feedback intake + GitHub-native release pipeline + rollback. Adopts GitHub-native tooling end-to-end | Ready to start after Gate A closes |
| **C — Stabilization** | Weeks 5–8 | Prove central-team triage scales. Phase 2 is NOT scoped in this window | Conditional on Gate B exit |
| **D — Phase 2 scoping** | Week 9 | Re-derive detector list from actual Phase 1 evidence. Commit at least one DX affordance for individual developers | Conditional on Gate C exit |
| **E — Phase 2 build** | Weeks 10–13 | Deploy adopted stack (Langfuse, OTel Collector); ship Scorer Registry with N rules; webhook → auto-file | Conditional on Gate D scope |

There is no Phase 2b for LLM polish. Langfuse ships LLM-as-judge eval primitives; "polish" becomes one Scorer in the registry if needed.

---

## 8. Currently-committed deliverables (Phase 1 only)

These ship between week 2 and week 4. Everything beyond Phase 1 is conditional on later gates.

### Phase 1 ships
- `/ai-sherpa-feedback` slash command + `submit-feedback.{ps1,sh}` helpers (ABI documented at `schemas/helper_abi.md`)
- `.github/ISSUE_TEMPLATE/feedback.yml` and `.github/release.yml` (GitHub-native)
- Weekly cron release Action (~50 lines, no jq / pandoc / Apps Script)
- `VERSION` file + `--update` and `--pin` improvements in `setup.bat` / `setup.sh` / `setup.ps1`
- `schemas/` directory pinned on day 1 (CI-validated)
- Atom-feed-to-Google-Group subscription configured (Workspace-native, no custom mailer)
- Rollback runbook (tested in dry-run on a fork before declaring Phase 1 done)
- On-call rotation documented with named assignees
- `docs/feedback-guide.md` + privacy disclosure
- `tools/local-session-analyzer/` — the Phase 0.5 prototype packaged as a standalone CLI any developer can run on their own data with no opt-in

### What is explicitly out of scope for Phase 1
- On-prem server, telemetry collector, fleet analyzer (deferred to Gate E)
- ChromaDB / FAISS / bespoke vector store (replaced by Langfuse + ClickHouse adoption)
- Apps Script mailer (replaced by Atom feed adoption)
- Custom release-notes generator, custom pandoc pipeline (replaced by `.github/release.yml`)
- 14-detector taxonomy as a monolith (re-derived at Gate D from Phase 1 evidence)
- LLM polish as a separate phase (folded into the Gate E Scorer registry if needed)

---

## 9. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Release Action bot push to `master` blocked by branch protection | High | Release-only deploy key with explicit bypass; tested on a fork before main repo |
| `setup --update` pulls a bad rule before email arrives | High | `--pin` flag + manifest-based `rollback_to` semantics; refuses to update if VERSION rolled back since last seen |
| Anthropic OTel export doesn't carry enough content for the Scorer Registry | Med | Spike 1 decision point; JSONL fallback path pre-planned |
| Admin API schema doesn't match assumptions | Med | Spike 2; normalizer wraps every field; fall back to Langfuse-derived metrics |
| Langfuse retention is EE-only as a managed policy | Med | InfoSec documentation says "ClickHouse TTL DDL", not "managed policy" |
| Developers opt out en masse | Med | Opt-in rate is a published metric; below 50% at Gate D, the DX affordances become a prerequisite, not a stretch goal |
| On-prem server SPOF | Med | Nightly ClickHouse mirror to second drive; documented + *tested* rebuild procedure |
| Scorer false-positive flood | Med | Gate E kill criterion: > 30% FP → auto-file behind manual approval; webhook circuit-breaker |
| Triage queue overwhelmed by auto-filed Issues | Med | Gate C SLO must hold for 4 consecutive weeks before Gate E unlocks |

---

## 10. The honest caveat: what does each developer actually get back?

The architect review observed that the previous program was "inward-facing infrastructure dressed as a DX initiative." The v2 program reduces but does not eliminate that critique. The Scorer Registry is the right architectural contribution — it fills a real OSS gap — but it is not by itself a developer-experience contribution.

Four affordances make the DX layer real. The first two ship in Phase 1; the last two are sketched and Gate D must commit at least one of them before Gate E ships:

1. **`/ai-sherpa-feedback`** *(Phase 1 — committed)*: one-keystroke structured feedback. Direct value: 45 seconds, not 15 minutes.
2. **`tools/local-session-analyzer`** *(Phase 1 — committed)*: run locally on your own data with no opt-in. Direct value: personal insights without surveillance.
3. **`/ai-sherpa-insights`** *(Gate E or later — sketched)*: surface the developer's own telemetry data. Direct value: analytics about your own work, not just contribution to a fleet metric.
4. **Weekly personal digest** *(Gate E or later — sketched)*: opt-in email with personal metrics + team improvements + credit for rules the developer helped surface.

The pitch we have to be able to make honestly:

> *"Phase 1 gives you a one-keystroke feedback button and a local analyzer. Phase 2 will give you personal insights from your own data once we're confident the system works. We're not asking you to opt into pure surveillance — we're asking you to opt into a loop you also benefit from."*

That sentence belongs verbatim in `docs/feedback-guide.md` and the consent prompt the collector shows on first run. If we can't say it honestly at Gate E, the gate does not open.

---

## 11. Rollout timeline (illustrative — gates govern)

| Time | Activity |
|---|---|
| Week 0 (now) | Team reviews this summary + the v2 brief + the three Gate A spike playbooks |
| Week 1 | Gate A spikes run in parallel; close-out meeting produces the decision matrix |
| Weeks 2–4 | Phase 1 implementation (Gate B); pilot to central team first |
| Weeks 5–8 | Phase 1 stabilization (Gate C); 5-day triage SLO must hold for 4 consecutive weeks |
| Week 9 | Gate D scoping meeting; Phase 2 spec produced; ≥1 DX affordance committed |
| Weeks 10–13 | Phase 2 build (Gate E) if Gate C and Gate A signals were positive |
| Week 14+ | Phase 2 stabilization, opt-in ramp |

These are estimates; the actual cadence depends on team availability and what the gates reveal. **No date above is a commitment**; each gate's transition criteria are the commitment.

---

## 12. Where to find the detailed specs

| Doc | Purpose |
|---|---|
| `docs/superpowers/2026-05-30-program-v2.md` | The authoritative program brief — start here |
| `docs/superpowers/spikes/2026-05-30-gate-a/` | The three Gate A spike playbooks + decision matrix template |
| `schemas/` | Cross-phase contracts: feedback Issue body, release manifest, label taxonomy, helper ABI |
| `docs/superpowers/specs/2026-05-29-analyzer-prototype-design.md` | Phase 0.5 prototype design (the shipped work) |
| `docs/superpowers/research/` | OSS landscape research (currently the 2026-05-29 narrow comparison; expansion pending) |
| `docs/superpowers/archive/2026-05-30-pre-v2/` | Superseded v1 program docs — reference, not authoritative |
| `analyzer-prototype/` (to be renamed `tools/local-session-analyzer/` per v2 §5.9) | The Phase 0.5 prototype code |

---

## 13. What we want from this review

Five questions for stakeholders before final commit:

1. **Anything missing from the requirements or use cases** as written here?
2. **Anything that should be descoped** further — e.g. is even Phase 1 overcommitted given current team capacity?
3. **Stakeholders we haven't named** in §3 — especially anyone with consent or governance authority we should have engaged before drafting?
4. **Budget posture for §5.8** — do we run self-hosted (~$110–250/mo + ops time) or accept managed Langfuse Cloud (~$2,600/mo, fewer ops)?
5. **Concerns about privacy, cost, scale, or operational burden** we should address before Gate A starts?

Reply on this doc or raise issues directly on the v2 brief.
