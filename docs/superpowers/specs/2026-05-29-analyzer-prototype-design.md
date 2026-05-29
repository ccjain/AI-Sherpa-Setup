# Analyzer Prototype Design (Phase 0.5)

**Date:** 2026-05-29
**Status:** Spec (pre-implementation)
**Scope:** A standalone Python prototype that runs against locally-available Claude Code session JSONL files and produces candidate-change Issues as Markdown — validating the analyzer architecture before any collection or release infrastructure exists.

---

## 1. Goals

1. Prove that meaningful candidate-change Issues fall out of real Claude Code session data, before investing in collection plumbing (Phase 1.5) or full transcript ingest (Phase 2a).
2. Build the **detector interface** that the production analyzer will reuse — the code surface developed here is the basis of `server/analyzer/` when Phase 2a lights up.
3. Produce immediately readable output: one Markdown file per candidate finding plus a single HTML summary, viewable with no infrastructure.
4. Stay small enough to ship in a day so we get a fast feedback loop on the detection model.

## 2. Non-goals

- File real GitHub Issues. Output goes to local files only.
- Cross-engineer pattern detection (scenario 9, 15 from program roadmap §3). The local corpus is one developer's sessions; cross-engineer findings require multi-user data we don't have yet.
- LLM-based "explain the cluster" polishing (Phase 2b territory). Findings ship with deterministic template text.
- Persistence / incremental analysis. Every invocation re-analyzes all sessions from scratch.
- Production hardening: no rate limiting, no concurrency, no error retry. Crash-on-bad-input is acceptable.
- Privacy gating (NDA marker check). Local data only — no transmission.

## 3. Constraints & context

| Item | Value |
|---|---|
| Data source | Local `~/.claude/projects/**/*.jsonl` only |
| Audience | The AI Sherpa team — they read the output to validate the model |
| Output mode | Markdown files (one per finding) + a single HTML summary page |
| Scenario coverage | 10 of 15: tabular (3, 7, 8, 10, 11, 12, 13) + embedding (1, 2, 5) |
| LLM use | None |
| Stack | Python 3.11+, plain `pip install -e .` via `pyproject.toml` |
| Repo location | `analyzer-prototype/` at repo root, gitignored output dir |
| Cross-engineer scenarios | Out of scope (need multi-user data) |

## 4. Architecture

```
analyzer-prototype/                      experimental — productized at server/analyzer/ later
├── README.md                            quick-start
├── pyproject.toml                       deps: pandas, sentence-transformers, scikit-learn, jinja2
├── analyzer/
│   ├── __init__.py
│   ├── __main__.py                      enables `python -m analyzer`
│   ├── cli.py                           argparse: --input, --output, --scenarios, --since, --verbose
│   ├── ingest.py                        walk JSONL → events DataFrame
│   ├── embeddings.py                    lazy-load BAAI/bge-small-en-v1.5
│   ├── render.py                        findings → Markdown files + HTML summary
│   └── detectors/
│       ├── __init__.py                  exports an ordered list of detectors
│       ├── base.py                      Finding dataclass + Detector protocol
│       ├── tabular.py                   scenarios 3, 7, 8, 10, 11, 12, 13
│       └── embedding.py                 scenarios 1, 2, 5
├── tests/
│   ├── fixtures/                        synthetic JSONL files, one per scenario
│   ├── test_ingest.py
│   ├── test_tabular_detectors.py
│   └── test_embedding_detectors.py
└── analyzer-out/                        gitignored; created on each run
    ├── issues/                          NNN-<slug>.md per finding
    └── summary.html                     filterable single-page index
```

**Key principle:** Every detector is an independent function over the same `events` DataFrame. Adding scenario N+1 is one new file plus one line in `detectors/__init__.py`. The detector interface (§5) is the long-lived contract; everything else can change without breaking detectors.

## 5. Detector interface

```python
# analyzer/detectors/base.py
from dataclasses import dataclass
from typing import Protocol, Iterable, Callable
import pandas as pd
import numpy as np

@dataclass(frozen=True)
class Finding:
    scenario_id: str          # "scenario-7", etc. — matches roadmap §3 numbering
    title: str                # one-line headline for the Issue title
    bucket: str               # roadmap §12.2: "add-rule" | "refine-rule" | "skill-fix" |
                              #                "plugin-change" | "setup-fix" | "docs"
    domain: str | None        # "embedded" | "web" | … | None if cross-domain
    severity: str             # "critical" | "high" | "normal" | "low"
    confidence: str           # "high" | "medium" | "low"
    evidence_md: str          # Markdown body for the Issue (≥ one paragraph)
    sample_session_paths: list[str]   # absolute paths to source JSONL files

EmbeddingsFn = Callable[[list[str]], np.ndarray]

class Detector(Protocol):
    id: str                   # unique, e.g., "scenario-7"
    def __call__(
        self,
        events: pd.DataFrame,
        embeddings_fn: EmbeddingsFn,
    ) -> Iterable[Finding]: ...
```

The `events` DataFrame schema (built by `ingest.py`):

| Column | Type | Always present | Notes |
|---|---|---|---|
| `session_id` | str | yes | UUID from Claude Code |
| `session_path` | str | yes | Absolute path to source JSONL |
| `project_path_hash` | str | yes | SHA-256 of the project root path |
| `timestamp` | datetime64[ns, UTC] | yes | ISO 8601 from the message |
| `event_type` | str | yes | One of: `prompt`, `response`, `tool_call`, `tool_result`, `file_edit`, `skill_invoked`, `slash_command` |
| `text` | str | for prompt/response | Message text |
| `tool_name` | str | for tool_call | e.g., "Bash", "Read", "Edit" |
| `tool_args_json` | str | for tool_call | Tool input as JSON string |
| `tool_success` | bool | for tool_call | From subsequent tool_result |
| `command_first_word` | str | for Bash tool_call | First whitespace-delimited word of the command (e.g., "cat") |
| `file_extension` | str | for file_edit | e.g., ".py" |
| `skill_name` | str | for skill_invoked | e.g., "board-bringup" |
| `slash_command_name` | str | for slash_command | e.g., "/clear", "/restart" |
| `is_first_in_session` | bool | for prompt | True for the first user prompt in a session |

`embeddings_fn` is `lambda texts: ...` — pure function over a list of strings. Loaded lazily so tabular detectors that don't need embeddings don't pay the model download cost.

## 6. Sample detector implementations

### 6.1 Tabular — scenario 7 (tool misuse)

```python
# analyzer/detectors/tabular.py
from .base import Finding

def detect_tool_misuse(events, embeddings_fn=None):
    bash_calls = events[(events.event_type == "tool_call") & (events.tool_name == "Bash")]
    suspect = bash_calls[bash_calls.command_first_word.isin(["cat", "head", "tail", "grep"])]
    if len(suspect) < 5:
        return []

    by_cmd = suspect.groupby("command_first_word").agg(
        count=("session_id", "size"),
        sessions=("session_id", lambda s: s.unique().tolist()[:5]),
    )

    findings = []
    for cmd, row in by_cmd.iterrows():
        replacement = {"cat": "Read", "head": "Read", "tail": "Read", "grep": "Grep"}[cmd]
        findings.append(Finding(
            scenario_id="scenario-7",
            title=f"Tool misuse: Bash + {cmd} instead of {replacement}",
            bucket="add-rule",
            domain=None,
            severity="normal",
            confidence="high" if row["count"] >= 20 else "medium",
            evidence_md=(
                f"Across the analyzed corpus, `Bash {cmd}` was invoked **{row['count']} times**.\n\n"
                f"Each of these calls could have been handled by the `{replacement}` tool directly, "
                f"avoiding a shell escape and the associated permission prompt.\n\n"
                f"**Suggested change:** add a rule to `core/CLAUDE.md` discouraging `Bash {cmd}` when "
                f"the equivalent first-class tool exists."
            ),
            sample_session_paths=row["sessions"],
        ))
    return findings

detect_tool_misuse.id = "scenario-7"
```

### 6.2 Embedding — scenario 5 (repeated context-priming)

```python
# analyzer/detectors/embedding.py
from sklearn.cluster import HDBSCAN
from .base import Finding

def detect_repeated_priming(events, embeddings_fn):
    first_prompts = events[
        (events.event_type == "prompt") & (events.is_first_in_session == True)
    ]
    if len(first_prompts) < 10:
        return []

    texts = first_prompts.text.str.slice(0, 500).tolist()
    paths = first_prompts.session_path.tolist()
    embs = embeddings_fn(texts)

    labels = HDBSCAN(min_cluster_size=3, metric="cosine").fit_predict(embs)
    findings = []
    for label in set(labels) - {-1}:
        idxs = [i for i, l in enumerate(labels) if l == label]
        sample_text = texts[idxs[0]]
        sample_paths = [paths[i] for i in idxs[:5]]
        findings.append(Finding(
            scenario_id="scenario-5",
            title=f"Repeated session-opening prompt across {len(idxs)} sessions",
            bucket="add-rule",
            domain=None,
            severity="high" if len(idxs) >= 10 else "normal",
            confidence="high" if len(idxs) >= 5 else "medium",
            evidence_md=(
                f"**{len(idxs)} sessions** open with a near-identical prompt opening. "
                f"This is a strong signal that the content belongs in a CLAUDE.md rule or "
                f"a skill's `description:` instead of being re-typed each session.\n\n"
                f"**Sample opening (cluster centroid):**\n\n"
                f"```\n{sample_text[:400]}\n```\n\n"
                f"**Suggested change:** review the sample sessions, distill the recurring "
                f"context into a one-paragraph rule, and add it to the appropriate "
                f"`domains/<X>/CLAUDE.md` or `core/CLAUDE.md`."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_repeated_priming.id = "scenario-5"
```

The other 8 detectors follow the same shape — implementations are part of the implementation plan, not this spec.

## 7. Output format

### 7.1 Per-finding Markdown

Path: `analyzer-out/issues/{NNN}-{slug}.md` where `NNN` is a zero-padded counter (assigned in deterministic order: sort findings by severity desc, then scenario_id) and `slug` is the title kebab-cased and truncated.

Body shape:

```markdown
# [{bucket}] {title}

**Scenario:** {scenario_id} (see roadmap §3)
**Domain:** {domain or "any"}
**Severity:** {severity}
**Confidence:** {confidence}

## Suggested change

{evidence_md}

## Sample sessions

- `{absolute path 1}`
- `{absolute path 2}`
- …
```

### 7.2 HTML summary

`analyzer-out/summary.html` — single self-contained page rendered from a Jinja2 template. Columns: severity, scenario, domain, title, confidence, sample-count, link to Markdown file. Sortable via vanilla JS (`<table>` with `<th>` click handlers). No CDN dependencies — CSS inline, JS inline.

Header block at the top: total findings, breakdown by severity, breakdown by bucket, analysis timestamp, input path, number of sessions analyzed.

## 8. CLI surface

`python -m analyzer [flags]`

| Flag | Default | Meaning |
|---|---|---|
| `--input PATH` | `~/.claude/projects` | Root dir to walk for `*.jsonl` |
| `--output PATH` | `./analyzer-out` | Where to write Markdown + HTML |
| `--scenarios IDS` | `all` | Comma-separated scenario IDs to run (e.g., `scenario-5,scenario-7`) |
| `--since DATE` | (none) | Skip sessions older than this ISO date |
| `--verbose` | off | Per-detector progress + timing |

Examples:

```bash
python -m analyzer                                # all defaults
python -m analyzer --scenarios scenario-5         # just repeated priming
python -m analyzer --since 2026-04-01             # last ~2 months
python -m analyzer --input ./tests/fixtures --output /tmp/out --verbose
```

## 9. Verification approach

Three layers, all local:

1. **Unit tests per detector.** Each scenario has a fixture JSONL file in `tests/fixtures/` shaped to trigger exactly one finding. The test asserts the detector returns the expected finding (scenario_id, severity, sample_session_paths includes the fixture).
2. **Ingest tests.** `test_ingest.py` feeds a fixture file and asserts the resulting events DataFrame has expected columns and row counts.
3. **End-to-end smoke.** `python -m analyzer --input ./tests/fixtures --output /tmp/smoke` should produce a non-empty `summary.html` and at least one `issues/*.md` file without crashing.

No "gold output" comparison for findings — the prototype's job is to surface candidates for human review, not produce byte-exact output.

## 10. Decisions locked

| Decision | Choice |
|---|---|
| Scenario coverage | Tabular (3, 7, 8, 10, 11, 12, 13) + embedding (1, 2, 5) — 10 of 15 |
| Data source | `~/.claude/projects/**/*.jsonl` only |
| Output | Markdown files (one per finding) + single HTML summary |
| Repo location | `analyzer-prototype/` at repo root (NOT `server/analyzer/` — not productized yet) |
| Python stack | 3.11+, `pip install -e .` via `pyproject.toml`, no Poetry/uv |
| Embedding model | `BAAI/bge-small-en-v1.5` via `sentence-transformers` (CPU, ~100 MB) |
| Clustering | `scikit-learn` HDBSCAN with `min_cluster_size=3`, cosine metric |
| Templating | Jinja2 |
| LLM | None |
| Persistence | None — full re-analysis each run |
| Privacy gating | None — local data only |
| Cross-engineer scenarios (9, 15) | Out of scope |

## 11. Risks

| Risk | Mitigation |
|---|---|
| Local corpus too small to produce useful findings | Acceptable for v0 — output of zero findings is itself signal that detection thresholds need tuning. Re-run on teammates' machines later if needed. |
| Embedding model download fails on the implementer's machine | `sentence-transformers` caches under `~/.cache/huggingface/` and prints a clear error if blocked. Implementer can pre-download via `huggingface-cli`. |
| Detector code drifts from roadmap §3 scenario numbering | Each detector's `id` attribute is the contract. Tests assert scenario IDs explicitly. |
| Prototype code becomes load-bearing without productization review | Repo location `analyzer-prototype/` is explicit; README states "experimental, expect to be moved to `server/analyzer/`". |
| Sessions with very long prompts blow up embedding memory | Slice first 500 chars before embedding (in §6.2 example). Encoded into all embedding detectors. |
| HTML summary fails to render because Jinja2 not installed | `pyproject.toml` pins it as a hard dependency. Smoke test (§9.3) catches missing deps. |

## 12. Roadmap fit

This prototype slots in as **Phase 0.5** between "design committed" and the existing Phase 1. It does NOT replace any later phase:

| Phase | Status after this spec |
|---|---|
| **0.5 (new)** — Local-data analyzer prototype | This spec; implementation plan separately |
| 1 — Manual feedback | Spec + plan committed; execution deferred until 0.5 ships |
| 1.5 — Metadata telemetry | Unchanged |
| 2a — Full-transcript local analyzer | Unchanged; **inherits detector code from 0.5** |
| 2b — LLM-assisted analyzer | Unchanged |

Adds one line to roadmap §13 ("What's spec'd vs. what's not") and a sentence to §14 ("Next steps"). I'll update those in the implementation plan's final task.

## 13. Open questions for the implementer

These do not change architecture; they're knobs.

1. Threshold tuning per detector (e.g., scenario 7's "< 5 → no finding"). Defaults are starting points; tune via the smoke run.
2. Whether to bundle the HTML summary as a single self-contained file or split into `summary.html` + `summary.css` + `summary.js`. Default: single file for portability.
3. Whether the embedding model should be configurable via `--embedding-model`. Default: hard-coded `BAAI/bge-small-en-v1.5`.
4. Whether to print findings to stdout in `--verbose` mode in addition to writing them to disk. Default: just write to disk; stdout shows per-detector progress only.
