# Gate A — spike playbooks (week 0–1)

Gate A is the program's first conditional transition. Three short investigations run in parallel and converge on a one-page decision matrix that determines the shape of Phase 1 commitments and the feasibility of Gate E. See `docs/superpowers/2026-05-30-program-v2.md` §2 and §4.

The three spikes:

| # | Playbook | Duration | Owner (TBA) | What it decides |
|---|---|---|---|---|
| 1 | [`spike-1-anthropic-otel.md`](spike-1-anthropic-otel.md) | 3 working days | TBA | Whether Anthropic's native OTel export covers enough content for the Scorer Registry, or whether we need a parallel JSONL ingest pipe. |
| 2 | [`spike-2-admin-api.md`](spike-2-admin-api.md) | 3 working days | TBA | Whether the Anthropic Admin API delivers the org-level acceptance / sessions / cost metrics we assumed, with confirmed schema. |
| 3 | [`spike-3-infra-capability.md`](spike-3-infra-capability.md) | 1 working day | TBA (ops) | Whether we self-host Langfuse + ClickHouse on the existing Windows server (with Docker) or stand up a Linux VM beside it. |

## Hard rules

- The three spikes run **in parallel**. None blocks the others.
- Each spike is **time-boxed**. If a spike runs over by more than 50%, escalate, do not extend.
- Each spike outputs a single row in the Gate A decision matrix (template below). The matrix is the only artifact that matters; the working notes are reference.
- Spike work must NOT mutate production state. Investigations are read-only except in dedicated test repos / forks.

## Gate A exit criteria

Gate A closes when:

1. All three spike playbooks have been executed and their decision-matrix rows are filled in.
2. The central team has met to read the matrix and assign each row a colour (green / amber / red).
3. The kill criterion (§4 Gate A) is evaluated: if both OTel coverage AND Admin API are red, the Scorer Registry approach is re-scoped before Gate B starts.

## Decision-matrix template

To be filled in at the close-out meeting. One row per spike.

| Spike | Outcome (one sentence) | Confidence | Affects | Decision |
|---|---|---|---|---|
| 1 — Anthropic OTel | | high / medium / low | Scorer Registry input shape | adopt OTel only / adopt OTel + JSONL / fall back to JSONL only |
| 2 — Admin API | | high / medium / low | Org-level metrics tier | adopt as-is / wrap with normalizer / abandon and use Langfuse-derived metrics |
| 3 — Infra | | n/a | Server hosting model | host on Windows + Docker / stand up Linux VM / accept managed Langfuse Cloud |

The filled matrix is committed to `docs/superpowers/spikes/2026-05-30-gate-a/decision-matrix.md` in the same close-out commit and is referenced by Gate B planning.
