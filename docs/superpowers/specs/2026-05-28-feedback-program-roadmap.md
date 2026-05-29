# AI Sherpa — Feedback & Learning Program Roadmap

**Date:** 2026-05-28
**Status:** Roadmap (program-level direction across multiple specs)
**Supersedes:** the single-spec framing in `2026-05-28-feedback-release-pipeline-design.md`. That doc is now Phase 1 of this program.

This roadmap captures the strategic direction agreed across the brainstorming
session: why we have two feedback channels, how they are staged, what silent
failures each channel catches, how the monorepo stays stable while the
bigger pieces are built, and which decisions are locked vs. open.

---

## 1. Purpose

AI Sherpa is deployed to 150+ developers across 10+ teams. The program's job
is to **continuously improve the rules, skills, and plugins each domain ships
with**, by capturing what works and what doesn't in real Claude sessions.

We have two reasons to do this and one reason it's hard:

- **Reason A — Reduce engineer frustration.** When AI Sherpa rules misfire,
  the engineer fights Claude every day. We want to detect that and fix it.
- **Reason B — Raise leverage.** When one engineer solves a domain problem
  brilliantly, the next engineer should benefit without re-deriving it.
- **The hard part.** Our engineers are domain experts but not AI-native. They
  don't reliably notice when Claude is wrong, and they won't reliably report
  what they don't notice.

That third bullet is the load-bearing observation. It's why a single
manual-feedback channel is not enough.

---

## 2. The two-channel feedback model

We collect feedback via two channels with different strengths:

| Channel | Catches | Misses | Privacy posture |
|---|---|---|---|
| **Manual** — `/ai-sherpa-feedback` | Explicit, articulable failures (engineer noticed and can describe) | Anything the engineer didn't notice or didn't bother to report | None — engineer chooses what to send |
| **Telemetry** — session collection + agentic analysis | Silent, habituated, cross-engineer patterns | Cases not represented in any session | Significant — needs legal/InfoSec review for full transcripts |

**Convergence point.** Both channels produce GitHub Issues with `feedback` +
`domain/*` labels. From there, the triage → PR → weekly release → email
pipeline (designed in the Phase 1 spec) handles both uniformly. We build the
triage pipeline once and feed it from two sources.

---

## 3. Silent-failure classes (what only telemetry catches)

Manual feedback is bounded by what an engineer notices. Telemetry sees the
session as it happened. The table below enumerates the silent-failure
scenarios we need to detect and what data each requires.

**Data column legend:**
- **M** = metadata only (no prompt/response text) — Phase 1.5, no legal hurdle
- **T** = full transcripts — Phase 2, requires legal/InfoSec sign-off

| # | Scenario | Detection method | Data | Candidate-change bucket (see §12.2) |
|---|---|---|---|---|
| 1 | **Skill should have fired but didn't (per-session diagnosis)** | Cross-reference session topic vs. installed skills' `description:` fields. Embeddings or keyword match. Aggregate version of this signal (low fire-rate per skill) is captured by scenario 11 with metadata alone. | T | **#3** update skill `description:` |
| 2 | **Same correction repeated across sessions** | Diff what engineer edits *after* accepting AI output. Hash the (suggestion → edit) deltas; cluster repeats. | T | **#1** add rule |
| 3 | **Domain mismatch** | File extensions touched in sessions vs. configured AI Sherpa domain. | M | **#5** setup fix or **#6** onboarding doc |
| 4 | **Stale memory contradicting current code** | Compare `~/.claude/memory/*.md` facts against current repo state. | M + T | **#1** add rule about memory hygiene |
| 5 | **Repeated context-priming** | First N tokens of prompts hashed/embedded; flag boilerplate that recurs per-engineer and across engineers (the cross-engineer convergence is the highest-value signal of the whole program). | T | **#1** add rule — the strongest single source of candidate rules |
| 6 | **Rule existed but didn't trigger** | For each CLAUDE.md rule, define a content signature; scan sessions where it appears but the rule warning didn't. | T | **#2** refine existing rule |
| 7 | **Tool misuse / inefficient patterns** | `Bash + cat` instead of Read; `Bash + grep` instead of Grep; permission-prompt rate. | M | **#1** add rule |
| 8 | **Sessions ending in frustration / abandonment** | Multiple `/clear`, `/restart`, sessions ending mid-task. Structural signal. | M | **#1** rule (likely missing) or **#3** skill |
| 9 | **Inconsistent advice across engineers** | Cluster sessions by intent (embeddings on first prompt); flag divergent first-pass answers. | T | **#2** refine rule (ambiguity in domain) |
| 10 | **High accept-then-revert rate** | Tool suggestion accepted → file edited again within 60s. Effective "yes but actually no". | M | **#1** rule or **#2** refine rule |
| 11 | **Plugin/skill ROI** | For each installed skill: fire rate × accept rate × subsequent-edit rate. | M | **#3** update description or **#4** remove plugin |
| 12 | **Onboarding velocity** | Session-length, tool-counts over time for new hires vs. veterans. | M | **#6** docs or **#5** setup |
| 13 | **Stale install** | `VERSION` per engineer at session start; flag anyone > N releases behind. | M | **#5** setup fix (update discovery) |
| 14 | **Workaround / override patterns** | Engineer repeatedly says "ignore the rule" or "actually just do X". | T | **#2** refine rule (too strict / context-blind) |
| 15 | **Cross-engineer lone-genius patterns** | Cluster similar problems; surface the best solution as a candidate skill. | T | **#1** add rule or **#3** new skill |
| 16 | **Edits without prior Read** | Per session, count Edit/Write where the same file_path had no preceding Read. Anthropic published research found 43.8% as a quality-regression correlate. Phase 2a (lucemia taxonomy). | T | **#1** add rule (the strongest behavioral correlate of quality regression) |
| 17 | **Self-admitted errors per 1K tool calls** | Regex on assistant messages for `"I apologize"`, `"you're right"`, `"my mistake"`, `"let me try"` etc., normalized per 1K tool calls. Phase 2a (lucemia taxonomy). | T | **#2** refine rule |
| 18 | **Low Read:Edit ratio** | Per dev, total Reads / total Edit+Writes. Healthy ≥4.0; degraded ≈2.0 per Anthropic research. Phase 2a (lucemia taxonomy). | M (tool counts only) | **#1** add rule |
| 19 | **User frustration in prompt text** | Regex on user follow-up prompts for frustration markers (`that's wrong`, `no, don't`, `why did you`, `just do`). Complements scenario-8's structural signal. Phase 2a (lucemia taxonomy). | T | **#1** add rule / **#3** skill |

**Seven of fifteen original scenarios are fully detectable with metadata alone**
(scenarios 3, 7, 8, 10, 11, 12, 13), and an eighth (1) is partially detectable
via the aggregate ROI signal in scenario 11. Three of the four lucemia-derived
additions are content-dependent (16, 17, 19); scenario 18 needs only tool-call
counts. Phase 2a covers scenarios 1, 2, 3, 5, 7, 8, 10, 11, 12, 13, 16, 17, 18, 19
(14 of 19). Phase 2b is what unlocks scenarios 4, 6, 14 (which require
semantic judgment over rules and memory).

---

## 4. Rollout (3 + 1 phases)

Updated 2026-05-29: Phase 1.5 has been eliminated. Anthropic's Admin API
(available on Team/Enterprise plans) provides the per-developer structured
metrics that Phase 1.5 would have collected via an on-device metadata
collector. With legal/InfoSec already having approved full-transcript
collection, Phase 2a starts directly from Phase 1 — no separate metadata-only
intermediate step.

| Phase | Duration | What it adds | Privacy hurdle |
|---|---|---|---|
| **0.5 — Analyzer prototype** | ~1 day | Local-data analyzer at `analyzer-prototype/`. 10 detectors over `~/.claude/projects/`. Validates the detector model before any collection infrastructure exists. **Shipped** at commit `efd9fb4`. | None — local data only |
| **1 — Manual feedback** | 2–3 weeks | `/ai-sherpa-feedback` skill, GH Issue form, triage labels + Project board, weekly release Action, Apps Script email to Google Group, `--update` change-summary tail. | None |
| **2a — Multi-developer collection + analyzer** | 4 weeks | On-device collector (full JSONL payload) + FastAPI ingest service + SQLite FTS5 + ChromaDB storage + Anthropic Admin API integration + 14 detectors (Phase 0.5's 10 + lucemia's 4) + auto-filing into Phase 1 triage queue. Two-tier retention (7-day sessions, forever insights). Runs on the existing on-prem Windows server. **Zero ongoing API cost.** | **Approved** — full transcripts already cleared by legal |
| **2b — LLM-assisted polish** | 1 week | One additional step inside Phase 2a's pipeline: for each new finding above a confidence threshold, call Claude API (Haiku) to draft PR-ready rule wording + unified diff + reviewer rationale. Hard cost cap (~$5/week target). Default OFF; opt-in via `Config.llm_enabled=True`. | None additional; same data already approved |

**Why this order:**

- **Phase 0.5 first** (done): proved the detector model fires on real data before
  building any collection plumbing. Outputs informed Phase 2a's design and
  surfaced the OSS landscape that simplified the architecture.
- **Phase 1 next**: ships fastest, produces a labelled ground-truth corpus the
  Phase 2a analyzer cross-references for calibration, and trains the central
  team on the triage rhythm with a small initial inbox.
- **Phase 2a third**: multi-developer collection scales the detection model
  beyond a single dev's corpus. Builds on the same triage queue as Phase 1
  via auto-filing.
- **Phase 2b last**: layers LLM polish on top of Phase 2a's findings. Optional,
  opt-in, cost-capped. Not required for the program to deliver value.

---

## 5. Convergence — one triage queue, two sources

Both channels produce GitHub Issues with consistent labelling so the central
team triages them the same way:

```
Manual feedback             Telemetry insight
  (Phase 1)                  (Phase 2a / 2b)
       │                            │
       │  /ai-sherpa-feedback       │  Analyzer auto-files
       │  → GH Issue                │  → GH Issue
       │  labels: feedback,         │  labels: feedback, source:telemetry,
       │   source:manual,           │   confidence:{high,med,low},
       │   domain/*,                │   type/<bucket>, domain/*,
       │   status/needs-review      │   severity/*, status/needs-review
       │                            │
       └─────────────┬──────────────┘
                     ▼
              Same triage workflow
              (labels, Project board,
              weekly cadence — designed
              in Phase 1 spec)
                     │
                     ▼
              PR with `Closes #N` and
              `release-note` label
                     │
                     ▼
              Weekly release Action →
              GH Release + email to
              ai-sherpa-announce
```

**Auto-filing rules (Phase 2):**

- **High-confidence insights** auto-file directly as Issues with full evidence
  (linked source sessions, occurrence count, severity).
- **Medium-confidence insights** auto-file but with `status/needs-analyst` so
  the central team reviews before triage proper.
- **Low-confidence insights** land in a separate insights queue the analyzer
  team reviews weekly; only promoted to Issues if a human agrees.

This three-tier confidence gate is how we honour the "the analyzer is also AI
and can also be wrong" point — we never let the analyzer flood the triage
queue with unvalidated guesses.

---

## 6. Repository structure — monorepo with three hard zones

The setup repo (Zone 1) stays stable while we build the much bigger telemetry
+ analyzer subsystem. The discipline is enforced by directory layout, CI
filters, and CODEOWNERS — not by good intentions.

```
ai-sherpa/
├── core/, domains/, settings/, templates/   ┐
├── plugins.json                             │
├── setup.bat, setup.sh, setup.ps1           │  ZONE 1 — DEV-FACING
├── skills/                                  │  (cloned by every dev;
│                                            │   setup reads from here only)
│                                            ┘
│
├── client-agent/                            ┐
│   ├── collector/   (session uploader)      │  ZONE 2 — ON-DEV
│   ├── redactor/    (optional scrubber)     │  (installed by setup
│   └── README.md                            │   when --enable-telemetry)
│                                            ┘
│
├── server/                                  ┐
│   ├── ingest/      (FastAPI HTTP service)  │  ZONE 3 — SERVER
│   ├── analyzer/    (Python: rules + local  │  (runs on the existing
│   │                 embeddings; no LLM v1) │   on-prem Windows box;
│   ├── db/          (SQLite schema)         │   no dev touches this)
│   ├── deploy/      (NSSM service install   │
│   │                 + Task Scheduler XML)  │
│   └── README.md                            ┘
│
├── .github/         (workflows, templates — shared)
├── tools/           (release dry-run, mailer source — shared)
└── docs/            (specs, plans, this roadmap)
```

**Three invariants that protect Zone 1:**

1. **`setup.*` never reads from `server/`.** It can install from
   `client-agent/` when opted in. Enforced by a CI check that greps the
   setup scripts.
2. **No top-level dependency manifests for server code.** `server/`'s
   `pyproject.toml` lives inside `server/`. A dev cloning the repo for rules
   sees zero Python deps at root.
3. **Server has its own README and deploy targets.** Anyone running
   `server/deploy/up.sh` is by definition ops, not a dev.

**Protective tooling:**

- **CI path filters** — workflows under `.github/workflows/*.yml` use
  `paths:` so a PR that only changes `server/` doesn't trigger the dev-setup
  release workflow, and `core/` changes don't trigger server CI.
- **`CODEOWNERS`** — different reviewers required for `server/` vs.
  `core/+setup.*`.
- **Setup smoke test** — CI runs `bash setup.sh --dry-run` on Ubuntu/macOS
  and `setup.bat --dry-run` on Windows; asserts the exit code and the
  touched-files list. Catches accidental cross-zone breakage.
- **Feature flags in setup** — Phase 1.5 / 2 features ship behind opt-in
  (`--enable-telemetry`). Partially-built telemetry features can land in
  `master` without affecting devs who don't opt in.
- **Long-lived feature branches** for the analyzer build — periodically
  rebases from master; master stays releasable for `setup --update` at all
  times.

**When we would split into separate repos** (not now, but documented so we
know the triggers):

1. `server/` adopts language/runtime that bloats root tooling (heavy build
   systems, hosted DB migration binaries).
2. We want to open-source or partner-share the rules without exposing the
   analyzer.
3. Access control diverges — contractors should see `core/` but never
   `server/`.

None apply today. Split later via `git filter-repo` if any trigger fires.

---

## 7. Privacy & legal posture

| Item | Posture |
|---|---|
| **Network scope (v1)** | **Intranet only.** Server reachable only from the corporate LAN; not exposed to the public internet. Laptops working off-network queue locally and ship next time on the LAN. |
| **What ships in Phase 1** | Nothing automatic. Engineer manually composes feedback, reviews before submission, files via own `gh` auth. |
| **What ships in Phase 1.5** | Metadata events only — skill fire counts, tool-call sequences, session length, file extensions, domain, AI Sherpa version. No prompt or response text. |
| **What ships in Phase 2** | Full raw session transcripts (prompts, responses, file paths, tool calls). Approved scope; requires legal + InfoSec sign-off before launch. |
| **NDA / confidential projects** | Excluded from all telemetry. Detected via existing pre-flight check + presence of `NDA.md` / `CONFIDENTIAL.md`. Collector hard-skips these sessions. |
| **Transport security (v1)** | Plain HTTP on the corporate LAN is acceptable for v1 (intranet only). Internal TLS optional, recommended for hygiene. Upgrade to public DNS + Let's Encrypt cert when off-network laptops are added (v2). |
| **Auth (v1)** | **None.** Server is intranet-only and only org-internal devs run `setup.bat`. Identity reported via `X-Developer` (Windows username) and `X-Machine-Id` headers, but **not cryptographically asserted** — analysis use only. Upgrade to **per-machine bearer tokens** issued at enrollment when the server is exposed off-network (v2). |
| **At-rest encryption** | Standard Windows BitLocker on the server's storage volume. No application-level encryption in v1. |
| **Access control** | Server-side data accessible only to AI Sherpa team via Windows file ACL on `D:\ai-sherpa\` and the analyzer's service account. |
| **Retention** | Default 12 months for transcripts; 24 months for aggregated insights. Configurable. Right-to-delete on request. |
| **Per-dev consent** | Setup explicitly asks at install time: "Enable telemetry? (You can change this later with `setup --disable-telemetry`)" Default = **off** until legal completes. |
| **Auditability** | Telemetry collector logs every upload locally; engineer can run `setup --telemetry-status` to see what's been sent. Server logs every POST (timestamp, source IP, machine_id, bytes). |

---

## 8. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Legal review for Phase 2 stalls or denies full-transcript collection | Medium | High — caps detection to 8/15 scenarios | Phase 1.5 metadata already catches the most common silent-failure cases; we operate without Phase 2 if needed |
| Analyzer hallucinates patterns; floods triage queue with false positives | Medium | Medium | Three-tier confidence gate (§5). Manual ground-truth corpus from Phase 1 calibrates the analyzer |
| Phase 1.5 metadata reveals real privacy concerns we didn't anticipate (e.g., file paths leak project codenames) | Medium | Medium | Privacy review even for metadata before launch; hashing of identifiers; opt-in by default |
| Telemetry slows down dev machines | Low | Medium | Collector batches uploads, never blocks the Claude session; max CPU/network budgets |
| Setup gets destabilized by server-side PRs | Medium without guardrails, Low with them | High — would break dev experience | CI path filters + CODEOWNERS + setup smoke test (§6) |
| Devs feel surveilled and disable telemetry en masse | Medium | High — kills Phase 2 value | Transparent UX: `setup --telemetry-status` shows exactly what's sent; aggregated, anonymized reports shared back with teams; clear opt-in not opt-out |
| Cost overrun on analyzer LLM calls | Medium | Medium | Cheap-model first-pass (Haiku) triages; only "promising" sessions invoke Sonnet/Opus. Aggressive prompt caching |

---

## 9. Decisions locked (and where they came from)

| Decision | Choice | Source |
|---|---|---|
| Scope of the brainstorm | End-to-end thin slice across intake → triage → release → notify | Section 1 of Phase 1 spec |
| Repo host | Public GitHub, org-owned | Q&A turn |
| Scale | 10+ teams, 150+ developers | Q&A turn |
| Ownership | Central AI Sherpa team approves all | Q&A turn |
| Manual intake UX | In-Claude slash command (primary), GitHub Issue web UI (fallback, same template) | Q&A turn |
| Release cadence | Weekly scheduled + manual dispatch hotfix | Q&A turn |
| Versioning | CalVer (`vYYYY.MM.DD`) | Phase 1 spec §8.2 |
| Email transport | Google Apps Script Web App → Google Group | Q&A turn |
| Telemetry data scope | Phase 1.5 metadata; Phase 2 full transcripts gated on legal | This roadmap §7 |
| Telemetry hosting | Self-hosted on the existing on-prem **standalone Windows** server (no AD assumed) | Q&A turn |
| Network scope (v1) | Intranet only — no public DNS, no off-network laptops | Q&A turn |
| Transport mechanism | **HTTP POST** to a FastAPI service on the on-prem server (not WebSocket, not SMB). Reason: stateless, idempotent, debuggable, future-portable | Q&A turn |
| v1 auth model | **None.** Intranet-only + setup.bat is org-internal-only. Identity from `X-Developer` + `X-Machine-Id` headers, not cryptographically asserted. Bearer tokens added when going off-network (v2) | Q&A turn |
| Analyzer approach (v1) | **No Claude API, no local LLM.** Rule-based heuristics + local sentence-transformer embeddings + clustering. Zero ongoing API cost | Q&A turn |
| Analyzer upgrade path | Add a final LLM "explain" step later — Claude API (cheap, scoped to top-N candidates) or a locally-run open model. Drops in as one additional step | Q&A turn |
| Convergence model | Both channels feed the same triage queue with `source:*` labels | This roadmap §5 |
| Repo structure | Monorepo with three hard zones | This roadmap §6 |
| Rollout order | Phase 1 first; Phase 1.5 in parallel; Phase 2a (no-LLM) gated on legal; Phase 2b (LLM-assisted) gated on budget | This roadmap §4 |

---

## 10. Open questions deferred to implementer or future spec

These do not change architecture; they are knobs.

1. Exact cron time/timezone for the weekly release Action.
2. Which Workspace account deploys the mailer Apps Script.
3. Whether to restrict feedback Issue creation to org members (recommended yes).
4. Internal DNS name for the on-prem server (e.g., `ai-sherpa-srv.local`) vs. plain IP.
5. Python version on the server (3.11 recommended).
6. Whether to keep the v1 "no auth" stance through Phase 1.5 OR add a shared-secret token earlier (only if insider abuse is observed).
7. Whether the analyzer runs nightly, weekly, or on-demand.
8. Whether to ship a small admin UI in Phase 2a or read insights from CLI + SQL only.
9. Exact retention windows once legal weighs in.
10. Whether anonymized aggregate reports are shared back with teams ("your team's top 3 friction points this month").

---

## 11. Continuous session collection mechanism (v1 — intranet-only, Windows-first)

> **Updated 2026-05-29:** Phase 1.5 has been eliminated; this section's
> mechanism is now owned by Phase 2a, which ships full-JSONL payload (not
> metadata-only) and adds the SQLite FTS5 + ChromaDB indexing layer at
> ingest time (see `2026-05-29-phase2a-design.md` §6 and §8). The Anthropic
> Admin API integration originally sketched for Phase 1.5 is also folded
> into Phase 2a (see Phase 2a spec §7). The architectural diagram and
> mechanism below remain accurate as the foundation; refer to the Phase 2a
> spec for the layered additions.

This section captures the concrete v1 mechanism the program uses to ship
session data from each dev's laptop to the on-prem server.

### 11.1 Architecture at a glance

End-to-end, from a developer's keystrokes inside Claude Code to a GitHub
Issue filed for the central team to triage:

```
  ON DEV LAPTOPS (Windows × ~150)                  ON-PREM WINDOWS SERVER (always on)

  ┌─ Claude Code session ─────────┐                ┌─ FastAPI ingest service ──────┐
  │ writes JSONL transcript to    │                │ NSSM-managed Windows service  │
  │ %USERPROFILE%\.claude\        │                │ binds 0.0.0.0:8080 on LAN     │
  │  projects\<hash>\<id>.jsonl   │                │                               │
  └───────────────┬───────────────┘                │ POST /v1/sessions/{id}        │
                  │                                │   headers: X-Machine-Id,      │
                  ▼                                │            X-Developer        │
  ┌─ SessionEnd hook (95% case) ──┐  HTTP POST     │   body:    JSONL              │
  │ runs upload.ps1 -Mode Hook    ├────────────────▶ → SHA-256 dedup check         │
  └───────────────┬───────────────┘  (intranet     │ → write to D:\ai-sherpa\…     │
                  │                  only)         │ → log to ingest.log           │
                  │ + hourly Task Scheduler sweep                                  │
                  │   (5% case: hook missed,       └──────────────┬────────────────┘
                  │    laptop was offline, etc.)                  │
                  ▼                                                ▼
  ┌─ upload.ps1 ──────────────────┐               ┌─ Storage on the server ───────┐
  │ 1. NDA gate (skip if          │               │ D:\ai-sherpa\                 │
  │    NDA.md / CONFIDENTIAL.md)  │               │  ├─ sessions\<dev>\<machine>\ │
  │ 2. dedup vs local uploads.db  │               │  │   └─ <session>.jsonl       │
  │ 3. transform payload          │               │  ├─ events.sqlite             │
  │    (1.5 = metadata only,      │               │  ├─ insights.sqlite           │
  │     2  = full JSONL)          │               │  └─ logs\ingest.log           │
  │ 4. POST to server             │               └──────────────┬────────────────┘
  │ 5. mark uploaded / pending    │                              │ nightly Windows
  │    in uploads.db              │                              │ scheduled task
  └───────────────────────────────┘                              ▼
                                                  ┌─ Analyzer (Python, same box) ─┐
  (repeat × 150 laptops)                          │ - parse JSONL → events        │
                                                  │ - run §3 scenario detections  │
                                                  │   (SQL + local embeddings,    │
                                                  │    no LLM in v1)              │
                                                  │ - render candidate-change     │
                                                  │   Issue body per template     │
                                                  └──────────────┬────────────────┘
                                                                 │
                                                                 ▼ gh issue create
                                                  ┌─ GitHub (AI Sherpa repo) ─────┐
                                                  │ Issues filed into the same    │
                                                  │ triage queue as manual        │
                                                  │ feedback from Phase 1.        │
                                                  │ Labels: feedback,             │
                                                  │   source:telemetry,           │
                                                  │   type/<bucket>, domain/<X>,  │
                                                  │   severity/*, confidence/*    │
                                                  └───────────────────────────────┘
```

**Five hops, each well-defined:**

1. **Claude Code writes JSONL.** Already happens; no change needed. One file per session at `%USERPROFILE%\.claude\projects\<hash>\<session>.jsonl`.
2. **Laptop pushes via HTTP.** `SessionEnd` hook runs `upload.ps1 -Mode Hook` immediately; an hourly Task Scheduler entry runs `-Mode Sweep` as catch-up. Both POST to the ingest service. Failures queue locally in `uploads.db` and retry with backoff (see §11.8).
3. **Ingest writes to disk.** FastAPI service receives the POST, dedups against SQLite, writes the JSONL to `D:\ai-sherpa\sessions\<dev>\<machine_id>\<session_id>.jsonl`. Logs every request for forensic review.
4. **Analyzer runs nightly.** Same on-prem box. Parses new JSONL into events, runs the §3 detection queries (tabular rules + local embeddings/clustering), generates candidate-change Issue bodies per the templates in §12.3.
5. **Issues filed via `gh` CLI.** Each detected pattern becomes a GitHub Issue with the right labels — joining the Phase 1 triage queue. From there it's the same flow as manual feedback: triage → PR → weekly release → email (see Phase 1 spec).

**Two boundaries that matter:**

- The **HTTP boundary** (between hop 2 and hop 3) is the only network call in the whole pipeline. Everything else is local: file reads on the laptop, file writes + SQLite + Python on the server. Easy to debug; failure mode is bounded.
- The **`gh issue create` boundary** (between hop 4 and hop 5) is the **convergence point with Phase 1** — manual feedback Issues and telemetry-derived Issues land in the same queue, distinguished only by `source:*` labels. The central team's weekly workflow doesn't care which source produced an Issue.

The remaining §11.x subsections drill into each hop.

### 11.2 Topology

- **Single on-prem standalone Windows server** (already exists, always on, has space + CPU). Not AD-joined.
- **Intranet only** — server reachable on the corporate LAN; not exposed to the public internet.
- **Dev laptops are Windows-primary**. Linux/Mac collectors are supported (same logic, bash instead of PowerShell) but not the primary target for v1.

### 11.3 Where sessions live on Windows

Claude Code already writes every session to disk:

`%USERPROFILE%\.claude\projects\<project-hash>\<session-id>.jsonl`

Each line is a single message (user prompt, assistant response, tool call,
tool result). Files are appended during the conversation and finalized at
session end. The collector reads these files; it doesn't need to hook into
Claude Code internals.

### 11.4 Collection mechanism: hook + sweep

Two complementary triggers, both running the same upload script:

| Trigger | When it fires | What it catches |
|---|---|---|
| `SessionEnd` hook in `~/.claude/settings.json` | Every time a Claude Code session ends normally | The 95% case — clean session-end uploads within seconds |
| Hourly Windows Task Scheduler entry | Every hour while the user is logged in and a network is available | The 5% case — sessions where the hook didn't fire (laptop closed, terminal killed, server unreachable at hook time) |

Both invocations run the same PowerShell script (`upload.ps1`) with different `-Mode` arguments (`Hook` or `Sweep`).

### 11.5 Server-side service

A tiny FastAPI service running as a Windows service (installed via NSSM)
on the on-prem server.

**Endpoints:**

- `POST /v1/sessions/{session_id}` — receives a JSONL file. Body = the file contents. Headers: `X-Machine-Id: <uuid>`, `X-Developer: <username>`.
- `GET /healthz` — used by the laptop for fast online detection before bulk upload.

**Behavior:**

- No auth check in v1 (intranet-only; trust-the-network).
- Compute SHA-256 of the body. If `(machine_id, session_id, sha)` already in SQLite, return `200 already-have-this`. Otherwise write to `D:\ai-sherpa\sessions\<developer>\<machine_id>\<session_id>.jsonl` and record in SQLite.
- Log every request (timestamp, source IP, headers, bytes) to `D:\ai-sherpa\logs\ingest.log` — supports later forensic review if abuse appears.

**Size:** Roughly 40 lines of Python. Single file. No DB migrations beyond a tiny SQLite schema.

### 11.6 Client-side: what `setup.bat --enable-telemetry` installs

Files created on the laptop:

```
%USERPROFILE%\.ai-sherpa\
  ├── upload.ps1            ← upload script, two modes
  ├── uploads.db            ← SQLite manifest of already-uploaded sessions
  └── machine-id            ← UUID generated at first run; persists across reinstalls

%USERPROFILE%\.claude\settings.json
  └── hooks.SessionEnd
        → "powershell -NoProfile -ExecutionPolicy Bypass -File
            %USERPROFILE%\.ai-sherpa\upload.ps1 -Mode Hook"

Windows Task Scheduler
  └── "AI Sherpa Hourly Upload"
        → "powershell -NoProfile -ExecutionPolicy Bypass -File
            %USERPROFILE%\.ai-sherpa\upload.ps1 -Mode Sweep"
        → trigger: hourly, only when network available, run as logged-in user
```

### 11.7 Upload script logic (same for both modes)

```
1. For each candidate JSONL file in %USERPROFILE%\.claude\projects\**:
2.   If session_id is in uploads.db with current hash → skip (already uploaded).
3.   If the project root contains NDA.md or CONFIDENTIAL.md → skip; log locally only.
4.   For Phase 1.5: transform the file to metadata-only payload.
5.   For Phase 2:   leave the JSONL as-is.
6.   POST to http://ai-sherpa-srv.local:8080/v1/sessions/<session_id>
        with headers X-Machine-Id, X-Developer.
7.   On 2xx: mark (session_id, sha, uploaded_at) in uploads.db.
8.   On network failure / 5xx / timeout: leave entry as `pending`. Next sweep
        retries with exponential backoff (1m → 5m → 30m → cap at 6h per session).
9.   On 4xx: log to local audit log, mark as `failed` (no retry).
```

The script is fully stateless between invocations — the SQLite manifest is the only persisted state.

### 11.8 Offline tolerance

A laptop off the corporate LAN behaves like this:

1. `SessionEnd` hook fires → upload fails (DNS unresolvable or connection refused) → session marked `pending` in `uploads.db`.
2. Each hourly sweep retries pending sessions with backoff. Stays pending if still off-network.
3. When the laptop reconnects to the corp LAN, the next sweep succeeds and clears the queue.

What's lost in v1: a laptop that **never** reconnects to the LAN (lost, sold,
fully-remote dev who never visits an office). Acceptable; tracked as a v2
concern.

### 11.9 NDA / privacy gate

Before uploading any session, the script checks:

1. Does the session's project directory (or any ancestor) contain `NDA.md` or `CONFIDENTIAL.md`? If yes → skip, log locally only, never upload.
2. (Optional, paranoid mode) Has the user run `setup --review-projects` to explicitly allow-list this project? If allow-list mode is on and the project is not listed → skip.

A persistent project-level marker file (`.ai-sherpa-noupload`) can be dropped into a project root to permanently exclude it from telemetry regardless of NDA file presence.

### 11.10 Bandwidth and storage sanity check

- **Per laptop per day:** ~10 sessions × ~200 KB average = ~2 MB/day.
- **Total ingest:** 150 laptops × 2 MB = ~300 MB/day.
- **Server storage:** at 300 MB/day, a 1 TB volume holds ~9 years of raw sessions. No archival pressure for v1.

### 11.11 Migration path to v2 (off-network laptops)

When the time comes to support fully-remote devs whose laptops never reach the corp LAN:

1. Move the FastAPI service to public DNS (`ai-sherpa-ingest.<org>.com`) with a real TLS cert (Let's Encrypt).
2. Introduce **per-machine bearer tokens** issued at enrollment via `gh auth token` (no auth in v1 → real auth in v2).
3. Add rate limiting (e.g., 100 sessions/hour per machine_id) and source-IP geolocation logging.
4. **Client change is small** — add the bearer token to the existing POST headers; URL switch is a config-only setup update.

The HTTP-first choice in v1 is what makes the v2 upgrade essentially free on
the client side.

---

## 12. Analyzer approach (v1 — no Claude API, no local LLM)

This section captures the concrete analyzer architecture for Phase 2a. The
goal is **zero ongoing AI/LLM cost** while still producing useful improvements
to the AI Sherpa repo every week.

### 12.1 The single objective

The analyzer's job is to answer one question every week:

> *"What should we change in the AI Sherpa repo this week?"*

Everything the analyzer produces is in service of that question. Counts,
rates, clusters, scores — they are all *internal scoring inputs* used to
rank and justify candidate changes. They are **not** separate dashboard
outputs. If a metric doesn't help surface or rank a candidate change, it's
noise and the analyzer doesn't compute it.

### 12.2 The six buckets of AI Sherpa changes

Every improvement to this setup falls into exactly one of these:

| # | Change type | Target file(s) |
|---|---|---|
| 1 | **Add a rule** | `core/CLAUDE.md` or `domains/<X>/CLAUDE.md` |
| 2 | **Refine an existing rule** | Same |
| 3 | **Update a skill description** | `skills/<X>/SKILL.md` `description:` field |
| 4 | **Add or remove a plugin** | `plugins.json` |
| 5 | **Update setup behavior** | `setup.bat` / `setup.sh` / `setup.ps1` |
| 6 | **Update documentation** | `docs/*.md` |

The §3 silent-failure table's "Candidate-change bucket" column maps each
scenario to one of these. If a finding doesn't map to any of these six,
it's noise — discard.

### 12.3 The analyzer's only output: candidate-change Issues

Every analyzer finding becomes a GitHub Issue filed into the **same Phase 1
triage queue** that handles manual feedback. Labels: `feedback`,
`source:telemetry`, `type/<bucket>`, `domain/<X>`, `severity/*`,
`confidence/*`, `status/needs-review`.

Example Issue:

```
Title: [rule] Add malloc-in-ISR warning to embedded domain
Labels: feedback, source:telemetry, type/add-rule, domain/embedded,
        severity/high, confidence/high, status/needs-review

## Suggested change
Add to `domains/embedded/CLAUDE.md` under "Never Do (Embedded)":
> "Always warn before suggesting `malloc` in any ISR or interrupt-
>  related context, even when the developer hasn't tagged the
>  function as an ISR."

## Evidence
- 14 sessions across 6 embedded engineers in past 30 days where
  Claude suggested malloc inside what was contextually an ISR
- Manual feedback Issue #237 reported the same pattern explicitly
- Sample sessions: [linked]

## Estimated impact
- Affects ~6 engineers (40% of embedded team)
- Occurrence rate: ~0.5/engineer/week
- Severity: high (safety-critical for firmware)

## Confidence
high — manual feedback corroborates the telemetry cluster.
```

The Issue is the only artifact the central team interacts with. They
triage, edit, or reject it; if approved, they write the PR (or — in
Phase 2b — accept the LLM-drafted diff).

### 12.4 Where metrics actually live

The metrics referenced in §3 (silent-failure scenarios) and the diagnostic
counts (error rates, ROI, abandonment, accept-then-revert) are still
computed. They live **inside** each candidate-change Issue body as
evidence and scoring inputs — never as a separate dashboard or report.

The central team does not consult a dashboard. They consult the triage
queue. Every metric is justified by what candidate change it helps surface
or rank.

**Optional single derived artifact:** a one-paragraph summary in the
existing weekly release email — *"This week: 12 candidate changes filed
by the analyzer; 8 approved by central team and shipping in v2026.06.01.
Top domain by candidate count: embedded (5)."* That is the only
"dashboard."

### 12.5 Detection capability tiers

The fifteen silent-failure scenarios from §3 split into three tiers based
on what local techniques can detect:

| Tier | Scenarios | Method |
|---|---|---|
| **A. Pure tabular / rule-based** | 3, 7, 8, 10, 11, 12, 13 | SQL queries, frequency analysis, structural pattern matching on event data. No model needed. |
| **B. Local embeddings + clustering** | 1, 2, 5, 9, 15 | Local sentence-transformer model + scikit-learn. Identifies similar prompts, repeated corrections, divergent advice, cross-engineer patterns. Runs on CPU at ~1000 sessions/min. |
| **C. Needs semantic judgment (LLM)** | 4, 6, 14 | NL reasoning over rules and content. Deferred to Phase 2b. |

**v1 covers tiers A and B**, producing candidate-change Issues for 12 of 15
scenarios with zero LLM cost.

### 12.6 Recommended v1 stack

All running on the same on-prem Windows server as the ingest service:

| Layer | Choice | Why |
|---|---|---|
| Language | Python 3.11+ | Already on the server; ecosystem fit |
| Tabular analysis | Pandas + SQLite | No service to run; trivial schema |
| Embeddings | `sentence-transformers` with `BAAI/bge-small-en-v1.5` or `nomic-embed-text` | Free, CPU-friendly (~1000 sessions/min on modest CPU), one-time ~100 MB model download |
| Clustering | `scikit-learn` (HDBSCAN or KMeans) | Standard, well-understood |
| Issue filing | `gh issue create` from the analyzer host | Reuses Phase 1 triage queue |

Total new dependencies: ~5 Python packages. Install time: minutes.
Ongoing API cost: **zero**.

### 12.7 Analyzer pipeline (nightly Windows scheduled task)

```
1. Read all new JSONL files since last run (file mtime tracking in SQLite).
2. Parse each into events: prompts, responses, tool calls, file edits.
3. For each scenario in §3:
   a. Run the corresponding detection (tier-A SQL or tier-B embeddings+cluster).
   b. For each finding above the trigger threshold, compute scoring inputs:
      engineer_count, occurrence_count, domain, severity, confidence.
   c. Look up the scenario's "Candidate-change bucket" from §3.
   d. Render the candidate-change Issue body (deterministic template per
      scenario type — see §12.3 example shape).
   e. `gh issue create` into the triage queue with appropriate labels.
4. Append a one-paragraph summary to the weekly release email body.
```

That's the entire analyzer. No dashboards. No separate reports. No periodic
exports. One nightly process that produces N candidate-change Issues, where
N is typically 0–20 per night for an org this size.

### 12.8 What "confidence" means without an LLM

Same three tiers as §5:

| Confidence | Heuristic |
|---|---|
| **High** | Same finding occurs ≥ N times across ≥ M engineers, low intra-cluster variance, OR corroborated by a manual feedback Issue |
| **Medium** | Structural backing but limited frequency, OR high frequency in a single engineer |
| **Low** | Single occurrence, ambiguous cluster, near-threshold match |

High → auto-file with `status/needs-review`; medium → auto-file with
`status/needs-analyst`; low → local insights queue, weekly human review
(no Issue filed yet).

### 12.9 Upgrade paths to LLM (Phase 2b)

When the org adds LLM budget, the analyzer's job becomes **converting
clusters into PR-ready diff suggestions** — not finding new patterns
(the v1 detectors already do that), but *wording the fix*.

The key reframe: **the LLM doesn't do the analysis. It writes the fix.**
The local-only analyzer in v1 surfaces clusters and patterns deterministic-
ally; Phase 2b adds an LLM step that converts each cluster into PR-ready
prose for the candidate-change Issue.

**Path 1 — Claude API for diff drafting (recommended first move):**

For each candidate-change Issue (from §12.7 step 3.d), make one Claude API
call with the cluster's evidence and ask for:
- Exact rule wording for the target CLAUDE.md / SKILL.md / etc.
- A unified-diff snippet ready to paste into a PR
- A one-sentence rationale for the reviewer

The Issue then arrives with the PR draft already inlined. The central team
accepts/edits, and files the PR with one click.

Cost: ~20 candidates × ~10K tokens × Haiku rates ≈ pennies per week. The
analyzer continues to find candidates without an LLM; the LLM just polishes
the output.

**Path 2 — Local open-source LLM on the same server:**

Same job (diff drafting), different model. Drop in `vllm` or `llama.cpp`
with a 7–8B model (Llama 3.1 8B, Qwen 2.5 7B). Slower inference, lower
quality than Claude, but zero per-call cost. Good fit when data locality is
a hard constraint.

Both paths slot in as **one additional step** between §12.7 step 3.d
(render template) and 3.e (`gh issue create`). No collection-side changes;
no detection changes. The candidate-change Issue model is the same; only
the body quality improves.

---

## 13. What's spec'd vs. what's not

| Asset | Status |
|---|---|
| **Phase 0.5 — Analyzer prototype (local data)** | **Spec'd + implemented + shipped to master**: `2026-05-29-analyzer-prototype-design.md` + `2026-05-29-analyzer-prototype.md` (plan). Implementation merged at commit `efd9fb4`. 21/21 tests passing; 12 findings on a 44-session real-data corpus. |
| Phase 1 design (manual feedback + triage + release + email) | **Spec'd**: `2026-05-28-feedback-release-pipeline-design.md` (commit `181da4e`). |
| Phase 1 implementation plan | **Spec'd**: `2026-05-29-phase1-feedback-release-pipeline.md` (commit `bab4924`). Not yet implemented. |
| **Phase 1.5 (eliminated)** | ~~Originally planned for metadata-only telemetry. Folded into Phase 2a since Anthropic Admin API now provides the equivalent per-developer metrics layer.~~ |
| Phase 2a design (multi-developer collection + analyzer) | **Spec'd**: `2026-05-29-phase2a-design.md` (commit `45750f3`). Plan: `2026-05-29-phase2a.md` (commit `f393b18`). Not yet implemented. |
| Phase 2b design (LLM-assisted polish) | **Spec'd**: `2026-05-29-phase2b-design.md` (commit `c44801f`). Plan: `2026-05-29-phase2b.md` (commit `d20ebdc`). Not yet implemented. |
| OSS landscape research | `2026-05-29-oss-claude-session-tools-comparison.md` (commit `d691c56`). |
| Repo-zone discipline (CI filters, CODEOWNERS, smoke test) | Not yet spec'd. Will be implemented as a small structural PR before any Phase 2a server code lands. |

---

## 14. Next steps

Updated 2026-05-29: post-Phase-0.5 + all-phases-spec'd state.

1. **User reviews the full bundle** — all 5 specs + 3 plans + this roadmap end-to-end. Tell me what to edit. (Current step.)
2. **Implement Phase 1.** Spec + plan ready. ~2–3 weeks of work. Manual feedback + triage + release + email. Ships before any Phase 2a infrastructure work.
3. **Implement Phase 2a.** Spec + plan ready. ~4 weeks of work. Builds the on-prem server + collector + 14 detectors + auto-filer. Joins the Phase 1 triage queue.
4. **Decide on Phase 2b.** Opt-in after Phase 2a runs for ~4 weeks and we know which candidate-change Issues feel ready for LLM polish.
5. **Repo-zone discipline PR.** Small structural commit (CI path filters + CODEOWNERS + setup smoke test) before any large Phase 2a code lands. ~1 hour of work.

This roadmap is the parent doc; each phase has its own design spec and
implementation plan.
