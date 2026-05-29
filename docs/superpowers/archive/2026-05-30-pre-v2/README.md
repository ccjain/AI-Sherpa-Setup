# Archive — 2026-05-30 pre-v2 program docs

The documents in this directory are the AI Sherpa Feedback & Learning Program
specs, plans, and stakeholder summary that were authored 2026-05-28 through
2026-05-29 and superseded on 2026-05-30 by the v2 program brief.

**Live program brief:** [`../../2026-05-30-program-v2.md`](../../2026-05-30-program-v2.md)

## Why these are archived

A cross-cutting architectural review and four parallel OSS-landscape investigations
(2026-05-29 → 2026-05-30) concluded that the original program plan was ~80%
reinvention of existing open-source infrastructure (Langfuse, OpenTelemetry
Collector, GitHub-native release tooling) and ~20% genuinely-novel work that
was under-scoped. The v2 brief restructures the program around adoption of the
existing stack, with the narrower build job (per-rule effectiveness scoring)
sized appropriately.

The detailed reasoning lives in:
- `../../2026-05-30-program-v2.md` (the brief)
- `../../2026-05-29-architect-review-analysis.md` (the review)

## Policy

- Docs here are **reference-only**. Do not cite as current.
- Do not edit them to "fix" them. They are historical artifacts; rewriting them erases the lesson.
- New work derived from these ideas belongs in a fresh doc under `../../specs/` or `../../plans/`, not here.
- Inter-archive links may have rotted from the move; that's acceptable for archived material.
- If a code-review-graph indexes markdown, this directory should be excluded so semantic search doesn't surface stale recommendations.

## What's in this archive

| File | Original location | Role in v1 |
|---|---|---|
| `2026-05-28-feedback-program-roadmap.md` | `specs/` | Program-level roadmap across all phases |
| `2026-05-28-feedback-release-pipeline-design.md` | `specs/` | Phase 1 design |
| `2026-05-29-phase1-feedback-release-pipeline.md` | `plans/` | Phase 1 task-by-task implementation plan |
| `2026-05-29-phase2a-design.md` | `specs/` | Phase 2a design |
| `2026-05-29-phase2a.md` | `plans/` | Phase 2a task-by-task implementation plan |
| `2026-05-29-phase2b-design.md` | `specs/` | Phase 2b (LLM polish) design |
| `2026-05-29-phase2b.md` | `plans/` | Phase 2b task-by-task implementation plan |
| `2026-05-29-program-requirements-summary.md` | `docs/superpowers/` | Stakeholder-facing summary; rewrite pending against v2 |

## What is NOT archived (still authoritative)

- `../../specs/2026-05-29-analyzer-prototype-design.md` — documents the Phase 0.5 prototype, which shipped and runs
- `../../plans/2026-05-29-analyzer-prototype.md` — same
- `../../research/2026-05-29-oss-claude-session-tools-comparison.md` — the original OSS research; will be superseded by a 2026-05-30 expansion (pending)
- The Phase 0.5 prototype code itself (currently `analyzer-prototype/` in the repo root; renamed to `tools/local-session-analyzer/` per v2 §5.9)
