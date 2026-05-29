> **ARCHIVED 2026-05-30.** Superseded by [docs/superpowers/2026-05-30-program-v2.md](../../2026-05-30-program-v2.md).
> Preserved for historical context. Not authoritative. Do not cite.

# Phase 2b — LLM-Assisted Analyzer Design

**Date:** 2026-05-29
**Status:** Spec (pre-implementation)
**Scope:** One additional step inside the Phase 2a analyzer pipeline: for each new finding (not recurrences) above a configurable confidence threshold, call Claude API once with the finding's evidence and ask for PR-ready rule wording, unified-diff snippet, and a one-sentence reviewer rationale. Attach to the finding before rendering / auto-filing.

---

## 1. Goals

1. Reduce central-team triage friction by shipping each candidate-change Issue with **PR-ready text** — a specific rule wording and a paste-ready unified diff — rather than just "consider adding a rule about X."
2. Stay surgical: **the LLM doesn't do analysis**; it converts existing analyzer output into reviewer-friendly prose. All detection is unchanged from Phase 2a.
3. Hard cost ceiling: ≤ ~$5/week at steady state for 150-dev org. Achieved via cheap-model default (Haiku), top-N candidates per run, aggressive prompt caching, and recurrences-skip.
4. Graceful degradation: if Claude API is unreachable, over-budget, or returns malformed output, the finding still ships — just without the LLM polish layer.
5. Zero schema-breaking change: adds nullable columns to `findings`; old findings without LLM polish remain renderable.

## 2. Non-goals

- Replacing or modifying any of the 14 detectors.
- LLM-driven new-pattern detection (would be a Phase 2c).
- Multi-turn LLM conversations or agentic loops.
- Streaming or interactive UI.
- Local LLM as the primary path (Path 2 in §6 is documented but not v1 default).
- Ground-truth fine-tuning of the LLM on past findings (out of scope; future work).
- Sending raw session JSONL to the LLM. The LLM sees only the **finding's evidence summary**, sanitized.

## 3. Constraints & context

| Item | Value |
|---|---|
| LLM provider (v1) | Anthropic Claude API |
| Default model | `claude-haiku-4-5` (cheapest member of current frontier family) |
| API key location | Windows Credential Manager, separate from Admin API key |
| Trigger | Inside `pipeline.py` at find-time, after recurrence check, before insight insert |
| Network | The Claude API call **does** leave the corporate LAN. NDA sessions never reach this point (filtered at collector) |
| Data leaving | Finding's `title`, `bucket`, `evidence_md`, up to 5 sample-text snippets, scenario_id. No session_id, no developer name, no file paths (sanitized) |
| Cost cap | `Config.llm_max_calls_per_run` (default 20) and `Config.llm_max_input_tokens_per_run` (default 100_000) — hard ceilings |
| Confidence gate | LLM only invoked for findings with `confidence != "low"` |
| Recurrence gate | LLM never invoked on recurrences (the past finding already has its polish) |
| Fallback | Any LLM failure → log, persist finding without polish, proceed normally |

## 4. Architecture — where Phase 2b drops in

```
Phase 2a pipeline.py (unchanged through step 5.c):

   5.d for each Finding produced:
        - compute fingerprint
        - check recurrence in insights.sqlite
        - if recurrence:
            increment_recurrence(); continue
        - else:                                          ┐
            [NEW IN 2B] if confidence != "low" AND       │
                        llm_calls_this_run < max:        │
                draft = llm_draft_polish(finding)       ├─ This is Phase 2b
                if draft: attach to finding              │
            insert_finding(...) with draft cols          ┘
        - render (unchanged)
        - auto_file (unchanged; uses drafted body if present)
```

No collection-side, ingest-side, detector-side, storage-schema (other than nullable columns), or auto-filer changes. **One new module, one new column-set, one new helper called from one existing line.**

## 5. Component — `server/analyzer/llm_draft.py`

A single Python module that exports `draft_polish(finding: Finding, cfg: Config, budget: Budget) -> LlmDraft | None`.

### 5.1 `LlmDraft` data shape

```python
@dataclass(frozen=True)
class LlmDraft:
    refined_title: str            # 1-line, ≤ 70 chars
    target_file: str              # e.g., "core/CLAUDE.md" or "domains/embedded/CLAUDE.md"
    rule_wording: str             # 1-2 paragraphs in Markdown
    unified_diff: str             # paste-ready git diff
    rationale: str                # 1-sentence reviewer summary
    model: str                    # e.g., "claude-haiku-4-5"
    input_tokens: int
    output_tokens: int
    drafted_at: str               # ISO 8601 UTC
```

### 5.2 Sanitization before sending

Even though the central team approves transcript collection, the **LLM call should never see**:
- Raw session paths (replace with `<session_N>`)
- Developer usernames (replace with `<dev_N>`)
- Raw transcript content beyond what the detector explicitly chose to surface in `evidence_md`

`sanitize_finding_for_llm(finding) -> dict` does this scrub. Implementation in §5.5.

### 5.3 The prompt

Single system + user prompt. System prompt is **static** (enables Anthropic prompt caching with ~$0 marginal cost on cache hit). User prompt carries the finding-specific payload.

**System prompt** (cached; ~500 tokens):

```
You are the AI Sherpa rules editor. Your job is to convert an analyzer
finding into a PR-ready change to the AI Sherpa repo.

The AI Sherpa repo contains CLAUDE.md files that guide Claude Code's
behavior across a 150-developer organization:
  - core/CLAUDE.md — rules for all developers
  - domains/<X>/CLAUDE.md — domain-specific rules (embedded, web, data,
    devops, marketing, sales, finance, service, procurement, uiux)
  - skills/<X>/SKILL.md — skill metadata (description field triggers
    auto-activation)
  - plugins.json — plugin install list
  - setup.bat / setup.sh / setup.ps1 — install scripts

Given a finding, produce a JSON object with these fields:
  refined_title    — 1 line, ≤70 chars, action-oriented
  target_file      — the specific file path to edit
  rule_wording     — the new/refined rule, Markdown, 1-2 paragraphs
  unified_diff     — paste-ready git diff against the target file
  rationale        — 1 sentence explaining why this change addresses the finding

Rules:
- Keep diffs minimal — only the new/changed lines
- Match the existing CLAUDE.md style (numbered lists, bold for keywords)
- Don't invent file paths — pick from the list above
- If the finding is unclear or trivially auto-fixable, say so in rationale and
  produce a minimal diff
- Output VALID JSON only, no prose before or after
```

**User prompt** (per-finding; ~500-2000 tokens):

```
Scenario: {scenario_id}
Bucket: {bucket}
Severity: {severity}
Confidence: {confidence}
Title: {title}

Evidence (Markdown):
{evidence_md}

Sample snippets (sanitized):
{sample_snippets_json}

Produce the JSON object as specified.
```

### 5.4 Parsing & validation

The response **must** be valid JSON matching `LlmDraft` shape. Validation:
- All 5 string fields non-empty
- `target_file` matches a known path pattern (`core/CLAUDE.md`, `domains/*/CLAUDE.md`, `skills/*/SKILL.md`, `plugins.json`, `setup.bat`, `setup.sh`, `setup.ps1`, `docs/*.md`)
- `unified_diff` starts with `--- ` or `diff --git`
- `refined_title` ≤ 70 chars
- Total response ≤ 4000 tokens

Validation failure → fallback to None (finding ships without polish).

### 5.5 Implementation skeleton

```python
# server/analyzer/llm_draft.py
from __future__ import annotations
import datetime
import json
import re
from dataclasses import dataclass
from typing import Iterable
from server.config import Config
from server.analyzer.detectors.base import Finding


@dataclass(frozen=True)
class LlmDraft:
    refined_title: str
    target_file: str
    rule_wording: str
    unified_diff: str
    rationale: str
    model: str
    input_tokens: int
    output_tokens: int
    drafted_at: str


class Budget:
    """Tracks per-run LLM cost ceilings."""
    def __init__(self, cfg: Config):
        self.calls_remaining = cfg.llm_max_calls_per_run
        self.input_tokens_remaining = cfg.llm_max_input_tokens_per_run

    def can_call(self, est_input_tokens: int) -> bool:
        return (self.calls_remaining > 0 and
                self.input_tokens_remaining >= est_input_tokens)

    def record(self, input_tokens: int) -> None:
        self.calls_remaining -= 1
        self.input_tokens_remaining -= input_tokens


_SYSTEM_PROMPT = """[as above]"""

_TARGET_FILE_PATTERN = re.compile(
    r"^(core/CLAUDE\.md|domains/[a-z]+/CLAUDE\.md|skills/[a-z0-9-]+/SKILL\.md|"
    r"plugins\.json|setup\.(bat|sh|ps1)|docs/[a-z0-9-]+\.md)$"
)


def sanitize_finding_for_llm(finding: Finding) -> dict:
    """Strip developer names, file paths, session IDs from a finding."""
    import json as _j
    return {
        "scenario_id": finding.scenario_id,
        "bucket": finding.bucket,
        "severity": finding.severity,
        "confidence": finding.confidence,
        "title": finding.title,
        "evidence_md": _scrub_text(finding.evidence_md),
        "sample_snippets_json": _j.dumps([{"path": "<session_N>"}
                                          for _ in finding.sample_session_paths[:5]]),
    }


def _scrub_text(text: str) -> str:
    """Replace likely PII patterns with placeholders."""
    if not text:
        return ""
    # Replace email addresses
    text = re.sub(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b", "<email>", text)
    # Replace UUID-like session IDs
    text = re.sub(r"\b[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\b",
                  "<session_id>", text)
    # Replace Windows absolute paths
    text = re.sub(r"[A-Z]:\\[^\s]+", "<path>", text)
    # Replace Unix absolute paths to ~/.claude or /tmp
    text = re.sub(r"(/(?:home|Users|tmp)/[^\s]+)", "<path>", text)
    return text


def draft_polish(finding: Finding, cfg: Config, budget: Budget) -> LlmDraft | None:
    """Call Claude API to draft PR-ready polish. Returns None on any failure."""
    if not budget.can_call(est_input_tokens=2000):
        return None
    try:
        return _call_anthropic(finding, cfg, budget)
    except Exception:
        return None


def _call_anthropic(finding: Finding, cfg: Config, budget: Budget) -> LlmDraft | None:
    import keyring
    from anthropic import Anthropic
    api_key = keyring.get_password(cfg.llm_api_credential_name, "default")
    if not api_key:
        return None

    sanitized = sanitize_finding_for_llm(finding)
    user_prompt = (
        f"Scenario: {sanitized['scenario_id']}\n"
        f"Bucket: {sanitized['bucket']}\n"
        f"Severity: {sanitized['severity']}\n"
        f"Confidence: {sanitized['confidence']}\n"
        f"Title: {sanitized['title']}\n\n"
        f"Evidence (Markdown):\n{sanitized['evidence_md']}\n\n"
        f"Sample snippets (sanitized):\n{sanitized['sample_snippets_json']}\n\n"
        f"Produce the JSON object as specified."
    )

    client = Anthropic(api_key=api_key)
    resp = client.messages.create(
        model=cfg.llm_model,
        max_tokens=2000,
        system=[{
            "type": "text",
            "text": _SYSTEM_PROMPT,
            "cache_control": {"type": "ephemeral"},   # Anthropic prompt caching
        }],
        messages=[{"role": "user", "content": user_prompt}],
    )

    body = resp.content[0].text if resp.content else ""
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        return None

    if not _validate_response(parsed):
        return None

    draft = LlmDraft(
        refined_title=parsed["refined_title"],
        target_file=parsed["target_file"],
        rule_wording=parsed["rule_wording"],
        unified_diff=parsed["unified_diff"],
        rationale=parsed["rationale"],
        model=cfg.llm_model,
        input_tokens=resp.usage.input_tokens,
        output_tokens=resp.usage.output_tokens,
        drafted_at=datetime.datetime.utcnow().isoformat(),
    )
    budget.record(resp.usage.input_tokens)
    return draft


def _validate_response(parsed: dict) -> bool:
    required = ("refined_title", "target_file", "rule_wording", "unified_diff", "rationale")
    if not all(k in parsed and isinstance(parsed[k], str) and parsed[k].strip() for k in required):
        return False
    if not _TARGET_FILE_PATTERN.match(parsed["target_file"]):
        return False
    if len(parsed["refined_title"]) > 70:
        return False
    if not (parsed["unified_diff"].startswith("--- ") or parsed["unified_diff"].startswith("diff --git")):
        return False
    return True
```

## 6. Two LLM paths

### Path 1 — Anthropic Claude API (recommended v1)

- Default model: `claude-haiku-4-5`
- Cost estimate: ~10 input tokens/sec × 2000 tokens × 20 calls/run × 7 runs/week × $0.25/M = **~$0.70/week**. Caching the system prompt drops actual cost ~50%.
- Configurable upgrade to `claude-sonnet-4-6` or `claude-opus-4-7` per `Config.llm_model` if Haiku output quality is insufficient.
- Same Admin API budget separately; this draws from a different rate-limit pool.

### Path 2 — Local open-source LLM (optional)

If data locality is a hard constraint or budget is zero:

- Replace `_call_anthropic` with `_call_local_llm` using vLLM or llama.cpp serving a 7-8B model (Llama 3.1 8B, Qwen 2.5 7B).
- Slower per-call (~10-30s vs ~1-2s), lower output quality but functional.
- Requires GPU on the on-prem server, or accept very slow CPU inference (~5 min/call).
- Switched via `Config.llm_provider = "local"` and a corresponding `_call_local_llm` implementation.

Path 2 is documented but not the v1 default.

## 7. Storage — additions to `findings` table

Five new **nullable** columns appended to the existing schema:

```sql
ALTER TABLE findings ADD COLUMN llm_drafted_at TEXT;
ALTER TABLE findings ADD COLUMN llm_model TEXT;
ALTER TABLE findings ADD COLUMN llm_refined_title TEXT;
ALTER TABLE findings ADD COLUMN llm_target_file TEXT;
ALTER TABLE findings ADD COLUMN llm_rule_wording TEXT;
ALTER TABLE findings ADD COLUMN llm_unified_diff TEXT;
ALTER TABLE findings ADD COLUMN llm_rationale TEXT;
ALTER TABLE findings ADD COLUMN llm_input_tokens INTEGER;
ALTER TABLE findings ADD COLUMN llm_output_tokens INTEGER;
```

Findings without polish keep all `llm_*` columns NULL. Renderer and auto-filer handle either case (§8).

Migration script in Task 1 of the Phase 2b implementation plan.

## 8. Rendering & auto-filing behavior

### 8.1 Renderer

If a finding has `llm_refined_title`, prefer it for the Markdown `<h1>`. If `llm_rule_wording` exists, include it under a new section "## Drafted change". If `llm_unified_diff` exists, include it under "## Drafted diff" in a fenced ` ```diff ` code block.

Original `evidence_md` always present under "## Evidence" — the LLM's polish complements, never replaces, the analyzer's evidence.

### 8.2 Auto-filer

Issue title prefers `llm_refined_title` if present. Issue body includes a new section near the top:

```markdown
## Drafted change (LLM-assisted)

> **Target file:** `{llm_target_file}`
> **Rationale:** {llm_rationale}

### Proposed rule wording

{llm_rule_wording}

### Paste-ready diff

```diff
{llm_unified_diff}
```

---

## Evidence (analyzer-generated)

{evidence_md}
```

When `llm_*` columns are NULL, the auto-filer falls back to the Phase 2a body shape verbatim.

## 9. Cost monitoring

Aggregate per-run totals exposed via the `runs` table — add three columns:

```sql
ALTER TABLE runs ADD COLUMN llm_calls_total INTEGER DEFAULT 0;
ALTER TABLE runs ADD COLUMN llm_input_tokens_total INTEGER DEFAULT 0;
ALTER TABLE runs ADD COLUMN llm_output_tokens_total INTEGER DEFAULT 0;
```

Pipeline updates these at the end of each run. A small CLI command (`py -m server.analyzer.cost_report`) sums totals over the last 30 days and prints an estimated dollar figure, so the central team can verify budget compliance.

## 10. Failure modes & mitigations

| Failure | Behavior |
|---|---|
| Claude API key missing in Credential Manager | LLM step skipped silently; `runs.error_log_json` records "llm_key_missing"; findings ship without polish |
| Claude API returns 429 (rate limit) | Caught, finding ships without polish, logged. No retry within same run. |
| Claude API returns 5xx | Same as 429 — skip and log |
| Response is malformed JSON | Validation fails, finding ships without polish |
| Response is valid JSON but fails `_validate_response` (e.g., target_file outside allowlist) | Skip; log "llm_validation_failed" |
| Budget exhausted mid-run | Subsequent findings skip the LLM step; logged via per-finding `llm_skipped_reason` (added to runs error log) |
| Output exceeds 4000 tokens | Truncated; validation likely fails; finding ships without polish |
| Local LLM (Path 2) crashes | Same fallback path |

## 11. Privacy & security

- API key in Windows Credential Manager under `Config.llm_api_credential_name` (default `ai-sherpa-llm-api`). Separate from Admin API key.
- Sanitization (§5.2 + `_scrub_text`) strips emails, UUIDs, absolute paths from `evidence_md` before sending.
- The LLM only receives a single finding at a time; no cross-finding aggregation. The model never sees session IDs, developer names, or raw transcript content beyond what the detectors explicitly chose to include in `evidence_md`.
- Outbound HTTPS only to `api.anthropic.com`. Firewall rule on the on-prem server allows just that destination.
- Audit log entry per LLM call: `(run_id, finding_id, model, input_tokens, output_tokens, sanitized=true)`. No payload bodies logged.

## 12. Config additions

```python
# Added to server/config.py Config dataclass
llm_provider: str = "anthropic"          # "anthropic" | "local"
llm_model: str = "claude-haiku-4-5"      # Anthropic model id
llm_api_credential_name: str = "ai-sherpa-llm-api"
llm_max_calls_per_run: int = 20
llm_max_input_tokens_per_run: int = 100_000
llm_min_confidence: str = "medium"       # only LLM-polish high|medium; skip low
llm_enabled: bool = False                # gate the whole feature; default OFF
```

`llm_enabled` defaults to **False** — Phase 2b is opt-in even after deployment, so the team can flip it on with one config change and roll back without touching code.

## 13. Verification strategy

### 13.1 Unit tests

- `sanitize_finding_for_llm` strips emails / UUIDs / paths
- `_validate_response` accepts well-formed, rejects malformed
- `Budget` enforces both call-count and token-count ceilings
- `draft_polish` returns None when API call mocked to fail

### 13.2 Mocked integration

- Pipeline with `llm_enabled=True` + mocked `_call_anthropic` returning a canned LlmDraft → finding gets `llm_*` columns populated
- Pipeline with `llm_enabled=False` → no `llm_*` columns populated even if mock available

### 13.3 Live smoke (manual)

One-time: dispatch a real call to `claude-haiku-4-5` with a fixture finding, eyeball the response. Confirm: valid JSON, plausible diff, target_file in allowlist, total tokens < 2500.

### 13.4 Cost regression test

After 1 week of production runs, sum `runs.llm_*_tokens_total`; verify weekly cost is ≤ $5. If not, tune `llm_max_calls_per_run` down.

## 14. Decisions locked

| Decision | Choice |
|---|---|
| LLM provider | Anthropic Claude API (Path 1) |
| Default model | `claude-haiku-4-5` |
| Cost ceiling | 20 calls/run × 100K input tokens/run; ≤ ~$5/week target |
| Recurrence gate | LLM never invoked on recurrences (past finding has its polish) |
| Confidence gate | LLM only invoked for confidence != "low" (configurable) |
| Sanitization | Strip emails, UUIDs, absolute paths before sending |
| Default state | `llm_enabled=False` — opt-in after deployment |
| Storage | 9 new nullable columns on `findings`, 3 new on `runs`. Existing rows unaffected. |
| Fallback | Any failure → ship finding without LLM polish; never block pipeline |
| Audit | Per-call entry in `runs.error_log_json` for cost / failures |
| Path 2 (local LLM) | Documented but not v1 default |

## 15. Open implementer questions

These don't change architecture; they're knobs.

1. **Exact Anthropic model ID** at implementation time — defaults change as Anthropic releases new versions. Pin via `Config.llm_model` rather than hard-coding.
2. **Prompt iteration** — the system prompt in §5.3 will need 2-3 rounds of tuning after live data. Start with what's in §5.3; iterate based on Issue review feedback from the central team.
3. **Whether to cache `target_file` lookups** — if many findings target `core/CLAUDE.md` simultaneously, batching could shave cost further. Defer optimization until cost monitoring shows it matters.
4. **Top-N selection** — if a run produces >20 candidate findings (above `llm_max_calls_per_run`), which 20 get polish? Recommended: sort by `severity` desc then `confidence` desc, take top 20. Documented as an implementer note in the plan.
5. **Whether to retry once on 429** — current spec says "no retry within same run". Could change to "1 retry after 30s wait" if cost stays within budget.

## 16. Phase 2b → future transition

Phase 2c (if it happens) would add LLM-driven **new pattern detection** — not polish, but actual finding production. That would require:
- A new "candidate-pattern" detector that uses the LLM as judge
- Adversarial verification (multiple LLM calls per candidate)
- A larger cost ceiling
- A separate review queue with stricter confidence gates

Out of scope for Phase 2b. Phase 2b ships as documented; Phase 2c is hypothetical until / unless central team requests it after seeing 2b output for several months.
