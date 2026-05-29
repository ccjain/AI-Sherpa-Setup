# OSS Claude Code Session Tools — Comparison & Adoption Recommendations

**Date:** 2026-05-29
**Status:** Research / analysis
**Context:** Phase 0.5 analyzer prototype shipped and validated against local data. Before scoping Phase 2a, evaluate two closest OSS analogs identified in research: `lucemia/claude-session-analyzer` and `sujankapadia/claude-code-analytics`. Decide what to adopt vs. build.

---

## 1. Executive summary

The two repos cover **complementary** ground; neither replaces our Phase 0.5 prototype, but each contributes patterns worth adopting:

- **`lucemia/claude-session-analyzer`** has the **analysis logic** we want — a behavioral-signal taxonomy from published Anthropic research that includes frustration indicators, Read:Edit ratio, self-corrections, and reasoning loops. It lacks infrastructure (no dashboard, no capture pipeline, no team aggregation).
- **`sujankapadia/claude-code-analytics`** has the **infrastructure** we want — automatic SessionEnd-hook capture, SQLite FTS5 indexing, ChromaDB embeddings, a React dashboard. It lacks the rules-improvement focus and AI Sherpa-specific candidate-change framing.
- **Our AI Sherpa differentiator** — turning analyzer findings into PR-ready candidate changes filed back to the AI Sherpa repo — is in neither tool. That stays our value-add.

**Recommendation:** Don't fork either tool. Adopt the **detection taxonomy** from lucemia and the **capture + storage architecture** from sujankapadia. Keep the candidate-change-Issue rendering as our unique layer. This sharpens Phase 1.5 and Phase 2a designs substantially.

---

## 2. Tool deep-dives

### 2.1 `lucemia/claude-session-analyzer`

**Source:** https://github.com/lucemia/claude-session-analyzer
**License:** MIT · **Status:** Nascent (3 commits, 8 stars, no releases) · **Language:** Python 3.7+, **zero deps beyond stdlib**

**What it extracts (5 categories of metrics, all from local `~/.claude/projects/`):**

| Category | Specific signals |
|---|---|
| **Thinking depth** | Redaction rate, signature-length proxy, Pearson correlation, time-of-day variation |
| **Tool usage** | **Read:Edit ratio**, Research:Mutation ratio, Write % of mutations, **edits-without-prior-Read %**, repeated edits |
| **Behavioral signals** | Reasoning loops, "simplest fix" mentions, premature stopping, **self-admitted errors per 1K tool calls** |
| **User experience** | **Frustration indicators**, user interrupts, **positive:negative sentiment ratio**, word frequency |
| **Cost** | Token usage, API request counts, daily cost trend, cost per prompt |

**Methodology lineage:** Replicates analysis published by Stella Laurenzo (Anthropic, April 2026). Two concrete claims from that work:
- *"Thinking content redaction correlated precisely with quality regression"*
- *"43.8% of edits were made to files the model hadn't read"*

**Output:** Markdown reports (`session-analysis-{date}.md`). One file per analysis run.

**Architecture:** Single-file `analyze_sessions.py`. No plugin/detector modularity in the README. Distributed as a standalone script, a Claude Code plugin (via GitHub install), or a manual slash-command setup.

**What's missing for our use case:**
- Single-user; no team aggregation
- No dashboard (Markdown only)
- No candidate-change Issue rendering
- No detector plugin architecture (our `Detector` protocol is more extensible)
- Early-stage project; not safe to depend on long-term

### 2.2 `sujankapadia/claude-code-analytics`

**Source:** https://github.com/sujankapadia/claude-code-analytics
**License:** MIT (presumed) · **Status:** Alpha v0.1.0 (Dec 30, 2025); 217 commits, 8 stars, active development · **Language:** 64% Python, 32% TypeScript, 3% Shell

**Capture mechanism:** *"Automatically captures every conversation when you exit Claude Code"* via a **SessionEnd hook** — directly validating the design pattern we chose for Phase 1.5 §11.3.

**What it does:**
- Hook-based session capture with dual-format storage (JSONL + readable text)
- File watcher imports new sessions into SQLite as they appear
- Token tracking + cost monitoring per session
- Tool usage analytics (MCP server stats, distribution charts)
- LLM-powered content analysis via OpenRouter / Google Gemini (300+ models, pre-built and custom analysis types)
- Hybrid search: **SQLite FTS5 + ChromaDB embeddings + LLM query expansion**, combined with Reciprocal Rank Fusion
- Session similarity search ("find related sessions") via embeddings
- Daily activity trends + temporal patterns

**Architecture:**
- Frontend: React SPA with virtual scrolling, command palette (⌘K), dark mode
- Backend: Python API server (localhost:8000)
- Storage: SQLite with FTS5 indexing
- Embeddings: ChromaDB (open-source vector DB)
- Real-time UI updates: Server-Sent Events
- Auto-import: file watcher on `~/.claude/projects/`

**Distribution:** Git clone + `./install.sh`. No npm/pip/Docker packaging. Self-hosted single-machine.

**What's missing for our use case:**
- Single-user (config at `~/.config/claude-code-analytics/.env`); no team rollup
- LLM dependency for content analysis (cost + API key)
- Doesn't produce candidate-change Issues for a target repo
- Heavy install (React build + Python server) makes it a lot to operate compared to our `python -m analyzer`

---

## 3. Side-by-side comparison

| Dimension | Phase 0.5 prototype (us) | claude-session-analyzer (lucemia) | claude-code-analytics (sujankapadia) |
|---|---|---|---|
| Language | Python 3.11 | Python 3.7 | Python + TS |
| Dependencies | pandas, sentence-transformers, sklearn, jinja2 | **stdlib only** | sklearn, sqlite-fts5, ChromaDB, React, OpenRouter SDK |
| Capture | Manual (`python -m analyzer`) | Manual run | **Automatic via SessionEnd hook + file watcher** |
| Storage | None (re-parse JSONL each run) | None (re-parse) | **SQLite FTS5 + ChromaDB** |
| Detection model | 10 silent-failure scenarios, modular `Detector` protocol | 5 categories of metrics, one file | Activity metrics + LLM-driven custom analysis |
| Behavioral signal taxonomy | Limited (scenarios 7, 8, 10) | **Strong — Read:Edit, self-corrections, frustration, premature stopping** | Limited (counts and trends) |
| Output | Markdown files + HTML summary | Markdown report | React dashboard (live) |
| Embeddings | Local `bge-small-en-v1.5` (free) | None | ChromaDB + LLM (paid API) |
| LLM dependency | None in v0 | None | **Required** for content analysis (OpenRouter/Gemini) |
| Multi-user / team | No (Phase 1.5+) | No | No |
| Candidate-change Issues | **Yes (our differentiator)** | No | No |
| Project status | Just shipped Phase 0.5 | 3 commits, dormant | 217 commits, active alpha |
| Distribution | `pip install -e .` | Plugin / script / slash command | Git clone + install.sh |

---

## 4. What we adopt — concrete recommendations

### 4.1 Adopt the behavioral signal taxonomy from `lucemia/claude-session-analyzer`

Our current detector set has 7 tabular + 3 embedding-based scenarios. Several of lucemia's signals are stronger versions of what our scenarios approximate:

| lucemia signal | Maps to / strengthens our scenario | Action |
|---|---|---|
| **Read:Edit ratio** | scenario-7 (tool misuse) is weaker | Add `detect_low_read_edit_ratio` as a new detector — fires when a session's Edit count >> Read count (suggests blind editing) |
| **Edits-without-prior-Read %** | Closest to scenario-10 (accept-then-revert) but a different signal | Add as a new detector — Anthropic's research found 43.8%, this is a strong correlate of quality regression |
| **Self-admitted errors per 1K tool calls** | We don't have anything like this | Add as a new detector. Regex on assistant messages for "I apologize", "you're right", "let me try", "actually that's wrong" |
| **Frustration indicators** + sentiment ratio | scenario-8 (abandonment) is structural; this is content-based | Combine: scenario-8 fires on structural signal, new `detect_user_frustration_text` fires on prompt sentiment |
| **Premature stopping** | We don't have it | Could be added later; needs more session structure analysis |
| **Reasoning loops** | We don't have it | Detect: same tool called with same args 3+ times in a session |

**Recommended priority:** add `detect_edits_without_prior_read` and `detect_self_admitted_errors` first. Both are simple to implement (no embeddings needed) and both have direct Anthropic-research backing for their signal strength.

These would land as Tasks 10–11 in a future Phase 0.5 extension OR as part of Phase 2a's detector set.

### 4.2 Adopt the capture + storage architecture from `sujankapadia/claude-code-analytics` for Phase 1.5

Our Phase 1.5 design in roadmap §11 prescribes:
- SessionEnd hook + Task Scheduler sweep
- HTTP POST to on-prem FastAPI ingest
- SQLite for ingest dedup

The sujankapadia repo validates this design and adds two refinements worth incorporating:

1. **File watcher in addition to the hook.** When the hook misses (session crash, terminal kill), the watcher catches new JSONLs as they appear. Our hourly sweep does this same job; their file watcher is real-time. For Phase 1.5, hourly is fine; for Phase 2a we may want real-time.

2. **SQLite FTS5 indexing.** Our analyzer re-parses JSONL on every run. At 150 devs × N sessions/day, this won't scale. Indexing into SQLite with FTS5 (full-text search) at ingest time means the analyzer can query a database, not walk a filesystem. Major perf win.

3. **ChromaDB for cluster persistence.** Right now scenario-5 re-computes embeddings on every run. With ChromaDB, embeddings persist; only new sessions get embedded. For 150 devs this matters.

**Recommended for Phase 1.5/2a:** ingest writes session JSONL + extracts events into SQLite FTS5 + adds embeddings of first-prompts to ChromaDB. The analyzer queries these stores instead of re-parsing files.

### 4.3 Do NOT fork either repo

Forking creates a hard maintenance burden. Both are early-stage, single-maintainer projects. Lifting specific patterns (signal definitions, hook config, FTS5 schema) is a smaller, more controlled commitment.

**One specific exception worth considering:** if the central AI Sherpa team is also a heavy user of session analytics, `sujankapadia/claude-code-analytics` could be installed alongside as a personal-productivity tool — same `~/.claude/projects/` reads, no interference with our analyzer.

### 4.4 What stays uniquely ours

| Capability | Status in others | Our advantage |
|---|---|---|
| Candidate-change Issues filed to AI Sherpa repo | Neither tool does this | This IS the rules-improvement loop — Phase 1 spec convergence point |
| Detector protocol (`Finding`, `Detector`) | lucemia: monolithic; sujankapadia: not detector-shaped | Adding a new scenario = one file, one line in the registry |
| Multi-developer aggregation | Neither | Phase 1.5/2a design is built for this from the start |
| Confidence tiers + auto-filing rules | Neither | Roadmap §5 three-tier confidence gate |

---

## 5. What this means for the roadmap

Three concrete edits worth making after this research:

**Edit 1 — Roadmap §3 (silent-failure table)**
Add four new scenarios drawn from lucemia's taxonomy. Each maps to existing candidate-change buckets:

| # | Scenario | Detection method | Data | Bucket |
|---|---|---|---|---|
| 16 | **Edits without prior Read** | Per session, count Edit calls where the same file_path had no preceding Read. Flag if ratio > 30% across multiple sessions. | T | #1 rule |
| 17 | **Self-admitted errors** | Regex on assistant messages for apology / correction phrases. Per 1K tool calls. | T | #2 refine rule |
| 18 | **Low Read:Edit ratio** | Per session, Read count / Edit count. Flag chronic low values. | M (tool counts only) | #1 rule |
| 19 | **User frustration text** | Sentiment + frustration phrases in user prompts. Per session frequency. | T | #1 rule / #3 skill |

**Edit 2 — Roadmap §11 (collection mechanism)**
Add §11.4.1 mentioning the file-watcher alternative to hook-only capture (for v2). Add §11.5.1 mentioning SQLite FTS5 indexing at ingest time. Add §11.5.2 mentioning ChromaDB for persistent embeddings.

**Edit 3 — Roadmap §13 (what's spec'd)**
Add a "Reference implementations studied" row pointing to this comparison doc.

---

## 6. Action items

In priority order:

1. **Apply roadmap edits 1–3** (this doc → roadmap link-up). Small commit.
2. **Add `detect_edits_without_prior_read`** and **`detect_self_admitted_errors`** to the analyzer prototype as Phase 0.5+ extensions. Two new detectors, ~2 hours each. Test on the same 44-session corpus.
3. **Decide on the prototype's terminal state:** ship as-is to master vs. keep iterating. The OSS findings don't change the deliverable, just inform the next phase.
4. **Update Phase 1.5 spec** (when written) to incorporate FTS5 + ChromaDB patterns and to cite sujankapadia as the architectural reference.

---

## 7. Open questions

- Is there value in opening an upstream PR to `lucemia/claude-session-analyzer` to align its signal naming with ours? Probably premature; the project is dormant.
- If the central AI Sherpa team uses sujankapadia's dashboard personally, do their findings inform our triage? Worth piloting with one team member.
- Does Anthropic's official Team Analytics Admin API (separate research thread) overlap with these tools? If yes, **the org-level metric collection layer of Phase 1.5 may not need to be built at all** — we'd write the analyzer to consume the Admin API instead of our own ingest. That's a major scope reduction worth dedicated investigation.
