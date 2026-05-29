# Spike 1 — Anthropic native OTel export coverage

**Duration:** 3 working days.
**Owner:** TBA.
**Goal:** Determine whether Anthropic's native Claude Code OTel export carries enough content for the Scorer Registry to compute its detectors *as designed*, or whether we still need to ingest raw JSONL session files in parallel.

This is the highest-leverage spike. If OTel coverage is sufficient, the laptop side of the architecture collapses to "ship an OTel Collector config" and `filelogreceiver` becomes unnecessary. If coverage is partial, we accept a hybrid pipe.

## Prerequisites

- Access to the central team's Claude Code installations (≥ 3 machines).
- A scratch OTel Collector endpoint (a single-node Docker `otel/opentelemetry-collector-contrib` is sufficient; localhost is fine).
- Familiarity with Claude Code's OTel docs: `code.claude.com/docs/en/monitoring-usage`.
- Read access to the archived `2026-05-29-phase2a-design.md` detector list (for the coverage-check checklist).

## Steps

1. **(½ day)** Enable Claude Code's native OTel export on 3 central-team machines. Configure to point at the scratch Collector. Document any setup friction.
2. **(2 days, in background)** Let the central team use Claude Code normally for 2 working days. Capture all emitted spans, logs, and metrics to a flat JSONL dump for offline analysis.
3. **(½ day)** Build a coverage matrix: rows = detectors from `analyzer-prototype/` + the lifted-from-`lucemia` metric set (`generic_metrics.py` plan, v2 §5.9), columns = required input fields. For each cell, mark: `present in OTel`, `derivable from OTel`, `absent — needs JSONL`.

Concrete fields to check (non-exhaustive — extend during the run):

- Tool name + outcome (success / failure) per call
- User prompt text (or hash, if text is absent)
- Assistant response text (or hash)
- File path read / edited (relative; check for PII exposure)
- Token counts (input / output)
- Hook firings (PreToolUse, PostToolUse, SessionStart, SessionEnd) and which rule (if any) caused a block
- Session ID + parent session relationship for `/clear` loops
- MCP server names invoked
- Skill names invoked

## Exit criteria

A 1-page coverage matrix committed at `docs/superpowers/spikes/2026-05-30-gate-a/spike-1-results.md` with:

- The matrix itself, populated.
- A one-sentence verdict per detector: covered / partial / not covered.
- A one-paragraph recommendation: OTel only, OTel + JSONL, or JSONL only.
- A list of 3 spans/events that would be most valuable additions if Anthropic were willing to extend the OTel emission (forms the basis of any upstream PR or feature request).

## Kill criterion

If fewer than 50% of detectors can be computed from OTel alone OR from OTel+derivation, the Scorer Registry must be re-scoped before Gate B planning starts. Escalate to the program owner before committing the row to the Gate A decision matrix.

## Output (Gate A decision-matrix row)

| Spike | Outcome (one sentence) | Confidence | Affects | Decision |
|---|---|---|---|---|
| 1 — Anthropic OTel | *e.g. "OTel covers 9 of 14 detectors; the 5 missing all need raw prompt text."* | high / medium / low | Scorer Registry input shape | adopt OTel only / adopt OTel + JSONL / fall back to JSONL only |
