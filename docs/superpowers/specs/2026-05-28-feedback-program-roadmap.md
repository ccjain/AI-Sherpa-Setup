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

| # | Scenario | Detection method | Data |
|---|---|---|---|
| 1 | **Skill should have fired but didn't (per-session diagnosis)** | Cross-reference session topic vs. installed skills' `description:` fields. Embeddings or keyword match. Aggregate version of this signal (low fire-rate per skill) is captured by scenario 11 with metadata alone. | T |
| 2 | **Same correction repeated across sessions** | Diff what engineer edits *after* accepting AI output. Hash the (suggestion → edit) deltas; cluster repeats. | T |
| 3 | **Domain mismatch** | File extensions touched in sessions vs. configured AI Sherpa domain. | M |
| 4 | **Stale memory contradicting current code** | Compare `~/.claude/memory/*.md` facts against current repo state. | M + T |
| 5 | **Repeated context-priming** | First N tokens of prompts hashed/embedded; flag boilerplate that recurs. | T |
| 6 | **Rule existed but didn't trigger** | For each CLAUDE.md rule, define a content signature; scan sessions where it appears but the rule warning didn't. | T |
| 7 | **Tool misuse / inefficient patterns** | `Bash + cat` instead of Read; `Bash + grep` instead of Grep; permission-prompt rate. | M |
| 8 | **Sessions ending in frustration / abandonment** | Multiple `/clear`, `/restart`, sessions ending mid-task. Structural signal. | M |
| 9 | **Inconsistent advice across engineers** | Cluster sessions by intent (embeddings on first prompt); flag divergent first-pass answers. | T |
| 10 | **High accept-then-revert rate** | Tool suggestion accepted → file edited again within 60s. Effective "yes but actually no". | M |
| 11 | **Plugin/skill ROI** | For each installed skill: fire rate × accept rate × subsequent-edit rate. | M |
| 12 | **Onboarding velocity** | Session-length, tool-counts over time for new hires vs. veterans. | M |
| 13 | **Stale install** | `VERSION` per engineer at session start; flag anyone > N releases behind. | M |
| 14 | **Workaround / override patterns** | Engineer repeatedly says "ignore the rule" or "actually just do X". | T |
| 15 | **Cross-engineer lone-genius patterns** | Cluster similar problems; surface the best solution as a candidate skill. | T |

**Seven of fifteen scenarios are fully detectable with metadata alone**
(scenarios 3, 7, 8, 10, 11, 12, 13), and an eighth (1) is partially detectable
via the aggregate ROI signal in scenario 11. That's the case for shipping
Phase 1.5 before Phase 2's legal review completes.

---

## 4. Three-phase rollout

| Phase | Duration | What it adds | Privacy hurdle |
|---|---|---|---|
| **1 — Manual feedback** | 2–3 weeks | `/ai-sherpa-feedback` skill, GH Issue form, triage labels + Project board, weekly release Action, Apps Script email to Google Group, `--update` change-summary tail. | None |
| **1.5 — Metadata telemetry** | 4–6 weeks (run in parallel with Phase 1 implementation) | On-device collector (events only, no content), ingest endpoint, metadata DB, dashboards/reports. Detects scenarios 3, 7, 8, 10, 11, 12, 13 from §3 (plus the aggregate version of 1 via 11). | None — no transcript content shipped |
| **2a — Full transcripts + local analyzer (no LLM)** | 2–3 months, gated on legal/InfoSec sign-off | Upgrade collector to ship full sessions. Analyzer built with **rule-based heuristics + local sentence-transformer embeddings + clustering** — no Claude API calls, no local LLM. Catches scenarios 1, 2, 5, 9, 15 with good quality; catches a partial version of 4, 6, 14. Runs on the existing on-prem server. **Zero ongoing API cost.** | **Yes** — legal/InfoSec approval required for full transcripts |
| **2b — LLM-assisted analyzer** | Adds 2–4 weeks of work after 2a, gated separately on Claude API budget approval OR local LLM deployment | Adds a final "semantic judgment" pass to the analyzer. Tightens detection of scenarios 4, 6, 14 (which need natural-language reasoning over rules and memory). Two options for the LLM: Claude API (cheap when scoped to top-N candidates per week) or a locally-run open model (Llama / Qwen on the on-prem server). | Same as 2a (the data is already approved); plus budget approval for API path |

**Why this order:**

- **Phase 1 first** for one specific reason: it ships fastest *and* it produces
  the labelled ground-truth corpus the Phase 2 analyzer needs for calibration.
  Without Phase 1 data, we can't tell if the analyzer is finding real problems
  or hallucinating ones.
- **Phase 1.5 in parallel** because metadata-only telemetry has no privacy
  hurdle and catches 8/15 scenarios. Waiting for Phase 2 to start any
  telemetry would mean months of blind operation.
- **Phase 2 in parallel** on the legal/InfoSec track. The engineering work
  starts when legal completes; the legal review starts *now*. If the review
  takes 8 weeks, the engineering does not also take 8 weeks of clock time
  after — they overlap.

---

## 5. Convergence — one triage queue, two sources

Both channels produce GitHub Issues with consistent labelling so the central
team triages them the same way:

```
Manual feedback             Telemetry insight
  (Phase 1)                  (Phase 1.5 / 2)
       │                            │
       │  /ai-sherpa-feedback       │  Analyzer auto-files
       │  → GH Issue                │  → GH Issue
       │  labels: feedback,         │  labels: feedback, source:telemetry,
       │   source:manual,           │   confidence:{high,med,low},
       │   domain/*,                │   domain/*,
       │   status/needs-review      │   status/needs-review
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

This section captures the concrete v1 mechanism the program uses to ship
session data from each dev's laptop to the on-prem server. The mechanism is
the same for Phase 1.5 (metadata only) and Phase 2 (full transcripts) — only
the payload shape differs.

### 11.1 Topology

- **Single on-prem standalone Windows server** (already exists, always on, has space + CPU). Not AD-joined.
- **Intranet only** — server reachable on the corporate LAN; not exposed to the public internet.
- **Dev laptops are Windows-primary**. Linux/Mac collectors are supported (same logic, bash instead of PowerShell) but not the primary target for v1.

### 11.2 Where sessions live on Windows

Claude Code already writes every session to disk:

`%USERPROFILE%\.claude\projects\<project-hash>\<session-id>.jsonl`

Each line is a single message (user prompt, assistant response, tool call,
tool result). Files are appended during the conversation and finalized at
session end. The collector reads these files; it doesn't need to hook into
Claude Code internals.

### 11.3 Collection mechanism: hook + sweep

Two complementary triggers, both running the same upload script:

| Trigger | When it fires | What it catches |
|---|---|---|
| `SessionEnd` hook in `~/.claude/settings.json` | Every time a Claude Code session ends normally | The 95% case — clean session-end uploads within seconds |
| Hourly Windows Task Scheduler entry | Every hour while the user is logged in and a network is available | The 5% case — sessions where the hook didn't fire (laptop closed, terminal killed, server unreachable at hook time) |

Both invocations run the same PowerShell script (`upload.ps1`) with different `-Mode` arguments (`Hook` or `Sweep`).

### 11.4 Server-side service

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

### 11.5 Client-side: what `setup.bat --enable-telemetry` installs

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

### 11.6 Upload script logic (same for both modes)

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

### 11.7 Offline tolerance

A laptop off the corporate LAN behaves like this:

1. `SessionEnd` hook fires → upload fails (DNS unresolvable or connection refused) → session marked `pending` in `uploads.db`.
2. Each hourly sweep retries pending sessions with backoff. Stays pending if still off-network.
3. When the laptop reconnects to the corp LAN, the next sweep succeeds and clears the queue.

What's lost in v1: a laptop that **never** reconnects to the LAN (lost, sold,
fully-remote dev who never visits an office). Acceptable; tracked as a v2
concern.

### 11.8 NDA / privacy gate

Before uploading any session, the script checks:

1. Does the session's project directory (or any ancestor) contain `NDA.md` or `CONFIDENTIAL.md`? If yes → skip, log locally only, never upload.
2. (Optional, paranoid mode) Has the user run `setup --review-projects` to explicitly allow-list this project? If allow-list mode is on and the project is not listed → skip.

A persistent project-level marker file (`.ai-sherpa-noupload`) can be dropped into a project root to permanently exclude it from telemetry regardless of NDA file presence.

### 11.9 Bandwidth and storage sanity check

- **Per laptop per day:** ~10 sessions × ~200 KB average = ~2 MB/day.
- **Total ingest:** 150 laptops × 2 MB = ~300 MB/day.
- **Server storage:** at 300 MB/day, a 1 TB volume holds ~9 years of raw sessions. No archival pressure for v1.

### 11.10 Migration path to v2 (off-network laptops)

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
goal is **zero ongoing AI/LLM cost** while still extracting useful insights
from the collected sessions.

### 12.1 Scenario tiers by required capability

The fifteen silent-failure scenarios from §3 split into three tiers based on what techniques can detect them:

| Tier | Scenarios | Method | Quality |
|---|---|---|---|
| **A. Pure tabular / rule-based** | 3, 7, 8, 10, 11, 12, 13 | SQL queries, frequency analysis, structural pattern matching on event data. No model needed. | Excellent |
| **B. Local embeddings + clustering** | 1, 2, 5, 9, 15 | Local sentence-transformer model + scikit-learn. Identifies similar prompts, repeated corrections, divergent advice, cross-engineer patterns. Runs on CPU at ~1000 sessions/min. | Good — finds patterns but can't *explain* them in natural language |
| **C. Needs semantic judgment (LLM)** | 4, 6, 14 | "Does this memory entry contradict the current code?" / "Did this CLAUDE.md rule apply but the model glossed over it?" Requires NL reasoning. | Deferred to Phase 2b |

**v1 covers tiers A and B**, catching 12 of 15 scenarios with zero LLM cost.

### 12.2 Recommended v1 stack

All running on the same on-prem Windows server as the ingest service:

| Layer | Choice | Why |
|---|---|---|
| Language | Python 3.11+ | Already on the server; ecosystem fit |
| Tabular analysis | Pandas + SQLite | No service to run; trivial schema |
| Embeddings | `sentence-transformers` with `BAAI/bge-small-en-v1.5` or `nomic-embed-text` | Free, CPU-friendly (~1000 sessions/min on a modest CPU), one-time ~100 MB model download |
| Clustering | `scikit-learn` (HDBSCAN or KMeans) | Standard, well-understood |
| Reports | f-string Markdown → HTML via `markdown` library | Static HTML output served from a folder; no web framework needed |

Total new dependencies on the server: ~5 Python packages. Install time: minutes. Ongoing API cost: **zero**.

### 12.3 Analyzer pipeline (runs as a Windows scheduled task, default nightly)

```
1. Read all new JSONL files since last run (tracked by file mtime in SQLite).
2. Parse each session into events: prompts, responses, tool calls, file edits.
3. For each tier-A scenario: run the corresponding SQL/pandas query against
   events. Insert findings into insights DB.
4. For each tier-B scenario:
   a. Compute embeddings for prompt openings, edit deltas, etc.
   b. Cluster within the new batch + recent history.
   c. Surface clusters exceeding a threshold (e.g., same edit applied 5+ times).
5. Generate weekly report (HTML) summarizing top findings per domain.
6. For high-confidence findings, auto-file GitHub Issues into the Phase 1
   triage queue via `gh issue create` from the analyzer host.
```

### 12.4 What "confidence" means without an LLM

We don't need natural-language confidence scoring — the existing signal is enough:

| Confidence | Heuristic |
|---|---|
| **High** | Same finding occurs ≥ N times across ≥ M engineers, low intra-cluster variance |
| **Medium** | Finding has structural backing but limited frequency, OR high frequency in a single engineer |
| **Low** | Single occurrence, ambiguous cluster, near-threshold match |

Same three-tier auto-file gate as §5: high → auto-Issue; medium → auto-Issue with `status/needs-analyst`; low → local queue, weekly human review.

### 12.5 Upgrade paths to LLM (Phase 2b)

When the org is ready to add LLM analysis:

**Path 1 — Claude API for the "explain" step (recommended first move):**

- Keep the v1 analyzer for finding candidates.
- For each candidate (top N per week), make one Claude API call: "given this evidence, write a one-paragraph natural-language description and a suggested rule change."
- Cost: ~20 candidates × ~10K tokens × Haiku rates ≈ pennies per week.

**Path 2 — Local open-source LLM on the same server:**

- Drop in `vllm` or `llama.cpp` with a 7–8B model (Llama 3.1 8B, Qwen 2.5 7B).
- Slower inference, lower quality than Claude, but zero per-call cost.
- Good fit if data locality is a hard constraint.

Both swap in as **one additional pipeline step** in §12.3. No collection-side changes required.

---

## 13. What's spec'd vs. what's not

| Asset | Status |
|---|---|
| Phase 1 design (manual feedback + triage + release + email) | **Spec'd**: `2026-05-28-feedback-release-pipeline-design.md` (commit `181da4e`) |
| Phase 1 implementation plan | Not yet written. Next step after this roadmap is approved. |
| Phase 1.5 design (metadata telemetry) | Concepts captured in §11 + §12 of this roadmap. Full spec to be written before Phase 1.5 implementation, ideally in parallel with Phase 1. |
| Phase 2a design (full transcripts + local analyzer) | Concepts captured in §11 + §12. Full spec to be written after Phase 1 ships and legal review is well underway. |
| Phase 2b design (LLM-assisted analyzer) | Sketch in §12.5. Full spec when Claude API budget or local LLM is approved. |
| Repo-zone discipline (CI filters, CODEOWNERS, smoke test) | Not yet spec'd. Will be implemented as a small structural PR before any Phase 1.5 / 2 code lands. |

---

## 14. Next steps

In order:

1. **User reviews this roadmap.** Pin down anything that needs adjustment.
2. **User reviews the Phase 1 spec** (`2026-05-28-feedback-release-pipeline-design.md`). Approve or request changes.
3. **Write the Phase 1 implementation plan** (via the writing-plans skill). This produces the step-by-step task list to ship Phase 1.
4. **Implement Phase 1.** ~2–3 weeks.
5. **In parallel with #4:** Start the legal/InfoSec engagement for Phase 2a (full transcripts). Write the Phase 1.5 spec (metadata telemetry — concrete starting point in §11 of this roadmap). Land the small structural PR (zone discipline tooling).
6. **Implement Phase 1.5** once Phase 1 is shipping. ~4–6 weeks.
7. **Write Phase 2a spec + implement** once legal approves and Phase 1 has produced ~6–8 weeks of ground-truth manual feedback for analyzer calibration.
8. **Decide on Phase 2b (LLM)** once Phase 2a is producing insights and the org has visibility into what the local analyzer can/can't catch.

This roadmap is the parent doc; each phase gets its own design spec and
implementation plan as it comes due.
