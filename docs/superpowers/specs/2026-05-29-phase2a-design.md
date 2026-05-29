# Phase 2a — Full-Transcript Analyzer Design

**Date:** 2026-05-29
**Status:** Spec (pre-implementation)
**Scope:** Multi-developer telemetry collection (full session JSONL) + indexed storage + 14-detector analyzer + Markdown/HTML output + auto-filing of high-confidence findings into the Phase 1 triage queue. No LLM in v1.

---

## 1. Goals

1. Detect silent-failure patterns in real Claude Code sessions across the organization, complementing manual feedback (Phase 1) with telemetry-derived candidate-change Issues.
2. Reuse the Phase 0.5 prototype's detector code and the Phase 1.5 collection design — no redesign at those layers.
3. Layer in `sujankapadia/claude-code-analytics`'s indexing patterns (SQLite FTS5 + ChromaDB) so the analyzer scales past 5,000 sessions without re-parse cost.
4. Layer in `lucemia/claude-session-analyzer`'s detection taxonomy — Read:Edit ratio, edits-without-prior-Read, self-admitted errors, user frustration text — adding four new detectors (scenarios 16–19) for a 14-detector total.
5. Use Anthropic's Admin API for org-level per-developer structured metrics instead of building a redundant metadata collector.
6. Apply a two-tier retention model: 7-day rolling for raw sessions (already on devs' laptops), forever-with-snapshots for insights (the durable artifact).
7. Auto-file high-confidence cross-developer findings as GitHub Issues into the AI Sherpa repo's Phase 1 triage queue.

## 2. Non-goals

- LLM-assisted analysis (deferred to Phase 2b — drops in as one step at find-time).
- Cross-engineer scenarios 9 and 15 (need semantic judgment — Phase 2b).
- Off-network laptop support (Phase 1.5 §11.10 v2 plan; intranet-only here).
- A custom React dashboard. The Markdown + HTML output from Phase 0.5 carries forward.
- Re-analysis of sessions older than 7 days. Past findings persist; the raw data does not.
- LLM-driven content classification. All v1 detection is rule-based + local embeddings.
- Public exposure of any analyzer endpoint. Server is intranet-only.

## 3. Constraints & context

| Item | Value |
|---|---|
| Org plan | Team / Enterprise (Anthropic Admin API available) |
| Legal posture | Full transcripts approved |
| Network | Intranet only |
| Server | Existing on-prem Windows machine (already used by Phase 1.5) |
| Dev laptops | Windows-primary (Linux/Mac collectors supported but not v1 target) |
| Scale planning | 150 developers × ~10 sessions/day × ~200 KB ≈ ~300 MB/day ingest |
| Steady-state storage | ~2.5 GB hot + ~55 MB warm + ~7 MB/year cold (see §6.5) |
| LLM use | None in v1; Phase 2b path documented |

## 4. Architecture

```
ON DEV LAPTOPS (Windows × ~150)              ON-PREM WINDOWS SERVER (always on)
                                              + ANTHROPIC ADMIN API (external)
┌─ Claude Code writes JSONL ────────┐
│ %USERPROFILE%\.claude\projects\   │         ┌─ FastAPI ingest ──────────────┐
│   <hash>\<session>.jsonl          │         │ POST /v1/sessions/{id}        │
└────────────────┬──────────────────┘         │   body: JSONL                  │
                 │                             │ → SHA-256 dedup                │
┌─ SessionEnd hook + hourly sweep ──┐  HTTP   │ → write to D:\ai-sherpa\…      │
│ upload.ps1 → POST JSONL           ├────────▶│ → SQLite FTS5 index events     │
└────────────────┬──────────────────┘ POST    │ → ChromaDB embed first-prompts │
                 │                             └────────────────┬───────────────┘
                 │ + NDA gate                                   │
                                                                ▼
                          ┌─ Anthropic Admin API ──┐  ┌─ Indexed storage on server ────┐
                          │ daily pull, JSON cache │  │ D:\ai-sherpa\                  │
                          │ per-dev metrics:       │  │  ├─ sessions\<dev>\<m>\*.jsonl │
                          │  - tokens              │  │  ├─ events.sqlite (FTS5)       │
                          │  - acceptance rate     │  │  ├─ chroma\ (vector DB)        │
                          │  - DAU, sessions       │  │  ├─ admin_api_cache\*.json     │
                          │  - LOC accepted        │  │  └─ insights.sqlite            │
                          └─────────────┬──────────┘  └────────────────┬───────────────┘
                                        │                              │
                                        └────────────┬─────────────────┘
                                                     │ nightly Windows task
                                                     ▼
                          ┌─ Analyzer (Python, on same server) ──────┐
                          │ - query SQLite + ChromaDB + Admin cache  │
                          │ - run 14 detectors (10 Phase 0.5 + 4     │
                          │   from lucemia taxonomy)                  │
                          │ - render findings as candidate-change    │
                          │   Issues                                  │
                          └──────────────────┬───────────────────────┘
                                             │
                          ┌──────────────────┼──────────────────┐
                          ▼                  ▼                  ▼
              ┌─ Markdown files ──┐ ┌─ HTML summary ┐ ┌─ Auto-file GH Issues ─┐
              │ analyzer-out\     │ │ filterable    │ │ high-confidence only; │
              │   issues\*.md     │ │ table         │ │ same triage queue as  │
              └───────────────────┘ └───────────────┘ │ Phase 1 manual feedback│
                                                      └────────────────────────┘
```

Six components, each with one job:

| # | Component | Where | Job |
|---|---|---|---|
| 1 | Collector | Per dev machine | Hook + sweep, NDA gate, POST full JSONL |
| 2 | Ingest service | On-prem server | Receive, dedup, write to disk, index into FTS5 + ChromaDB |
| 3 | Admin API puller | On-prem server (scheduled) | Daily fetch from Anthropic Admin API, cache JSON locally |
| 4 | Detector library | On-prem server | 14 detectors over events DataFrame, embeddings, and admin metrics |
| 5 | Renderer | On-prem server | Findings → Markdown files + HTML summary |
| 6 | Issue auto-filer | On-prem server | High-confidence findings → `gh issue create` into AI Sherpa repo |

**Convergence with Phase 1:** Component 6 files Issues with labels `feedback`, `source:telemetry`, `confidence/*`, `domain/*` — joining the same triage queue manual feedback uses. No new workflow for the central team.

## 5. Component 1 — Collector (Phase 1.5 reuse, full-JSONL payload)

Direct reuse of the Phase 1.5 mechanism from roadmap §11. Same code, same hook, same sweep, same intranet HTTP POST. Only the payload shape changes — full JSONL instead of metadata-only events.

### 5.1 Installed per laptop by `setup.bat --enable-telemetry`

```
%USERPROFILE%\.ai-sherpa\
  ├── upload.ps1        ← runs in -Mode Hook (SessionEnd) or -Mode Sweep (hourly)
  ├── uploads.db        ← SQLite manifest: (session_id, sha, uploaded_at, status)
  └── machine-id        ← UUID stored on first run; survives reinstalls

%USERPROFILE%\.claude\settings.json
  └── hooks.SessionEnd  → powershell -File upload.ps1 -Mode Hook

Windows Task Scheduler
  └── "AI Sherpa Hourly Upload"  → upload.ps1 -Mode Sweep
        + condition: OnlyIfNetworkAvailable
```

### 5.2 Payload change vs. Phase 1.5

| | Phase 1.5 (metadata-only) | Phase 2a (full transcripts) |
|---|---|---|
| Body | Extracted event-stream JSON, ~3 KB | Raw JSONL file, ~50–500 KB |
| Endpoint | `POST /v1/events/{session_id}` | `POST /v1/sessions/{session_id}` |
| Headers | `X-Machine-Id`, `X-Developer` | unchanged |
| Privacy | No transcript content | Full transcript (legal-approved) |

### 5.3 NDA / privacy gate (unchanged from Phase 1.5)

Skip uploads if the session's project directory or any ancestor contains `NDA.md`, `CONFIDENTIAL.md`, or `.ai-sherpa-noupload`. Skipped sessions logged locally only; aggregate skipped counts surface in admin telemetry.

### 5.4 Offline tolerance + retry

Hourly sweep retries `pending` entries with exponential backoff (1m → 5m → 30m → 6h cap). Laptops off the corporate LAN queue locally; ship on next LAN reconnect.

### 5.5 Auth (v1)

No auth. Intranet-only. Identity from `X-Developer` + `X-Machine-Id` headers, not cryptographically asserted. Upgrade path to per-machine bearer tokens documented in roadmap §11.10 (v2).

### 5.6 Consent flag

A `Config` field `enable_transcripts: bool` (default true) on each machine. If flipped to false (e.g., legal revokes), next sweep stops uploading. Documented in config.json.

## 6. Component 2 — Ingest service (with FTS5 + ChromaDB indexing)

The ingest endpoint now performs three writes per successful upload: raw file to disk, events to SQLite FTS5, first-prompt embedding to ChromaDB.

### 6.1 Endpoint

`POST /v1/sessions/{session_id}` with headers `X-Machine-Id`, `X-Developer`, body = raw JSONL.

### 6.2 Behavior

1. Verify no `X-AI-Sherpa-Token` mismatch (in v1, no auth — always pass).
2. Compute SHA-256 of body. If `(machine_id, session_id, sha)` already in `sessions` table → return `200 already-have-this`.
3. Write JSONL to `D:\ai-sherpa\sessions\<developer>\<machine_id>\<session_id>.jsonl`.
4. Parse JSONL into events (reuse `ingest.py` from Phase 0.5 prototype).
5. Bulk insert into `events.sqlite` events table. Trigger-cascade keeps `events_fts` virtual table in sync.
6. UPSERT into `sessions` table with started_at, ended_at, event_count, tool_call_count.
7. Extract first user prompt; embed via `BAAI/bge-small-en-v1.5`; add to ChromaDB `first_prompts` collection with metadata `{session_id, developer, project_path_hash, timestamp}`.
8. Log request (timestamp, source IP, machine_id, bytes) to `D:\ai-sherpa\logs\ingest.log`.

Indexing failures (steps 5–7) are logged but **do not fail the upload**. Raw JSONL is the source of truth; indexes are rebuildable.

### 6.3 Performance budget

At 300 MB/day ingest spread across 150 devs (most arrive in clumps around end-of-workday), peak rate ~1–2 sessions/sec. SQLite FTS5 insertion and ChromaDB embedding handle this comfortably on the existing server. Embedding the first-prompt of one session takes ~100 ms on CPU.

### 6.4 Bandwidth + storage sanity check

- Per laptop per day: ~10 sessions × ~200 KB = ~2 MB/day
- Total ingest: 150 × 2 MB = ~300 MB/day
- 7-day rolling window: ~2 GB raw + ~400 MB FTS5 + ~8 MB ChromaDB = ~2.5 GB
- 1 TB on-prem server: 0.3% utilized

## 7. Component 3 — Anthropic Admin API puller

Daily JSON pull, locally cached, queried by detectors that benefit from org-level structured metrics.

### 7.1 What we pull

Per-developer daily metrics from Anthropic's Admin API:

| Metric | Granularity | Used by |
|---|---|---|
| Tokens (input/output, cache split) | Per dev, per day, per model | scenario-13 (correlate version with token rate) |
| Suggestion acceptance rate | Per dev, per day | scenario-10, scenario-17 |
| DAU, sessions | Per dev, per day | scenario-12 baseline |
| LOC accepted + PRs assisted | Per dev, per day | health KPI; stored for trend analysis |
| Cost in USD | Per dev, per day | rollup; not detector input directly |

### 7.2 Puller (~30 lines)

`server/admin_api/puller.py`. Runs daily at `admin_puller_time` (default 02:00) via Windows Task Scheduler. Backfills the last 8 days each run so a missed day self-heals.

### 7.3 Secret management

API key in Windows Credential Manager under `ai-sherpa-admin-api`. Read via `keyring` library at task startup. Never in plain text on disk, never echoed in logs.

### 7.4 Cache layout

One daily JSON file per day: `D:\ai-sherpa\admin_api_cache\YYYY-MM-DD.json`. Normalizer (`admin_api.py::load_admin_metrics`) merges all cached days into a pandas DataFrame for detector consumption.

### 7.5 Failure modes

| Failure | Behavior |
|---|---|
| 401 (bad key) | Log error; analyzer runs with empty admin DataFrame |
| 429 / 5xx | Wait 60s, retry up to 3× |
| Network unreachable | Backfill catches the gap next run |
| Corrupted cache file | Normalizer skips it; other days still load |

## 8. Component 4 — Storage layer (two tiers, single source of truth)

### 8.1 Stores at a glance

```
D:\ai-sherpa\
  ├── sessions\<dev>\<machine_id>\<session_id>.jsonl   ← SOURCE OF TRUTH (7-day rolling)
  ├── events.sqlite                                     ← FTS5-indexed event stream (7-day)
  ├── chroma\                                           ← persistent embedding store (7-day)
  ├── admin_api_cache\*.json                            ← daily API pulls (1-year)
  ├── insights.sqlite                                   ← findings + run metadata (forever)
  ├── analyzer-out\YYYY-MM-DD\                          ← rendered output (30-day)
  └── logs\ingest.log
```

**Reconstructibility rule:** if `events.sqlite` and `chroma\` are deleted, a rebuild script (`tools/rebuild-indexes.py`) reproduces them from `sessions\**\*.jsonl`. Raw files are truth; indexes are caches.

### 8.2 `events.sqlite` schema

```sql
CREATE TABLE events (
    event_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    session_path    TEXT NOT NULL,
    project_path_hash TEXT NOT NULL,
    developer       TEXT NOT NULL,
    machine_id      TEXT NOT NULL,
    timestamp       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    text            TEXT,
    tool_name       TEXT,
    tool_args_json  TEXT,
    tool_success    INTEGER,
    command_first_word TEXT,
    file_extension  TEXT,
    skill_name      TEXT,
    slash_command_name TEXT,
    is_first_in_session INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_events_session   ON events(session_id);
CREATE INDEX idx_events_developer ON events(developer);
CREATE INDEX idx_events_type      ON events(event_type);
CREATE INDEX idx_events_timestamp ON events(timestamp);

CREATE VIRTUAL TABLE events_fts USING fts5(
    text,
    content='events',
    content_rowid='event_id'
);

CREATE TRIGGER events_ai AFTER INSERT ON events BEGIN
    INSERT INTO events_fts(rowid, text) VALUES (new.event_id, new.text);
END;
CREATE TRIGGER events_ad AFTER DELETE ON events BEGIN
    DELETE FROM events_fts WHERE rowid = old.event_id;
END;

CREATE TABLE sessions (
    session_id      TEXT PRIMARY KEY,
    session_path    TEXT NOT NULL,
    developer       TEXT NOT NULL,
    machine_id      TEXT NOT NULL,
    started_at      TEXT,
    ended_at        TEXT,
    event_count     INTEGER NOT NULL,
    tool_call_count INTEGER NOT NULL,
    nda_skipped     INTEGER NOT NULL DEFAULT 0,
    ingested_at     TEXT NOT NULL
);
CREATE INDEX idx_sessions_developer ON sessions(developer);
CREATE INDEX idx_sessions_started   ON sessions(started_at);
```

### 8.3 ChromaDB collections

```python
import chromadb
client = chromadb.PersistentClient(path=r"D:\ai-sherpa\chroma")
```

| Collection | What it embeds | Used by |
|---|---|---|
| `first_prompts` | First user prompt per session (≤ 500 chars) | scenario-5, scenario-9, scenario-1 |
| `corrections` | User prompts matching correction phrases (≤ 300 chars) | scenario-2 |
| `assistant_responses_sample` | 1-in-N assistant response sample | scenario-15 (future) |

All collections use cosine distance. Persistent on disk; only new sessions get embedded.

### 8.4 `insights.sqlite` schema

```sql
CREATE TABLE runs (
    run_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at      TEXT NOT NULL,
    ended_at        TEXT,
    sessions_seen   INTEGER,
    findings_total  INTEGER,
    analyzer_version TEXT,
    error_log_json  TEXT
);

CREATE TABLE findings (
    finding_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          INTEGER NOT NULL REFERENCES runs(run_id),
    scenario_id     TEXT NOT NULL,
    title           TEXT NOT NULL,
    bucket          TEXT NOT NULL,
    domain          TEXT,
    severity        TEXT NOT NULL,
    confidence      TEXT NOT NULL,
    evidence_md     TEXT NOT NULL,
    fingerprint     TEXT NOT NULL,
    cluster_centroid_embedding BLOB,
    sample_snippets_json TEXT,
    contributing_session_ids_json TEXT,
    contributing_developer_count INTEGER,
    contributing_occurrence_count INTEGER,
    issue_url       TEXT,
    issue_filed_at  TEXT
);
CREATE INDEX idx_findings_run         ON findings(run_id);
CREATE INDEX idx_findings_fingerprint ON findings(fingerprint);
CREATE INDEX idx_findings_filed       ON findings(issue_filed_at);

CREATE TABLE finding_recurrences (
    finding_id   INTEGER NOT NULL REFERENCES findings(finding_id),
    run_id       INTEGER NOT NULL REFERENCES runs(run_id),
    occurrence_count_at_run INTEGER NOT NULL,
    PRIMARY KEY (finding_id, run_id)
);
```

`cluster_centroid_embedding` lets future runs recognize the same pattern even after source sessions are pruned. `sample_snippets_json` (up to 5 sample text excerpts captured at find-time) keeps Issue evidence self-contained.

### 8.5 Pruner — small scheduled job

Runs daily at `pruner_run_time` (default 03:00).

1. **Sessions:** `DELETE FROM events WHERE timestamp < (now - 7 days)` (FTS5 sync via trigger); `DELETE FROM sessions WHERE ended_at < (now - 7 days)`; `os.remove` raw JSONL files for the same sessions.
2. **ChromaDB:** per collection, `collection.delete(where={"timestamp": {"$lt": cutoff_iso}})`.
3. **Admin cache:** delete daily JSONs older than `admin_api_retention_days` (default 365).
4. **Analyzer output:** delete `analyzer-out\YYYY-MM-DD\` folders older than `output_retention_days` (default 30).

Insights are never pruned unless `insights_retention_days` is explicitly set non-None.

### 8.6 Capacity at scale

| Tier | Steady-state size |
|---|---|
| Hot (raw JSONL + events + chroma) | ~2.5 GB |
| Warm (admin cache) | ~55 MB |
| Cold (insights) | ~7 MB/year (grows linearly, ~70 MB at year 10) |
| **Total at year 10** | ~2.62 GB |

The on-prem server's 1 TB is 0.3% utilized at year 10. The system is essentially storage-free.

### 8.7 Backups

Mirror `sessions\`, `admin_api_cache\`, `insights.sqlite` nightly via robocopy to a second drive. Indexes (`events.sqlite`, `chroma\`) are rebuildable and don't need backing up.

## 9. Component 5 — Detector library (14 detectors)

### 9.1 The 14 detectors

| # | Scenario | Tier | Bucket | New in Phase 2a? |
|---|---|---|---|---|
| 1 | Skill should have fired | Embedding | skill-fix | No (Phase 0.5) |
| 2 | Same correction repeated | Embedding | add-rule | No |
| 3 | Domain mismatch | Tabular | setup-fix | No |
| 5 | Repeated context-priming | Embedding | add-rule | No |
| 7 | Tool misuse | Tabular | add-rule | No |
| 8 | Sessions ending in frustration | Tabular | add-rule | No |
| 10 | Accept-then-revert | Tabular | refine-rule | No |
| 11 | Plugin/skill ROI | Tabular | skill-fix | No |
| 12 | Onboarding velocity | Tabular | docs | No |
| 13 | Stale install | Tabular | setup-fix | No |
| 16 | Edits without prior Read | Tabular | add-rule | **Yes** |
| 17 | Self-admitted errors per 1K tool calls | Tabular | refine-rule | **Yes** |
| 18 | Low Read:Edit ratio | Tabular | add-rule | **Yes** |
| 19 | User frustration in prompt text | Tabular | add-rule | **Yes** |

Scenarios 4, 6, 9, 14, 15 deferred to Phase 2b (LLM-required).

### 9.2 The four new detectors (lucemia taxonomy)

**Scenario 16 — Edits without prior Read** — count (session, file) pairs where the first Edit/Write happens before any Read. Flag when ratio exceeds 30% across ≥10 (session, file) combinations. Anthropic's published research found 43.8% as a quality-regression correlate.

**Scenario 17 — Self-admitted errors per 1K tool calls** — regex on assistant messages for self-correction phrases (`I apologize`, `you're right`, `actually that's`, `let me try`, `my mistake`, etc.). Normalize per 1K tool calls. Flag when rate > 5 per 1K.

**Scenario 18 — Low Read:Edit ratio** — per developer over the 7-day window, total Read calls / total Edit+Write calls. Flag when ratio < 4.0 across ≥20 edit calls. Anthropic's healthy baseline is 6.6; degraded sessions drop to 2.0.

**Scenario 19 — User frustration in prompt text** — regex on user follow-up prompts (not first prompts) for frustration markers (`that's wrong`, `no, don't`, `why did you`, `just do`, etc.). Flag when matching rate exceeds 2.5% of follow-up prompts.

Implementation skeletons in §5 of the brainstorm transcript (carried into implementation plan).

### 9.3 Detector interface (unchanged from Phase 0.5)

```python
@dataclass(frozen=True)
class Finding:
    scenario_id: str
    title: str
    bucket: str
    domain: str | None
    severity: str
    confidence: str
    evidence_md: str
    sample_session_paths: list[str]

class Detector(Protocol):
    id: str
    def __call__(self, events: pd.DataFrame, embeddings_fn: EmbeddingsFn, **ctx) -> Iterable[Finding]: ...
```

`**ctx` carries: `configured_domain`, `installed_skills`, `current_version`, `detector_overrides[scenario_id]`, `admin_metrics`, `chroma_collections`. CLI uses `inspect.signature` to pass only kwargs each detector accepts (Phase 0.5 pattern).

### 9.4 Detector tuning via `Config.detector_overrides`

Every threshold is overridable via JSON config:

```json
{
    "detector_overrides": {
        "scenario-16": {"min_total_edits": 10, "ratio_threshold": 0.30},
        "scenario-17": {"min_tool_calls": 100, "rate_threshold_per_1k": 5.0},
        "scenario-18": {"min_edits": 20, "healthy_ratio": 4.0, "degraded_ratio": 2.0},
        "scenario-19": {"min_prompts": 20, "min_match_rate": 0.025}
    }
}
```

Each detector reads `ctx.get("detector_overrides", {}).get(self.id, {})` and merges over its defaults.

## 10. Component 6 — Analyzer pipeline, rendering, auto-filing

### 10.1 Pipeline (single Python process, nightly)

```
1. Connect to events.sqlite, chroma\, insights.sqlite, admin_api_cache\
2. Build events DataFrame from last 7 days
3. Build admin DataFrame from admin_api_cache
4. INSERT INTO runs (started_at, sessions_seen)
5. For each detector in ALL_DETECTORS:
     - inspect.signature → pick matching ctx kwargs
     - call detector(events, embeddings_fn, **kwargs)
     - for each Finding:
         compute fingerprint, check past findings for cosine similarity > 0.92
         if recurrence: UPDATE past finding's occurrence_count, INSERT finding_recurrences row
         else: INSERT new finding with cluster_centroid + sample_snippets snapshot
6. Render Markdown files + HTML summary into analyzer-out\YYYY-MM-DD\
7. Auto-file Issues for findings matching auto-file criteria
8. UPDATE runs SET ended_at, findings_total
```

Estimated runtime at steady state: 2–5 minutes per nightly run.

### 10.2 Output structure

```
D:\ai-sherpa\analyzer-out\
  ├── 2026-06-15\
  │   ├── issues\NNN-<slug>.md     ← one per finding
  │   ├── summary.html              ← sortable table
  │   └── run-metadata.json         ← run_id, counts, timing
  └── latest → 2026-06-15\          ← junction always pointing at most recent
```

Last 30 days of dated folders kept; pruner deletes older.

### 10.3 Auto-filing gate

Findings auto-file as GH Issues only when **all three** are true:

| Criterion | Default | Why |
|---|---|---|
| `confidence >= auto_file_min_confidence` | high | Medium/low require human triage first |
| `contributing_developer_count >= auto_file_min_developers` | 2 | Single-dev pattern might be personal preference |
| Not previously filed (fingerprint dedup) | always | Prevent duplicate Issues |

Findings that don't auto-file still land in Markdown + HTML. Central team can manually file from there.

### 10.4 Issue body template

```
Title: [{bucket}] {title}
Labels: feedback, source:telemetry, type/{bucket}, domain/{domain},
        severity/{severity}, confidence/{confidence}, status/needs-review

## Suggested change
{evidence_md}

## Evidence summary
- Contributing sessions: {contributing_occurrence_count}
- Contributing developers: {contributing_developer_count}
- First detected: {first_seen_at}
- Last seen: {last_seen_at}
- Analyzer fingerprint: `{fingerprint[:12]}`

## Sample sessions
(sessions older than 7 days are no longer on the server but were captured at find-time)
- {sample_snippets[0]}
- {sample_snippets[1]}
- …
```

### 10.5 Re-detection of recurring findings

The key durability mechanism. On every new finding, compare `cluster_centroid_embedding` against `findings.cluster_centroid_embedding` for the same `scenario_id`. If cosine similarity > 0.92:
- This is a recurrence, not a new finding
- UPDATE past finding's `contributing_occurrence_count += 1`
- INSERT row into `finding_recurrences`
- Do NOT create a new finding or file a new Issue

Past Issues' evidence summaries update with each recurrence — central team sees "this pattern has recurred 12 times across 8 developers" without manual aggregation.

### 10.6 GitHub auth for auto-filing

Repo-scoped PAT stored in Windows Credential Manager under `ai-sherpa-gh-token`. Read by `gh` via `GH_TOKEN` env var at task startup. Rotation documented in `tools/auto-filer/README.md`.

### 10.7 Failure handling

| Failure | Behavior |
|---|---|
| One detector throws | Caught; logged into `runs.error_log_json`; other detectors continue |
| ChromaDB unreachable | Skip embedding-based detectors; tabular still run |
| Admin cache empty | Empty DataFrame; admin-dependent detectors degrade gracefully |
| GitHub auto-file fails | `issue_url` stays NULL; next run retries |
| events.sqlite corruption | Analyzer exits non-zero; rebuild from raw JSONL via `tools/rebuild-indexes.py` |

## 11. Central config

Single `Config` dataclass loaded once at process start. Every component gets the same instance.

```python
@dataclass
class Config:
    root: Path = Path(os.environ.get("AI_SHERPA_ROOT", r"D:\ai-sherpa"))

    # Path properties (sessions_dir, events_db, chroma_dir, etc.) computed from root

    # Retention
    session_retention_days: int = 7
    admin_api_retention_days: int = 365
    insights_retention_days: int | None = None
    output_retention_days: int = 30

    # Ingest
    ingest_host: str = "0.0.0.0"
    ingest_port: int = 8080
    require_auth: bool = False
    enable_transcripts: bool = True

    # Schedules
    admin_puller_time: str = "02:00"
    analyzer_run_time: str = "02:30"
    pruner_run_time: str = "03:00"

    # Admin API
    admin_api_credential_name: str = "ai-sherpa-admin-api"
    admin_api_backfill_days: int = 8

    # Detector tuning
    detector_overrides: dict = field(default_factory=dict)

    # Auto-file
    auto_file_min_confidence: str = "high"
    auto_file_min_developers: int = 2
    github_repo: str = "ccjain/AI-Sherpa-Setup"
    github_token_credential_name: str = "ai-sherpa-gh-token"

    # Output
    render_markdown: bool = True
    render_html: bool = True

    @classmethod
    def load(cls, path: Path | None = None) -> "Config": ...
```

Defaults match the design above. Override via `D:\ai-sherpa\config.json` (or `AI_SHERPA_CONFIG` env var).

## 12. Verification strategy

### 12.1 Local-testable pieces

Each detector has fixture-based tests (Phase 0.5 pattern). The four new detectors (16–19) ship with their own fixtures triggering exactly one finding each. The ingest service has integration tests pointing at a temp DB. The pruner has a dry-run mode.

### 12.2 Integration smoke test

`tools/phase2a-dry-run.sh` runs the analyzer against a fixture corpus, generates Markdown + HTML output to a temp dir, prints summary statistics. Used to validate changes without touching production data.

### 12.3 End-to-end fork test

Fork the AI Sherpa repo to a personal account; deploy the ingest service to a test VM; install collector on a single dev laptop; run the full pipeline for 7 days; verify Issues auto-file correctly and recurrences detect correctly. Documented runbook in `docs/phase2a-fork-runbook.md` (created during implementation).

## 13. Security & privacy

| Item | Posture |
|---|---|
| Network scope | Intranet only |
| Auth | None in v1 (intranet trust) |
| NDA / confidential projects | Skipped at collector via marker files |
| Consent | `Config.enable_transcripts` per-machine flag; flipping disables next sweep |
| At-rest encryption | Windows BitLocker on server volume |
| Access control | Windows file ACL on `D:\ai-sherpa\`; analyzer service account |
| Retention | 7-day rolling sessions; 1-year admin cache; insights forever (configurable) |
| Secrets | Windows Credential Manager via `keyring` for Admin API key + GitHub PAT |
| Auditability | `D:\ai-sherpa\logs\ingest.log` + `D:\ai-sherpa\logs\analyzer.log` |
| Privacy revocation | Flip `enable_transcripts` to false; one command to delete `sessions\` |

## 14. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Anthropic Admin API schema changes | Medium | Medium — puller breaks | Wrap field access in `admin_api.py` normalizer; on schema mismatch, log loud error, continue with empty admin DataFrame, detectors degrade gracefully |
| ChromaDB version-incompatible upgrade | Medium | Low — `chroma\` rebuildable | Pin `chromadb` version in `pyproject.toml`. `tools/rebuild-indexes.py` recreates from raw JSONL |
| 7-day session window misses long-tail recurring patterns | Low | Medium | Past finding centroids in `insights.sqlite` provide cross-window memory — same pattern in week 4 vs. week 1 still gets recognized |
| Auto-filing floods triage queue when a new detector goes live | Medium | High — central team overwhelmed | `auto_file_min_developers=2` gate + manual review of new detector's first week's findings before enabling auto-file. Each new detector ships with `auto_file=False` initially |
| Findings reference sessions that have been pruned | Always (by design) | None if snapshot is good; high if snapshot is incomplete | Snapshot 5 sample text excerpts + cluster centroid embedding + developer count + occurrence count at find-time. Sample paths gracefully show "session pruned" |
| Detector false-positive rate too high | Medium | High — central team loses trust | Three-tier confidence gate (§10.3). Phase 0.5's threshold-tuning experience carries over directly |
| Server fails (disk, OS, hardware) | Low | High — analysis pauses | Nightly robocopy mirror of `sessions\`, `admin_api_cache\`, `insights.sqlite` to a second drive. Indexes rebuild from those |
| Privacy posture changes (legal revokes approval) | Low | Critical — must stop transcript collection | Collector reads `enable_transcripts` flag from config on every run; flipping false stops uploads on the next sweep. Server-side `sessions\` deletion is one command |
| Cold tier insights grow unexpectedly fast | Low | Low | `insights_retention_days` knob lets us prune anything older than N years if it ever matters (won't at 7 MB/year) |

## 15. Decisions locked

| Decision | Choice |
|---|---|
| Org plan | Team/Enterprise (Admin API available) |
| Legal | Full transcripts approved |
| Approach | B — Phase 0.5 detectors + Phase 1.5 collection + sujankapadia indexing |
| Detection scope | 14 detectors (10 Phase 0.5 + 4 new lucemia-derived) |
| Output | Markdown + HTML + auto-file high-confidence Issues |
| Collection | Phase 1.5 reuse, full-JSONL payload |
| Server | Existing on-prem Windows |
| Storage tiers | Hot 7-day (rolling), warm 1-year (admin), cold forever (insights) |
| Auth v1 | None (intranet) |
| Auto-file gate | High confidence + ≥2 developers + fingerprint dedup |
| Re-detection | Centroid cosine > 0.92 → recurrence |
| Config | `Config` dataclass + JSON override file |
| Secrets | Windows Credential Manager via keyring |
| Schedules | 02:00 admin pull, 02:30 analyzer, 03:00 pruner |

## 16. Open implementer questions

Don't change architecture; they're knobs.

1. Admin API exact endpoint + response schema (confirm at implementation time).
2. Detector threshold defaults (start with §9.2 values; tune from first week of production data).
3. Auto-file `min_developers` default (proposed 2; consider 3 for tighter early signal).
4. Auto-file GitHub repo (confirm AI Sherpa repo vs. separate insights repo).
5. Snapshot sample size (proposed 5 text excerpts per finding).
6. ChromaDB persistent client vs. server mode (start persistent; migrate if concurrent access needed).
7. `insights_retention_days = None` vs. explicit ceiling (none recommended).
8. Run-history table granularity (proposed full row per detector per run).

## 17. Phase 2a → Phase 2b transition

Phase 2b (LLM-assisted) drops in as one step inside the analyzer pipeline:

```
... existing pipeline ...
   d. for each Finding produced:
        - compute fingerprint, check recurrence
        - if new finding AND confidence != "low":
             [PHASE 2B] call Claude API (Haiku) with cluster evidence
             ask for: refined title, PR-ready rule wording, unified diff
             attach to finding's evidence_md
```

No collection-side, detection-side, or schema changes. LLM polishes output; doesn't do analysis. Carries roadmap §12.9's reframe forward intact.
