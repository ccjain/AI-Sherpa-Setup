# AI Sherpa Feedback & Learning Program — Requirements Summary

**Date:** 2026-05-29
**Audience:** AI Sherpa team, engineering management, central platform team
**Purpose:** Single shareable doc capturing what we're building, who it's for, the use cases it serves, and where detailed specs live.

---

## 1. Executive summary

AI Sherpa is the company's pre-configured Claude Code environment, deployed to ~150 developers across 10+ domains (embedded, web, data, devops, marketing, sales, finance, etc.). Today it ships **rules** (`CLAUDE.md` per domain), **plugins**, **skills**, and a **setup pipeline**. The rules need to keep improving as we learn what works and what doesn't.

This program adds a **closed-loop feedback and learning system** so AI Sherpa improves itself continuously:

- **Developers** can report problems with one keystroke (`/ai-sherpa-feedback`)
- **The system itself** observes real Claude sessions and auto-detects patterns (e.g., "this rule isn't firing", "engineers keep correcting Claude the same way")
- **The AI Sherpa team** triages both channels through a single GitHub workflow and ships weekly improvements
- **All developers** automatically receive the updates via a brief release email and one `setup --update` command

Built and rolled out in 4 phases. **Phase 0.5 is shipped** (a working analyzer prototype validated against real session data). Phases 1, 2a, and 2b are fully designed and planned but not yet implemented.

---

## 2. The problem

Three observations drive everything in this program:

1. **AI Sherpa rules are static, but the work isn't.** Domain rules need to evolve as the team learns. Today there's no systematic way to capture that learning and feed it back.
2. **Engineers don't notice when Claude is wrong.** Our developers are domain experts (firmware, web, finance, etc.) but not AI-native. They accept plausible-looking Claude suggestions and move on. Most "Claude got it wrong" moments are silent — not surfaced, not reported, not learned from.
3. **A single manual feedback channel can't see everything.** Engineers reliably notice and report the **explicit** failures (5–10/week from 150 devs at most). The **silent** failures — same correction repeated across sessions, missing context-priming, rules that should have fired but didn't — only surface from telemetry analysis. We need both channels.

---

## 3. Who this is for

| Stakeholder | Role | What this gives them |
|---|---|---|
| **Individual developers** (~150) | Daily users of Claude Code via AI Sherpa | A one-keystroke feedback path (`/ai-sherpa-feedback`) + automatic weekly updates with no friction |
| **Central AI Sherpa team** (3–5 people) | Maintain and ship AI Sherpa | A single GitHub triage queue (manual + auto-detected feedback) + weekly release Action |
| **Domain leads** | Subject-matter experts (embedded lead, web lead, etc.) | Auto-routed Issues for their domain via labels |
| **Engineering management** | Oversight + budget | Org-level metrics (acceptance rate, DAU, session counts) via Anthropic's Admin API + an optional one-page weekly KPI digest |
| **InfoSec / legal** | Compliance | A bounded data model: 7-day rolling sessions, NDA-flagged projects skipped, intranet-only collection |

---

## 4. Use cases

### UC1 — Developer reports a Claude mistake (Phase 1)

**Trigger:** Mid-session, the developer notices Claude suggested something wrong for their domain (e.g., `malloc` inside an ISR in embedded firmware).

**Flow:**
1. Developer types `/ai-sherpa-feedback`.
2. The skill auto-collects environment context (AI Sherpa version, OS, active plugins, recent file extensions, domain).
3. Asks four short questions (what did you ask, what did Claude do, what should it have done, which rule was violated if known).
4. Shows the assembled Issue body for review (developer can redact anything).
5. Files a structured GitHub Issue via the developer's own `gh` auth.

**Result:** A labeled Issue in the AI Sherpa repo within ~45 seconds. Total developer effort: typing ~80 words.

### UC2 — System detects a pattern from telemetry (Phase 2a)

**Trigger:** Across the org, 6 embedded developers each had a session where Claude suggested `malloc` in an ISR context. No one filed feedback (silent failure).

**Flow:**
1. Each session is captured by the collector running on dev laptops (only after the developer opts in; NDA projects always skipped).
2. The on-prem server analyzer runs nightly. It detects a cluster: "scenario-17 (self-admitted errors) fired in 14 sessions where context includes ISR-related terms."
3. The analyzer files a GitHub Issue with the evidence (sample sessions, contributing developer count, severity).
4. Optionally (Phase 2b): the LLM drafts paste-ready rule wording and a unified diff for the suggested CLAUDE.md change.

**Result:** A candidate-change Issue lands in the same triage queue as manual feedback, indistinguishable in workflow but tagged `source:telemetry`.

### UC3 — Central team triages and ships a release (Phase 1)

**Trigger:** It's Friday morning. The triage queue has ~12 new Issues since last week (mix of manual + auto-detected).

**Flow:**
1. Triage meeting (30 min). Each Issue gets:
   - **Approve** → labeled `status/approved`; a PR follows
   - **Reject** → closed with a comment
   - **Duplicate** → linked and closed
2. Approved Issues become PRs with `Closes #N` and a `release-note` label.
3. PRs merge throughout the week.
4. **Monday morning** (cron-scheduled), the release Action:
   - Tags a new release (`v2026.06.01` — calendar-versioned)
   - Generates release notes from merged-PR descriptions, grouped by domain
   - Creates a GitHub Release
   - Sends an email via Google Apps Script to `ai-sherpa-announce@<org>` Google Group

### UC4 — Developer gets the update (Phase 1)

**Trigger:** Developer reads the Monday email.

**Flow:**
1. Email subject: "AI Sherpa v2026.06.01 — 7 fixes across 4 domains."
2. Email body shows highlights and the update command for their platform.
3. Developer runs `setup.bat --update` (Windows) or `bash setup.sh --update`.
4. Setup script pulls latest, refreshes plugins, and prints "Was: v2026.05.25 → Now: v2026.06.01" + cumulative highlights since their last update.

**Result:** The new rules are active in their next Claude session. No restart, no extra steps.

### UC5 — Manager reviews org-level metrics (Phase 2a)

**Trigger:** Monthly review. Engineering manager wants to see Claude Code adoption and rule effectiveness across the org.

**Flow:**
1. Open the analyzer's HTML summary at `\\ai-sherpa-srv\analyzer-out\latest\summary.html`.
2. See:
   - Number of active developers, sessions per domain, daily/weekly trends
   - Top candidate changes filed this month, with confidence levels
   - Acceptance rate trend per domain (from Anthropic's Admin API)
   - Cost per developer per month (Admin API)
3. (Optional, Phase 2b) Cost report: `py -m server.analyzer.cost_report --window-days 30` prints the LLM API spend.

**Result:** A single page of metrics that didn't require building a custom dashboard.

### UC6 — New developer joins the team

**Trigger:** New hire starts on the embedded team.

**Flow:**
1. They clone the AI Sherpa repo and run `setup.bat` (picks `embedded` domain).
2. The setup script installs Claude Code (if missing), the embedded plugin set, the `/ai-sherpa-feedback` skill, and (if telemetry enabled) the upload collector.
3. They start using Claude Code normally. Their sessions count toward the team's telemetry (with their consent).
4. As patterns surface from their (and others') usage, AI Sherpa improves; they receive the same weekly emails.

**Result:** Zero-friction onboarding. No special training; no manual rule submission required.

### UC7 — InfoSec audit of telemetry collection

**Trigger:** Quarterly InfoSec review of any system collecting developer data.

**Auditor checks:**
- Data inventory: what's collected? (Full session JSONL, but 7-day rolling retention only.)
- Privacy gates: how are NDA projects excluded? (`NDA.md` / `CONFIDENTIAL.md` markers checked at collector before upload.)
- Network scope: where can the data reach? (Intranet only; on-prem Windows server; no public endpoint.)
- Access control: who can see the data? (Windows file ACL; analyzer service account.)
- Right to delete: can a developer's data be purged? (Yes — one SQL DELETE + filesystem rm.)
- Consent: how do developers opt in/out? (`Config.enable_transcripts` per-machine flag; setup-time prompt.)
- LLM data flow (Phase 2b): does data leave the org? (Sanitized finding summaries only — never raw sessions, never session IDs or developer names; cost capped at ~$5/week.)

**Result:** Full audit answers in one read of the program specs.

---

## 5. Functional requirements

### 5.1 Feedback intake

**FR-1** A developer must be able to file structured feedback from inside Claude Code with one slash command (`/ai-sherpa-feedback`).
**FR-2** The intake must auto-collect environment context (AI Sherpa version, OS, plugins, skills, project markers) so the developer only answers business-logic questions.
**FR-3** The developer must review and approve the assembled Issue body before submission. NEVER auto-submit.
**FR-4** A fallback path exists for non-Claude-Code submission (GitHub Issue form with the same fields).

### 5.2 Telemetry collection (Phase 2a only)

**FR-5** Per-laptop collector uploads session JSONL files to the on-prem server via HTTP POST on session end (and hourly catch-up sweep).
**FR-6** NDA-flagged projects (containing `NDA.md`, `CONFIDENTIAL.md`, or `.ai-sherpa-noupload`) are skipped at the collector — never leave the dev's machine.
**FR-7** Sessions older than 7 days are pruned from the server. Insights derived from them stay forever.
**FR-8** A developer can flip a config flag (`enable_transcripts: false`) to stop their machine from uploading; takes effect next sweep.

### 5.3 Detection

**FR-9** The system detects at least 14 silent-failure patterns (10 from the Phase 0.5 prototype + 4 from published Anthropic research):
- Skill should have fired but didn't
- Same correction repeated across sessions
- Domain mismatch (file extensions vs configured domain)
- Repeated context-priming
- Tool misuse (`Bash + cat` instead of `Read`)
- Session abandonment / `/clear` loops
- Accept-then-revert edit episodes
- Plugin/skill ROI (low fire rate)
- Onboarding velocity baseline
- Stale install version
- **Edits without prior Read** (Anthropic-research baseline: 43.8% correlates with quality regression)
- **Self-admitted errors per 1K tool calls** ("I apologize", "you're right", "let me try")
- **Low Read:Edit ratio** (Anthropic baseline: 6.6 healthy, ~2.0 degraded)
- **User frustration in prompt text** ("that's wrong", "why did you", "just do")

**FR-10** Each finding maps to one of 6 candidate-change types: add rule, refine rule, update skill description, add/remove plugin, fix setup, update docs.
**FR-11** The system recognizes recurring patterns via cluster centroid similarity — does not re-file Issues for the same underlying problem.

### 5.4 Triage and release

**FR-12** Both manual and auto-detected Issues land in the same GitHub triage queue, distinguished only by `source:manual` vs `source:telemetry` labels.
**FR-13** The system supports a label taxonomy of `status/*`, `domain/*`, `type/*`, `severity/*`, `confidence/*`, `source/*` per the Phase 1 spec.
**FR-14** A weekly cron-scheduled GitHub Action discovers merged PRs with the `release-note` label, generates a calendar-versioned release (`vYYYY.MM.DD`), and creates a GitHub Release with grouped notes.
**FR-15** The Action sends a notification email via a Google Apps Script Web App to `ai-sherpa-announce@<org>` Google Group on every successful release.

### 5.5 Auto-filing (Phase 2a)

**FR-16** Only findings meeting all three criteria auto-file as Issues:
- Confidence ≥ `auto_file_min_confidence` (default: high)
- Contributing developers ≥ `auto_file_min_developers` (default: 2)
- Not previously filed for this fingerprint
**FR-17** Findings that don't auto-file are still rendered to Markdown + HTML for human review.

### 5.6 LLM polish (Phase 2b, optional, opt-in)

**FR-18** For each new finding above a confidence threshold, the system optionally calls Claude API to produce: refined title, target file path, rule wording, unified diff, and a one-sentence reviewer rationale.
**FR-19** LLM polish is OFF by default (`Config.llm_enabled=False`).
**FR-20** Hard cost ceiling enforced via per-run call count and input-token budget. Any LLM failure ships the finding without polish.

---

## 6. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-1 | **Scale** | Support ~150 developers × ~10 sessions/day at steady state. |
| NFR-2 | **Storage** | Hot tier ≤ 5 GB; warm tier ≤ 100 MB; cold tier ≤ 10 MB/year. On a 1 TB on-prem server, fits comfortably for 10+ years. |
| NFR-3 | **Cost** | Phase 1 ingest: zero ongoing API cost. Phase 2a: zero LLM cost. Phase 2b: ≤ ~$5/week target. |
| NFR-4 | **Privacy** | NDA-flagged projects never leave the dev's machine. Sanitization strips emails, UUIDs, paths from LLM calls. Per-dev consent flag. |
| NFR-5 | **Network** | Intranet only in v1; no public endpoint, no off-network laptops. (v2 path documented; not in scope.) |
| NFR-6 | **Reliability** | Collector tolerates network failures and laptops being offline; retries with exponential backoff. Analyzer continues if one detector throws. |
| NFR-7 | **Audit** | Every ingest request and LLM call logged (timestamp, source IP, machine_id, bytes — no payload contents). |
| NFR-8 | **Recoverability** | All indexes rebuildable from raw JSONL via `tools/rebuild-indexes.py`. |
| NFR-9 | **Config** | Every threshold, retention window, schedule, and gate is configurable via `config.json`. No recompile needed. |
| NFR-10 | **Cadence** | Weekly release rhythm. Triage on Fridays; ship on Mondays. |

---

## 7. Solution at a glance — the 4-phase plan

| Phase | Status | What | When |
|---|---|---|---|
| **0.5 — Analyzer prototype** | **✅ Shipped** | Standalone Python prototype validating the detector model against local Claude session data. 10 detectors, 21 tests, real-data smoke produced 12 meaningful findings. | Done |
| **1 — Manual feedback pipeline** | Designed, planned, ready | `/ai-sherpa-feedback` skill, GH Issue form, triage labels + Project board, weekly release Action, email notification, `setup --update` improvements. | ~2–3 weeks to implement |
| **2a — Multi-developer telemetry + auto-analyzer** | Designed, planned, ready | On-device collector + on-prem ingest service + 14 detectors + auto-filing into the Phase 1 triage queue + Anthropic Admin API integration. | ~4 weeks to implement |
| **2b — LLM-assisted polish** | Designed, planned, ready | Optional Claude API step inside the analyzer pipeline that drafts PR-ready rule wording + unified diff. Opt-in. | ~1 week additional |

**Phase 1.5 was eliminated** from the original plan. It was originally going to be a metadata-only telemetry layer. With Anthropic's Admin API providing those per-developer structured metrics directly, the separate phase became redundant. Phase 2a absorbs that scope.

---

## 8. Deliverables — what each phase produces

### Phase 1 (manual feedback) ships:

- `/ai-sherpa-feedback` slash command in Claude Code (PowerShell + Bash helpers)
- `.github/labels.yml` — full label taxonomy applied via a one-shot Action
- `.github/ISSUE_TEMPLATE/feedback.yml` — structured Issue form (same fields as the slash command)
- `.github/pull_request_template.md` — enforces release-note convention
- `.github/workflows/release.yml` — weekly cron release Action
- `.github/workflows/auto-label-released.yml` — applies `status/released` on Issue close
- `tools/mailer/mailer.gs` — Google Apps Script Web App for email sending
- `scripts/generate-release-notes.sh` — assembles release notes from merged PRs
- `VERSION` file + `--update` improvements in `setup.bat` / `setup.sh` / `setup.ps1`
- Updated `docs/feedback-guide.md` + `docs/user-guide.md`
- A `docs/phase1-fork-runbook.md` for end-to-end testing

### Phase 2a (multi-dev analyzer) ships:

- `server/` Python package on the on-prem Windows server with:
  - FastAPI ingest service (`POST /v1/sessions/{id}`)
  - SQLite FTS5 indexed `events.sqlite`
  - ChromaDB persistent embeddings
  - Anthropic Admin API daily puller
  - 14 detectors (10 carried from Phase 0.5 + 4 new from Anthropic research)
  - Analyzer pipeline with recurrence detection
  - Markdown + HTML rendering
  - Auto-filer (`gh issue create`) with confidence + developer gates
  - Daily pruner
- `client-agent/collector/upload.ps1` — laptop-side uploader with NDA gate
- `setup.bat --enable-telemetry` flag and helpers
- NSSM service install + Task Scheduler scripts
- `tools/phase2a-dry-run.ps1` + `tools/rebuild-indexes.py`
- `docs/phase2a-fork-runbook.md`

### Phase 2b (LLM polish) ships:

- `server/analyzer/llm_draft.py` — `LlmDraft` dataclass + `Budget` class + `draft_polish` + sanitization
- 9 nullable columns added to `findings`, 3 to `runs`
- `server/analyzer/cost_report.py` — CLI for weekly LLM spend monitoring
- Renderer + auto-filer updates to display LLM-drafted sections when present

---

## 9. Risks & mitigations (high level)

| Risk | Mitigation |
|---|---|
| **Auto-filer floods triage queue** when a new detector goes live | High-confidence + ≥2 developer gates; new detectors ship with `auto_file=False` until verified |
| **Analyzer false positives** waste triage time | Three-tier confidence gate; new detectors validated on Phase 0.5 prototype against real data before promotion |
| **Anthropic Admin API schema changes** break the puller | Normalizer wraps field access; falls back to empty DataFrame on schema mismatch |
| **Server failure** loses recent sessions | Nightly mirror of raw JSONL + admin_api_cache to a second drive; indexes rebuildable |
| **Developers feel surveilled** and disable telemetry | Default-off until consented; `setup --telemetry-status` shows exactly what was sent; per-dev opt-out one-command |
| **LLM costs spiral** | Hard per-run cap (calls + tokens); weekly cost-report CLI; opt-in default |
| **Privacy posture changes** (legal revokes consent) | Single config flag stops uploads; one-command server data deletion |

---

## 10. Rollout timeline (rough)

| Week | Activity |
|---|---|
| Week 0 (now) | Team reviews this requirements summary + the detailed specs |
| Week 1 | Phase 0 manual setup for Phase 1 (Google Group, Apps Script deploy, GitHub Project board) |
| Weeks 2–4 | Implement Phase 1; ship to pilot users |
| Weeks 5–8 | Implement Phase 2a in parallel with Phase 1 stabilization. On-prem server setup. Collector pilot with central team's own machines first. |
| Week 9 | Phase 2a goes org-wide (opt-in initially, then default-on after 2 weeks of clean ops) |
| Weeks 10–11 | Evaluate Phase 2b: review Phase 2a's first month of Issues; decide if LLM polish is worth the budget |
| Week 12+ | Phase 2b opt-in (if approved) |

These are estimates; the actual cadence depends on team availability and any rework discovered during reviews.

---

## 11. Where to find the detailed specs

All living in `docs/superpowers/` in the AI Sherpa repo:

| Doc | Purpose |
|---|---|
| `specs/2026-05-28-feedback-program-roadmap.md` | One-page strategic map across all phases (start here for context) |
| `specs/2026-05-28-feedback-release-pipeline-design.md` | Phase 1 design |
| `plans/2026-05-29-phase1-feedback-release-pipeline.md` | Phase 1 task-by-task implementation plan |
| `specs/2026-05-29-analyzer-prototype-design.md` | Phase 0.5 design |
| `plans/2026-05-29-analyzer-prototype.md` | Phase 0.5 implementation plan (already executed; reference only) |
| `specs/2026-05-29-phase2a-design.md` | Phase 2a design |
| `plans/2026-05-29-phase2a.md` | Phase 2a task-by-task implementation plan |
| `specs/2026-05-29-phase2b-design.md` | Phase 2b design |
| `plans/2026-05-29-phase2b.md` | Phase 2b task-by-task implementation plan |
| `research/2026-05-29-oss-claude-session-tools-comparison.md` | Why we adopted patterns from `lucemia/claude-session-analyzer` and `sujankapadia/claude-code-analytics` |

The actual Phase 0.5 prototype code is at `analyzer-prototype/` (merged into master).

---

## 12. What we want from this review

- **Anything missing** from the requirements or use cases?
- **Anything overcommitted** that we should descope?
- **Anyone we haven't considered** in the stakeholder list?
- **Implementation priority** — Phase 1 first, Phase 2a first, or both in parallel?
- **Concerns** about privacy, cost, scale, or operational burden we should address before starting implementation?

Reply or raise issues directly on the relevant spec/plan docs.
