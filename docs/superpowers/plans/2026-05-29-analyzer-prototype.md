# Analyzer Prototype Implementation Plan (Phase 0.5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Python prototype that reads local Claude Code session JSONL, detects 10 of the 15 silent-failure scenarios from the roadmap, and writes candidate-change Issues as Markdown files plus a single HTML summary — all with zero infrastructure.

**Architecture:** A `python -m analyzer` package with a tiny pluggable detector interface (`Finding` dataclass + `Detector` protocol). Tabular detectors run pandas/SQL over an events DataFrame; embedding detectors run `sentence-transformers` + scikit-learn HDBSCAN over local prompt text. No LLM, no server, no GitHub Issue filing. Output lives under `./analyzer-out/`.

**Tech Stack:** Python 3.11+, pandas, sentence-transformers (`BAAI/bge-small-en-v1.5`), scikit-learn (HDBSCAN), Jinja2, pytest. Plain `pip install -e .` via `pyproject.toml`.

**Spec:** `docs/superpowers/specs/2026-05-29-analyzer-prototype-design.md` (commit `87fda61`).

---

## File structure overview

| Path | New / Modify | Responsibility | First touched in |
|---|---|---|---|
| `analyzer-prototype/pyproject.toml` | new | Package metadata + deps | Task 1 |
| `analyzer-prototype/README.md` | new | Quick-start, what this is | Task 1 |
| `analyzer-prototype/.gitignore` | new | Ignore `analyzer-out/`, `__pycache__/`, etc. | Task 1 |
| `analyzer-prototype/analyzer/__init__.py` | new | Marks package | Task 1 |
| `analyzer-prototype/analyzer/__main__.py` | new | `python -m analyzer` entry point | Task 1 |
| `analyzer-prototype/analyzer/detectors/__init__.py` | new | Ordered list of detectors | Task 1 |
| `analyzer-prototype/analyzer/detectors/base.py` | new | `Finding` dataclass + `Detector` protocol | Task 1 |
| `analyzer-prototype/analyzer/ingest.py` | new | Walk JSONL → events DataFrame | Task 2 |
| `analyzer-prototype/analyzer/detectors/tabular.py` | new | Scenarios 3, 7, 8, 10, 11, 12, 13 | Task 3 |
| `analyzer-prototype/analyzer/embeddings.py` | new | Lazy-load sentence-transformers | Task 4 |
| `analyzer-prototype/analyzer/detectors/embedding.py` | new | Scenarios 1, 2, 5 | Task 5 |
| `analyzer-prototype/analyzer/render.py` | new | Markdown rendering | Task 6 |
| `analyzer-prototype/analyzer/render.py` (extended) | modify | HTML summary | Task 7 |
| `analyzer-prototype/analyzer/templates/summary.html.j2` | new | Jinja2 template | Task 7 |
| `analyzer-prototype/analyzer/cli.py` | new | argparse + orchestration | Task 8 |
| `analyzer-prototype/tests/fixtures/*.jsonl` | new | Synthetic session fixtures | Tasks 2, 3, 5 |
| `analyzer-prototype/tests/test_*.py` | new | pytest tests | Tasks 2, 3, 5, 6, 7, 8 |
| `docs/superpowers/specs/2026-05-28-feedback-program-roadmap.md` | modify | Add Phase 0.5 to §13 + §14 | Task 9 |

---

## Task 1: Scaffolding (package skeleton + base types)

Set up the empty package, the dependency manifest, and the long-lived `Finding`/`Detector` types. After this task, `pip install -e analyzer-prototype/` succeeds and `python -m analyzer --help` errors cleanly (we wire the CLI in Task 8).

**Files:**
- Create: `analyzer-prototype/pyproject.toml`
- Create: `analyzer-prototype/README.md`
- Create: `analyzer-prototype/.gitignore`
- Create: `analyzer-prototype/analyzer/__init__.py`
- Create: `analyzer-prototype/analyzer/__main__.py`
- Create: `analyzer-prototype/analyzer/detectors/__init__.py`
- Create: `analyzer-prototype/analyzer/detectors/base.py`

- [ ] **Step 1: Create the directory tree**

Run:
```bash
mkdir -p analyzer-prototype/analyzer/detectors analyzer-prototype/tests/fixtures
```

- [ ] **Step 2: Write `pyproject.toml`**

Create `analyzer-prototype/pyproject.toml`:

```toml
[project]
name = "ai-sherpa-analyzer-prototype"
version = "0.1.0"
description = "Local-data Phase 0.5 prototype for the AI Sherpa analyzer."
requires-python = ">=3.11"
dependencies = [
    "pandas>=2.0",
    "sentence-transformers>=2.5",
    "scikit-learn>=1.4",
    "jinja2>=3.1",
]

[project.optional-dependencies]
dev = ["pytest>=8.0"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
include = ["analyzer*"]
exclude = ["tests*"]
```

- [ ] **Step 3: Write `.gitignore`**

Create `analyzer-prototype/.gitignore`:

```
analyzer-out/
__pycache__/
*.egg-info/
.pytest_cache/
.venv/
*.pyc
```

- [ ] **Step 4: Write `README.md`**

Create `analyzer-prototype/README.md`:

````markdown
# AI Sherpa analyzer prototype (Phase 0.5)

Reads local Claude Code session JSONL files and produces candidate-change
Issues as Markdown plus a single HTML summary. Validates the analyzer
architecture before any collection or release infrastructure exists.

**Status: experimental.** Code surface developed here is expected to move
to `server/analyzer/` once productized (Phase 2a). Don't depend on it
from anything else in this repo.

## Install

```bash
cd analyzer-prototype
pip install -e ".[dev]"
```

The first run will download `BAAI/bge-small-en-v1.5` (~100 MB) into the
HuggingFace cache (`~/.cache/huggingface/`).

## Run

```bash
python -m analyzer
```

Reads `~/.claude/projects/**/*.jsonl`, writes Markdown findings to
`./analyzer-out/issues/` and `./analyzer-out/summary.html`.

```bash
python -m analyzer --scenarios scenario-7 --verbose
python -m analyzer --input tests/fixtures --output /tmp/out
```

## Test

```bash
pytest
```

## Design

See `docs/superpowers/specs/2026-05-29-analyzer-prototype-design.md`.
````

- [ ] **Step 5: Write `analyzer/__init__.py`**

Create `analyzer-prototype/analyzer/__init__.py`:

```python
"""AI Sherpa analyzer prototype."""
__version__ = "0.1.0"
```

- [ ] **Step 6: Write `analyzer/__main__.py`**

Create `analyzer-prototype/analyzer/__main__.py`:

```python
from analyzer.cli import main

if __name__ == "__main__":
    main()
```

(`analyzer.cli` doesn't exist yet — Task 8 creates it. For now this file just exists so `python -m analyzer` is wired up.)

- [ ] **Step 7: Write `detectors/__init__.py`**

Create `analyzer-prototype/analyzer/detectors/__init__.py`:

```python
"""Detector registry.

ALL_DETECTORS is the ordered list used by analyzer.cli to run every
detector against the events DataFrame. Add a new scenario by appending
its function here.
"""
from analyzer.detectors import tabular, embedding

ALL_DETECTORS = [
    # Tabular (no embeddings needed)
    tabular.detect_domain_mismatch,        # scenario-3
    tabular.detect_tool_misuse,            # scenario-7
    tabular.detect_abandonment,            # scenario-8
    tabular.detect_accept_then_revert,     # scenario-10
    tabular.detect_skill_roi,              # scenario-11
    tabular.detect_onboarding_velocity,    # scenario-12
    tabular.detect_stale_install,          # scenario-13
    # Embedding-based
    embedding.detect_missed_skill_fire,    # scenario-1
    embedding.detect_repeated_correction,  # scenario-2
    embedding.detect_repeated_priming,     # scenario-5
]
```

(References to `tabular.*` and `embedding.*` will be unresolved until Tasks 3 and 5. That's fine — `__init__.py` is imported lazily.)

- [ ] **Step 8: Write `detectors/base.py`**

Create `analyzer-prototype/analyzer/detectors/base.py`:

```python
"""Long-lived types shared by every detector.

These are the contract. Detector implementations may change; this file
should change very rarely.
"""
from dataclasses import dataclass
from typing import Callable, Iterable, Protocol
import numpy as np
import pandas as pd

EmbeddingsFn = Callable[[list[str]], np.ndarray]


@dataclass(frozen=True)
class Finding:
    scenario_id: str          # "scenario-7", matches roadmap §3 numbering
    title: str                # one-line headline; becomes the Markdown <h1>
    bucket: str               # roadmap §12.2: "add-rule" | "refine-rule" |
                              #   "skill-fix" | "plugin-change" |
                              #   "setup-fix" | "docs"
    domain: str | None        # "embedded" | "web" | … | None if any/unknown
    severity: str             # "critical" | "high" | "normal" | "low"
    confidence: str           # "high" | "medium" | "low"
    evidence_md: str          # Markdown body (≥ one paragraph)
    sample_session_paths: list[str]   # absolute paths to source JSONL


class Detector(Protocol):
    id: str
    def __call__(
        self,
        events: pd.DataFrame,
        embeddings_fn: EmbeddingsFn,
    ) -> Iterable[Finding]: ...
```

- [ ] **Step 9: Verify the package installs**

Run:
```bash
cd analyzer-prototype && pip install -e ".[dev]" && cd ..
```
Expected: pip resolves and installs the package + deps. Long output ending in `Successfully installed …`. No errors. (First-time installs will download ~500 MB of dependencies.)

- [ ] **Step 10: Verify import works**

Run:
```bash
python -c "from analyzer.detectors.base import Finding, Detector; print('OK')"
```
Expected output: `OK`

- [ ] **Step 11: Commit**

```bash
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scaffolding + Finding/Detector base types"
```

---

## Task 2: Ingest — JSONL → events DataFrame

Discover the actual JSONL schema, write a tiny fixture, then TDD the ingest function.

**Files:**
- Create: `analyzer-prototype/tests/fixtures/minimal-session.jsonl`
- Create: `analyzer-prototype/tests/test_ingest.py`
- Create: `analyzer-prototype/analyzer/ingest.py`

- [ ] **Step 1: Probe the real Claude Code JSONL schema**

Run (on a Unix shell; on Windows use the equivalent paths):
```bash
ls -la "$HOME/.claude/projects/" | head
find "$HOME/.claude/projects/" -name "*.jsonl" -print | head -3
head -3 "$(find "$HOME/.claude/projects/" -name "*.jsonl" -print | head -1)" | python -m json.tool --no-ensure-ascii 2>/dev/null || head -3 "$(find "$HOME/.claude/projects/" -name "*.jsonl" -print | head -1)"
```
Expected: a list of project directories, then the first few JSON lines from one session, printed pretty.

Note the field names you see — at minimum: which field carries the message type, the timestamp, the text content, and the session id. Update Step 4 (the ingest implementation) if any field names differ from the defaults assumed below.

- [ ] **Step 2: Create the fixture**

The fixture is a minimal synthetic session covering a user prompt, an assistant response, a tool call, a tool result, and a slash command. Create `analyzer-prototype/tests/fixtures/minimal-session.jsonl` with this exact content (one JSON object per line):

```jsonl
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-fixture-1","cwd":"/tmp/proj","message":{"role":"user","content":"Help me bring up a new STM32H7 board using Zephyr"}}
{"type":"assistant","uuid":"a1","timestamp":"2026-05-28T10:00:05Z","sessionId":"s-fixture-1","message":{"role":"assistant","content":[{"type":"text","text":"Sure, let me look around."}]}}
{"type":"assistant","uuid":"a2","timestamp":"2026-05-28T10:00:06Z","sessionId":"s-fixture-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"cat /etc/os-release"}}]}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:07Z","sessionId":"s-fixture-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"NAME=\"Ubuntu\""}]}}
{"type":"user","uuid":"u3","timestamp":"2026-05-28T10:00:10Z","sessionId":"s-fixture-1","message":{"role":"user","content":"/clear"}}
```

- [ ] **Step 3: Write the failing test**

Create `analyzer-prototype/tests/test_ingest.py`:

```python
from pathlib import Path
import pandas as pd
from analyzer.ingest import load_events

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_load_events_returns_dataframe_with_expected_columns():
    events = load_events(FIXTURE_DIR)
    expected_cols = {
        "session_id", "session_path", "project_path_hash",
        "timestamp", "event_type", "text", "tool_name",
        "command_first_word", "is_first_in_session",
        "slash_command_name",
    }
    assert expected_cols.issubset(events.columns), \
        f"missing: {expected_cols - set(events.columns)}"


def test_load_events_recognises_prompt_response_tool_call_tool_result_slashcmd():
    events = load_events(FIXTURE_DIR)
    types_seen = set(events.event_type.unique())
    assert {"prompt", "response", "tool_call", "tool_result", "slash_command"} <= types_seen


def test_load_events_marks_first_prompt_in_session():
    events = load_events(FIXTURE_DIR)
    first_prompts = events[(events.event_type == "prompt") & (events.is_first_in_session == True)]
    assert len(first_prompts) == 1, f"expected exactly 1 first prompt, got {len(first_prompts)}"


def test_load_events_extracts_bash_command_first_word():
    events = load_events(FIXTURE_DIR)
    bash_calls = events[(events.event_type == "tool_call") & (events.tool_name == "Bash")]
    assert (bash_calls.command_first_word == "cat").all()


def test_load_events_handles_empty_dir(tmp_path):
    events = load_events(tmp_path)
    assert isinstance(events, pd.DataFrame)
    assert len(events) == 0
```

- [ ] **Step 4: Run the test (expect FAIL — `ingest.py` doesn't exist)**

Run:
```bash
cd analyzer-prototype && pytest tests/test_ingest.py -v ; cd ..
```
Expected: `ImportError: cannot import name 'load_events' from 'analyzer.ingest'`, exit non-zero.

- [ ] **Step 5: Write the ingest implementation**

Create `analyzer-prototype/analyzer/ingest.py`:

```python
"""Walk JSONL session files under a root, emit a normalized events DataFrame.

If you probed a real Claude Code JSONL in Task 2 step 1 and saw fields named
differently than below (e.g., `type` is actually nested under `message.role`),
adjust `_classify_event` and `_extract_*` helpers. The test fixture is shaped
to match these assumed names; if you change the assumptions, also update the
fixture in tests/fixtures/minimal-session.jsonl.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable
import pandas as pd


_COLUMNS = [
    "session_id", "session_path", "project_path_hash",
    "timestamp", "event_type",
    "text", "tool_name", "tool_args_json", "tool_success",
    "command_first_word", "file_extension",
    "skill_name", "slash_command_name",
    "is_first_in_session",
]


def load_events(root: Path | str) -> pd.DataFrame:
    """Walk JSONL files under `root`, return all events as a DataFrame."""
    root = Path(root)
    rows: list[dict[str, Any]] = []
    for jsonl_path in root.rglob("*.jsonl"):
        rows.extend(_parse_session_file(jsonl_path))

    df = pd.DataFrame(rows, columns=_COLUMNS)
    if df.empty:
        return df

    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True, errors="coerce")
    df = df.sort_values(["session_id", "timestamp"]).reset_index(drop=True)

    # Mark first prompt per session.
    df["is_first_in_session"] = False
    first_prompts = (
        df[df.event_type == "prompt"]
        .groupby("session_id", group_keys=False)
        .head(1)
        .index
    )
    df.loc[first_prompts, "is_first_in_session"] = True
    return df


def _parse_session_file(path: Path) -> Iterable[dict[str, Any]]:
    project_path_hash = hashlib.sha256(str(path.parent).encode()).hexdigest()[:16]
    try:
        with path.open("r", encoding="utf-8") as f:
            lines = [ln for ln in f if ln.strip()]
    except OSError:
        return

    for line in lines:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        session_id = obj.get("sessionId") or obj.get("session_id") or path.stem
        timestamp = obj.get("timestamp")
        for event in _classify_event(obj):
            event.update({
                "session_id": session_id,
                "session_path": str(path),
                "project_path_hash": project_path_hash,
                "timestamp": timestamp,
            })
            # Fill in missing columns with None so DataFrame is rectangular.
            for col in _COLUMNS:
                event.setdefault(col, None)
            yield event


def _classify_event(obj: dict[str, Any]) -> Iterable[dict[str, Any]]:
    typ = obj.get("type")
    msg = obj.get("message") or {}
    content = msg.get("content")

    if typ == "user":
        if isinstance(content, str):
            if content.startswith("/"):
                yield {"event_type": "slash_command",
                       "slash_command_name": content.split()[0]}
            else:
                yield {"event_type": "prompt", "text": content}
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    yield {"event_type": "tool_result",
                           "tool_success": _infer_tool_success(block.get("content"))}
                else:
                    txt = block.get("text") if isinstance(block, dict) else None
                    if txt:
                        yield {"event_type": "prompt", "text": txt}
    elif typ == "assistant":
        if isinstance(content, str):
            yield {"event_type": "response", "text": content}
        elif isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                btyp = block.get("type")
                if btyp == "text":
                    yield {"event_type": "response", "text": block.get("text", "")}
                elif btyp == "tool_use":
                    tool_name = block.get("name", "")
                    args = block.get("input") or {}
                    args_json = json.dumps(args)
                    first_word = None
                    if tool_name == "Bash":
                        cmd = args.get("command", "")
                        first_word = cmd.strip().split(maxsplit=1)[0] if cmd else None
                    file_ext = None
                    if tool_name in ("Read", "Edit", "Write"):
                        fp = args.get("file_path", "")
                        if "." in fp:
                            file_ext = "." + fp.rsplit(".", 1)[1].lower()
                    yield {"event_type": "tool_call",
                           "tool_name": tool_name,
                           "tool_args_json": args_json,
                           "command_first_word": first_word,
                           "file_extension": file_ext}


def _infer_tool_success(content: Any) -> bool | None:
    if isinstance(content, str):
        lower = content.lower()
        if "error" in lower or "failed" in lower:
            return False
        return True
    return None
```

- [ ] **Step 6: Run the test (expect PASS)**

Run:
```bash
cd analyzer-prototype && pytest tests/test_ingest.py -v ; cd ..
```
Expected: all five tests pass.

If any test fails, the most common causes are (a) JSONL field names differ from the assumed shape — adjust `_classify_event`; (b) the fixture used different field names — adjust the fixture; (c) timezone handling — `pd.to_datetime(..., utc=True)` should canonicalize.

- [ ] **Step 7: Commit**

```bash
git add analyzer-prototype/analyzer/ingest.py \
        analyzer-prototype/tests/test_ingest.py \
        analyzer-prototype/tests/fixtures/minimal-session.jsonl
git commit -m "feat(analyzer-prototype): JSONL ingest → events DataFrame"
```

---

## Task 3: Tabular detectors (scenarios 3, 7, 8, 10, 11, 12, 13)

All seven scenarios share the pattern: fixture → failing test → minimal detector → passing test → commit. Each gets its own sub-task; commit each as you go so you can roll back any single detector if it misbehaves on real data.

**Files:**
- Create: `analyzer-prototype/analyzer/detectors/tabular.py`
- Create: `analyzer-prototype/tests/fixtures/tool-misuse.jsonl` (+ six more)
- Create: `analyzer-prototype/tests/test_tabular_detectors.py`

- [ ] **Step 1: Create the empty detector file**

Create `analyzer-prototype/analyzer/detectors/tabular.py`:

```python
"""Tabular detectors — pure SQL/pandas over the events DataFrame.

Each detector function takes (events, embeddings_fn) and returns
Iterable[Finding]. Embeddings are ignored here but the signature
matches the Detector protocol for uniformity.
"""
from typing import Iterable
import pandas as pd
from analyzer.detectors.base import Finding
```

- [ ] **Step 2: Create the test file skeleton**

Create `analyzer-prototype/tests/test_tabular_detectors.py`:

```python
from pathlib import Path
import pandas as pd
from analyzer.ingest import load_events

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def _events(name: str) -> pd.DataFrame:
    """Helper: load just one fixture file as a DataFrame."""
    return load_events(FIXTURE_DIR / name)
```

(Each sub-task below appends a test function and a detector function.)

### Sub-task 3a — Scenario 7 (tool misuse)

The first detector establishes the pattern. The implementation matches spec §6.1 verbatim.

- [ ] **3a.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/tool-misuse/session.jsonl`. Five Bash + cat calls in one session is enough to trip the threshold:

```jsonl
{"type":"assistant","uuid":"a1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-tm-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cat foo.txt"}}]}}
{"type":"assistant","uuid":"a2","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-tm-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"cat bar.txt"}}]}}
{"type":"assistant","uuid":"a3","timestamp":"2026-05-28T10:00:02Z","sessionId":"s-tm-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"cat baz.txt"}}]}}
{"type":"assistant","uuid":"a4","timestamp":"2026-05-28T10:00:03Z","sessionId":"s-tm-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"Bash","input":{"command":"cat qux.txt"}}]}}
{"type":"assistant","uuid":"a5","timestamp":"2026-05-28T10:00:04Z","sessionId":"s-tm-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t5","name":"Bash","input":{"command":"cat quux.txt"}}]}}
```

- [ ] **3a.2: Append the failing test**

Append to `tests/test_tabular_detectors.py`:

```python
def test_detect_tool_misuse():
    from analyzer.detectors.tabular import detect_tool_misuse
    findings = list(detect_tool_misuse(_events("tool-misuse"), embeddings_fn=None))
    assert len(findings) == 1
    f = findings[0]
    assert f.scenario_id == "scenario-7"
    assert "cat" in f.title.lower()
    assert f.bucket == "add-rule"
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py::test_detect_tool_misuse -v ; cd ..
```
Expected: `ImportError: cannot import name 'detect_tool_misuse'`, exit non-zero.

- [ ] **3a.3: Append the detector implementation**

Append to `analyzer/detectors/tabular.py`:

```python
def detect_tool_misuse(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    bash_calls = events[(events.event_type == "tool_call") & (events.tool_name == "Bash")]
    suspect = bash_calls[bash_calls.command_first_word.isin(["cat", "head", "tail", "grep"])]
    if len(suspect) < 5:
        return []

    findings = []
    for cmd, group in suspect.groupby("command_first_word"):
        replacement = {"cat": "Read", "head": "Read", "tail": "Read", "grep": "Grep"}[cmd]
        count = len(group)
        sample_paths = group.session_path.unique().tolist()[:5]
        findings.append(Finding(
            scenario_id="scenario-7",
            title=f"Tool misuse: Bash + {cmd} instead of {replacement}",
            bucket="add-rule",
            domain=None,
            severity="normal",
            confidence="high" if count >= 20 else "medium",
            evidence_md=(
                f"Across the analyzed corpus, `Bash {cmd}` was invoked **{count} times**.\n\n"
                f"Each call could have been handled by the `{replacement}` tool directly, "
                f"avoiding a shell escape and the associated permission prompt.\n\n"
                f"**Suggested change:** add a rule to `core/CLAUDE.md` discouraging "
                f"`Bash {cmd}` when the equivalent first-class tool exists."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_tool_misuse.id = "scenario-7"
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py::test_detect_tool_misuse -v ; cd ..
```
Expected: PASS.

- [ ] **3a.4: Commit**

```bash
git add analyzer-prototype/analyzer/detectors/tabular.py \
        analyzer-prototype/tests/test_tabular_detectors.py \
        analyzer-prototype/tests/fixtures/tool-misuse/
git commit -m "feat(analyzer-prototype): scenario-7 tool-misuse detector"
```

### Sub-task 3b — Scenario 8 (session abandonment)

A session is "abandoned" if it contains 2+ `/clear` or `/restart` slash commands, or if the last event is a user prompt with no following assistant response.

- [ ] **3b.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/abandonment/session.jsonl` — three sessions, two of which abandon:

```jsonl
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-ab-1","message":{"role":"user","content":"hello"}}
{"type":"assistant","uuid":"a1","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-ab-1","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:02Z","sessionId":"s-ab-2","message":{"role":"user","content":"/clear"}}
{"type":"user","uuid":"u3","timestamp":"2026-05-28T10:00:03Z","sessionId":"s-ab-2","message":{"role":"user","content":"/clear"}}
{"type":"user","uuid":"u4","timestamp":"2026-05-28T10:00:04Z","sessionId":"s-ab-2","message":{"role":"user","content":"/restart"}}
{"type":"user","uuid":"u5","timestamp":"2026-05-28T10:00:05Z","sessionId":"s-ab-3","message":{"role":"user","content":"help me"}}
```

(Session 1 ends cleanly. Session 2 has 3 clear/restart events. Session 3 ends on a user prompt with no response.)

- [ ] **3b.2: Append the test**

Append to `tests/test_tabular_detectors.py`:

```python
def test_detect_abandonment():
    from analyzer.detectors.tabular import detect_abandonment
    findings = list(detect_abandonment(_events("abandonment"), embeddings_fn=None))
    # Either one aggregate finding or per-session findings is acceptable;
    # require the finding mentions the abandoned sessions specifically.
    assert any(f.scenario_id == "scenario-8" for f in findings)
    all_paths = {p for f in findings for p in f.sample_session_paths}
    assert any("abandonment" in p for p in all_paths)
```

- [ ] **3b.3: Append the implementation**

Append to `analyzer/detectors/tabular.py`:

```python
def detect_abandonment(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []

    abandoned_sessions: set[str] = set()

    # Pattern A: 2+ /clear or /restart in a session.
    clear_restart = events[
        (events.event_type == "slash_command")
        & events.slash_command_name.isin(["/clear", "/restart"])
    ]
    clear_counts = clear_restart.groupby("session_id").size()
    abandoned_sessions.update(clear_counts[clear_counts >= 2].index)

    # Pattern B: session ends on a user prompt (no following assistant response).
    last_events = events.groupby("session_id").tail(1)
    abandoned_sessions.update(
        last_events[last_events.event_type == "prompt"].session_id.tolist()
    )

    if len(abandoned_sessions) < 2:
        return []

    sample_paths = (
        events[events.session_id.isin(abandoned_sessions)]
        .session_path.unique().tolist()[:5]
    )
    return [Finding(
        scenario_id="scenario-8",
        title=f"{len(abandoned_sessions)} sessions show abandonment / frustration signals",
        bucket="add-rule",
        domain=None,
        severity="normal",
        confidence="high" if len(abandoned_sessions) >= 5 else "medium",
        evidence_md=(
            f"**{len(abandoned_sessions)} sessions** ended in `/clear` / `/restart` "
            f"loops or stopped mid-task without an assistant response. This is a "
            f"signal that a recurring task pattern is not well covered by current "
            f"rules or skills.\n\n"
            f"**Suggested change:** sample the abandoned sessions to identify the "
            f"common task pattern, then add a rule or skill covering it."
        ),
        sample_session_paths=sample_paths,
    )]

detect_abandonment.id = "scenario-8"
```

- [ ] **3b.4: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py::test_detect_abandonment -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenario-8 abandonment detector"
```

### Sub-task 3c — Scenario 10 (accept-then-revert)

Accepted tool result followed by an edit to the same file within 60 seconds suggests the AI was 70% right and the user finished the job.

- [ ] **3c.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/accept-revert/session.jsonl`. Use a single session with an Edit tool call followed within seconds by another Edit to the same file:

```jsonl
{"type":"assistant","uuid":"a1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-ar-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/tmp/foo.py","old_string":"a","new_string":"b"}}]}}
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-ar-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"assistant","uuid":"a2","timestamp":"2026-05-28T10:00:05Z","sessionId":"s-ar-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/tmp/foo.py","old_string":"b","new_string":"c"}}]}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:06Z","sessionId":"s-ar-1","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"ok"}]}}
```

For a finding to fire, scenario 10 needs ≥3 such revert pairs. Duplicate the above 3 times with different session IDs by copy-pasting and substituting `s-ar-1` → `s-ar-2` and `s-ar-3`.

- [ ] **3c.2: Append the test**

```python
def test_detect_accept_then_revert():
    from analyzer.detectors.tabular import detect_accept_then_revert
    findings = list(detect_accept_then_revert(_events("accept-revert"), embeddings_fn=None))
    assert any(f.scenario_id == "scenario-10" for f in findings)
```

- [ ] **3c.3: Append the implementation**

Append to `analyzer/detectors/tabular.py`:

```python
def detect_accept_then_revert(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    edits = events[
        (events.event_type == "tool_call") & events.tool_name.isin(["Edit", "Write"])
    ].sort_values(["session_id", "timestamp"]).reset_index(drop=True)
    if edits.empty:
        return []

    # Parse file_path out of tool_args_json.
    import json
    edits["file_path"] = edits.tool_args_json.apply(
        lambda j: (json.loads(j).get("file_path") if isinstance(j, str) else None)
    )

    revert_pairs = 0
    sample_paths: list[str] = []
    for _, group in edits.groupby(["session_id", "file_path"]):
        group = group.sort_values("timestamp")
        if len(group) < 2:
            continue
        ts = group.timestamp.tolist()
        # Look for consecutive edits to same file within 60s.
        for i in range(len(ts) - 1):
            if (ts[i + 1] - ts[i]).total_seconds() <= 60:
                revert_pairs += 1
                sample_paths.append(group.session_path.iloc[0])

    if revert_pairs < 3:
        return []

    return [Finding(
        scenario_id="scenario-10",
        title=f"{revert_pairs} accept-then-revert edit pairs detected",
        bucket="refine-rule",
        domain=None,
        severity="normal",
        confidence="high" if revert_pairs >= 10 else "medium",
        evidence_md=(
            f"**{revert_pairs} cases** where the same file was edited again "
            f"within 60 seconds of the previous edit. This pattern indicates "
            f"Claude was close but not quite right, and the user finished the "
            f"job manually.\n\n"
            f"**Suggested change:** sample these sessions; if there's a recurring "
            f"pattern in what Claude got almost-right, refine the relevant rule."
        ),
        sample_session_paths=list(dict.fromkeys(sample_paths))[:5],
    )]

detect_accept_then_revert.id = "scenario-10"
```

- [ ] **3c.4: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py::test_detect_accept_then_revert -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenario-10 accept-then-revert detector"
```

### Sub-task 3d — Scenario 11 (skill/plugin ROI)

For each skill that ever fires, compute fire count. For the prototype, "low fire rate" means: skill exists in `~/.claude/skills/` but appears in ≤ 2% of analyzed sessions.

- [ ] **3d.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/skill-roi/session.jsonl`:

```jsonl
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-roi-1","message":{"role":"user","content":"do a thing"}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-roi-2","message":{"role":"user","content":"do another thing"}}
{"type":"user","uuid":"u3","timestamp":"2026-05-28T10:00:02Z","sessionId":"s-roi-3","message":{"role":"user","content":"do a third thing"}}
```

(No `skill_invoked` events — three sessions with zero skill fires. The detector will be parameterized to take an "installed skills" list; we'll pass a synthetic one in the test.)

- [ ] **3d.2: Append the test**

```python
def test_detect_skill_roi_zero_fires():
    from analyzer.detectors.tabular import detect_skill_roi
    events = _events("skill-roi")
    findings = list(detect_skill_roi(events, embeddings_fn=None, installed_skills=["board-bringup", "graphify"]))
    # Two installed skills with zero fires in 3 sessions → at least one finding.
    skill_names_in_findings = {f.title for f in findings}
    assert len(findings) >= 1
    assert any("board-bringup" in t or "graphify" in t for t in skill_names_in_findings)
```

- [ ] **3d.3: Append the implementation**

Append to `analyzer/detectors/tabular.py`:

```python
def detect_skill_roi(
    events: pd.DataFrame,
    embeddings_fn=None,
    installed_skills: list[str] | None = None,
) -> Iterable[Finding]:
    if events.empty or not installed_skills:
        return []
    total_sessions = events.session_id.nunique()
    if total_sessions == 0:
        return []

    fired = (
        events[events.event_type == "skill_invoked"]
        .groupby("skill_name").session_id.nunique()
        .to_dict()
    )

    findings = []
    for skill in installed_skills:
        sessions_fired_in = fired.get(skill, 0)
        rate = sessions_fired_in / total_sessions
        if rate < 0.02:  # less than 2% of sessions
            findings.append(Finding(
                scenario_id="scenario-11",
                title=f"Skill `{skill}` has near-zero fire rate ({sessions_fired_in}/{total_sessions} sessions)",
                bucket="skill-fix",
                domain=None,
                severity="low" if sessions_fired_in > 0 else "normal",
                confidence="medium",
                evidence_md=(
                    f"`{skill}` is installed but fired in only **{sessions_fired_in} of "
                    f"{total_sessions} analyzed sessions** ({rate:.1%}).\n\n"
                    f"**Suggested change:** review the skill's `description:` field. "
                    f"Either tighten it to match real usage patterns, or remove the "
                    f"skill from the install list if it is no longer relevant."
                ),
                sample_session_paths=[],
            ))
    return findings

detect_skill_roi.id = "scenario-11"
```

(Note: detector takes an optional `installed_skills` kwarg, which means the orchestrator in `cli.py` needs to pass it. Step 8 wires this.)

- [ ] **3d.4: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py::test_detect_skill_roi_zero_fires -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenario-11 skill-ROI detector"
```

### Sub-task 3e — Scenarios 3, 12, 13 (small + degraded-mode detectors)

These three are quick:
- **Scenario 3 (domain mismatch):** the prototype reads `~/.claude/CLAUDE.md` to detect configured domain, then compares to top file extensions touched in sessions.
- **Scenario 12 (onboarding velocity):** compute median session length per week; flag if it stays high (no learning curve visible). Degrades gracefully on small corpora.
- **Scenario 13 (stale install):** read the version comment from `~/.claude/CLAUDE.md` (or fall back to the repo `VERSION` file); produce an informational finding.

- [ ] **3e.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/mixed/session.jsonl` — two sessions with Edit calls on `.py` files (suggesting web/data domain):

```jsonl
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-mx-1","message":{"role":"user","content":"refactor this"}}
{"type":"assistant","uuid":"a1","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-mx-1","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/proj/app.py","old_string":"a","new_string":"b"}}]}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:02Z","sessionId":"s-mx-2","message":{"role":"user","content":"add a test"}}
{"type":"assistant","uuid":"a2","timestamp":"2026-05-28T10:00:03Z","sessionId":"s-mx-2","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/proj/test.py","old_string":"c","new_string":"d"}}]}}
```

- [ ] **3e.2: Append the tests**

```python
def test_detect_domain_mismatch():
    from analyzer.detectors.tabular import detect_domain_mismatch
    findings = list(detect_domain_mismatch(_events("mixed"), embeddings_fn=None, configured_domain="embedded"))
    assert any(f.scenario_id == "scenario-3" for f in findings)


def test_detect_onboarding_velocity_does_not_crash_on_small_corpus():
    from analyzer.detectors.tabular import detect_onboarding_velocity
    findings = list(detect_onboarding_velocity(_events("mixed"), embeddings_fn=None))
    # Small corpus → either zero findings or an informational one. Both are fine.
    assert isinstance(findings, list)


def test_detect_stale_install_returns_informational():
    from analyzer.detectors.tabular import detect_stale_install
    findings = list(detect_stale_install(_events("mixed"), embeddings_fn=None, current_version="v2026.05.29"))
    # An informational finding is OK; no finding is also OK on a tiny corpus.
    assert isinstance(findings, list)
```

- [ ] **3e.3: Append the implementations**

Append to `analyzer/detectors/tabular.py`:

```python
_EXTENSION_TO_DOMAIN = {
    ".c": "embedded", ".h": "embedded", ".cpp": "embedded",
    ".py": "data",
    ".ts": "web", ".tsx": "web", ".js": "web", ".jsx": "web",
    ".go": "devops", ".tf": "devops",
}


def detect_domain_mismatch(
    events: pd.DataFrame,
    embeddings_fn=None,
    configured_domain: str | None = None,
) -> Iterable[Finding]:
    if events.empty or not configured_domain:
        return []
    edits = events[events.event_type == "tool_call"]
    edits = edits[edits.file_extension.notna()]
    if edits.empty:
        return []
    inferred = edits.file_extension.map(_EXTENSION_TO_DOMAIN).dropna()
    if inferred.empty:
        return []
    top_inferred = inferred.value_counts().idxmax()
    if top_inferred == configured_domain:
        return []
    return [Finding(
        scenario_id="scenario-3",
        title=f"Configured domain `{configured_domain}` but file extensions suggest `{top_inferred}`",
        bucket="setup-fix",
        domain=None,
        severity="normal",
        confidence="medium",
        evidence_md=(
            f"The current AI Sherpa install is configured for domain "
            f"`{configured_domain}`, but the files touched across the analyzed "
            f"sessions match the `{top_inferred}` domain.\n\n"
            f"**Suggested change:** re-run `setup --reconfigure` and pick "
            f"`{top_inferred}`, or update the onboarding doc if this is "
            f"intentional mixed work."
        ),
        sample_session_paths=edits.session_path.unique().tolist()[:3],
    )]

detect_domain_mismatch.id = "scenario-3"


def detect_onboarding_velocity(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    session_lengths = (
        events.groupby("session_id")
        .agg(start=("timestamp", "min"), end=("timestamp", "max"))
    )
    session_lengths["minutes"] = (session_lengths.end - session_lengths.start).dt.total_seconds() / 60.0
    if len(session_lengths) < 5:
        return []  # not enough data; degrade silently
    median_minutes = session_lengths.minutes.median()
    return [Finding(
        scenario_id="scenario-12",
        title=f"Median session length: {median_minutes:.1f} min across {len(session_lengths)} sessions",
        bucket="docs",
        domain=None,
        severity="low",
        confidence="low",
        evidence_md=(
            f"Informational. Across the analyzed corpus, median session length "
            f"is **{median_minutes:.1f} minutes** over {len(session_lengths)} sessions.\n\n"
            f"Useful baseline for tracking onboarding velocity once multi-engineer "
            f"data is available (Phase 1.5+)."
        ),
        sample_session_paths=[],
    )]

detect_onboarding_velocity.id = "scenario-12"


def detect_stale_install(
    events: pd.DataFrame,
    embeddings_fn=None,
    current_version: str | None = None,
) -> Iterable[Finding]:
    if not current_version:
        return []
    return [Finding(
        scenario_id="scenario-13",
        title=f"Current install version: {current_version}",
        bucket="docs",
        domain=None,
        severity="low",
        confidence="low",
        evidence_md=(
            f"Informational. The current AI Sherpa install reports version "
            f"`{current_version}`. Once Phase 1 ships and a `VERSION` file is "
            f"updated per release, this detector will flag installs more than N "
            f"releases behind."
        ),
        sample_session_paths=[],
    )]

detect_stale_install.id = "scenario-13"
```

- [ ] **3e.4: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_tabular_detectors.py -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenarios 3, 12, 13 (domain/onboarding/stale-install)"
```

---

## Task 4: Embeddings module (lazy loader)

Wraps `sentence-transformers` so detectors get a pure-function `embeddings_fn`. Model loads once on first call; subsequent calls reuse it.

**Files:**
- Create: `analyzer-prototype/analyzer/embeddings.py`
- Create: `analyzer-prototype/tests/test_embeddings.py`

- [ ] **Step 1: Write the failing test**

Create `analyzer-prototype/tests/test_embeddings.py`:

```python
import numpy as np
from analyzer.embeddings import make_embeddings_fn


def test_embeddings_fn_returns_2d_float_array():
    fn = make_embeddings_fn()
    out = fn(["hello world", "goodbye world"])
    assert isinstance(out, np.ndarray)
    assert out.ndim == 2
    assert out.shape[0] == 2
    assert out.shape[1] > 0


def test_embeddings_fn_is_idempotent_within_a_session():
    fn = make_embeddings_fn()
    a = fn(["test"])
    b = fn(["test"])
    np.testing.assert_array_almost_equal(a, b)
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_embeddings.py -v ; cd ..
```
Expected: `ImportError: cannot import name 'make_embeddings_fn'`, exit non-zero.

- [ ] **Step 2: Write the implementation**

Create `analyzer-prototype/analyzer/embeddings.py`:

```python
"""Lazy-loaded local sentence-transformer.

`make_embeddings_fn()` returns a callable that turns a list of strings
into a 2-D numpy array. The model loads on the first call and is reused
on subsequent calls within the same Python process.
"""
from __future__ import annotations
from typing import Callable
import numpy as np

_MODEL = None
_MODEL_NAME = "BAAI/bge-small-en-v1.5"


def make_embeddings_fn() -> Callable[[list[str]], np.ndarray]:
    def fn(texts: list[str]) -> np.ndarray:
        global _MODEL
        if _MODEL is None:
            from sentence_transformers import SentenceTransformer
            _MODEL = SentenceTransformer(_MODEL_NAME)
        if not texts:
            return np.zeros((0, 0))
        return np.asarray(_MODEL.encode(texts, normalize_embeddings=True))
    return fn
```

- [ ] **Step 3: Run the test**

Run:
```bash
cd analyzer-prototype && pytest tests/test_embeddings.py -v ; cd ..
```
Expected: PASS. First run downloads the model (~100 MB, takes 30–60 seconds on a typical connection).

- [ ] **Step 4: Commit**

```bash
git add analyzer-prototype/analyzer/embeddings.py \
        analyzer-prototype/tests/test_embeddings.py
git commit -m "feat(analyzer-prototype): lazy-loaded sentence-transformer embeddings"
```

---

## Task 5: Embedding detectors (scenarios 1, 2, 5)

Same TDD-per-detector pattern as Task 3, but each uses `embeddings_fn` and clustering.

**Files:**
- Create: `analyzer-prototype/analyzer/detectors/embedding.py`
- Create: `analyzer-prototype/tests/test_embedding_detectors.py`
- Create: `analyzer-prototype/tests/fixtures/repeated-priming/session.jsonl`
- Create: more fixtures as needed

- [ ] **Step 1: Create the empty detector file**

Create `analyzer-prototype/analyzer/detectors/embedding.py`:

```python
"""Embedding-based detectors — sentence-transformer + HDBSCAN clustering."""
from typing import Iterable
import numpy as np
import pandas as pd
from analyzer.detectors.base import Finding
```

### Sub-task 5a — Scenario 5 (repeated context-priming)

The implementation matches spec §6.2 verbatim.

- [ ] **5a.1: Create the fixture**

Create `analyzer-prototype/tests/fixtures/repeated-priming/session.jsonl`. Five sessions each starting with the same long boilerplate prompt (slightly varied wording):

```jsonl
{"type":"user","uuid":"u1","timestamp":"2026-05-28T10:00:00Z","sessionId":"s-rp-1","message":{"role":"user","content":"Remember we use Zephyr RTOS on STM32H7, target board is the Nucleo H743ZI2, please use west build and west flash"}}
{"type":"user","uuid":"u2","timestamp":"2026-05-28T10:00:01Z","sessionId":"s-rp-2","message":{"role":"user","content":"Remember we use Zephyr on STM32H7, the target is Nucleo H743ZI2, use west to build and flash"}}
{"type":"user","uuid":"u3","timestamp":"2026-05-28T10:00:02Z","sessionId":"s-rp-3","message":{"role":"user","content":"Remember our setup: Zephyr RTOS, STM32H7, Nucleo H743ZI2 board, west toolchain"}}
{"type":"user","uuid":"u4","timestamp":"2026-05-28T10:00:03Z","sessionId":"s-rp-4","message":{"role":"user","content":"Remember we use Zephyr on STM32H7 boards Nucleo H743ZI2 use west to build"}}
{"type":"user","uuid":"u5","timestamp":"2026-05-28T10:00:04Z","sessionId":"s-rp-5","message":{"role":"user","content":"Remember: we are on Zephyr RTOS, STM32H7 Nucleo H743ZI2, west for build/flash"}}
```

- [ ] **5a.2: Create the test**

Create `analyzer-prototype/tests/test_embedding_detectors.py`:

```python
from pathlib import Path
from analyzer.ingest import load_events
from analyzer.embeddings import make_embeddings_fn

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def _events(name: str):
    return load_events(FIXTURE_DIR / name)


def test_detect_repeated_priming():
    from analyzer.detectors.embedding import detect_repeated_priming
    fn = make_embeddings_fn()
    findings = list(detect_repeated_priming(_events("repeated-priming"), embeddings_fn=fn))
    assert any(f.scenario_id == "scenario-5" for f in findings), \
        f"expected scenario-5 finding, got: {[f.scenario_id for f in findings]}"
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_embedding_detectors.py::test_detect_repeated_priming -v ; cd ..
```
Expected: FAIL (`cannot import detect_repeated_priming`).

- [ ] **5a.3: Append the implementation**

Append to `analyzer/detectors/embedding.py`:

```python
def detect_repeated_priming(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    if events.empty:
        return []
    first_prompts = events[
        (events.event_type == "prompt") & (events.is_first_in_session == True)
    ]
    if len(first_prompts) < 3:
        return []

    texts = first_prompts.text.fillna("").str.slice(0, 500).tolist()
    paths = first_prompts.session_path.tolist()
    embs = embeddings_fn(texts)
    if embs.shape[0] == 0:
        return []

    from sklearn.cluster import HDBSCAN
    labels = HDBSCAN(min_cluster_size=3, metric="cosine").fit_predict(embs)

    findings = []
    for label in set(labels.tolist()) - {-1}:
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
                f"This is a strong signal that the content belongs in a CLAUDE.md "
                f"rule or a skill's `description:` instead of being re-typed each session.\n\n"
                f"**Sample opening (cluster centroid):**\n\n"
                f"```\n{sample_text[:400]}\n```\n\n"
                f"**Suggested change:** review the sample sessions, distill the "
                f"recurring context into a one-paragraph rule, and add it to the "
                f"appropriate `domains/<X>/CLAUDE.md` or `core/CLAUDE.md`."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_repeated_priming.id = "scenario-5"
```

- [ ] **5a.4: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_embedding_detectors.py::test_detect_repeated_priming -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenario-5 repeated-context-priming detector"
```

### Sub-task 5b — Scenarios 1 + 2 (stub implementations with conservative thresholds)

Scenarios 1 (skill-should-have-fired) and 2 (repeated correction) are harder on a small corpus. For v0, ship stub implementations that fire only on strong signal and otherwise return `[]`. The CLI still runs them; if they don't fire, nothing breaks.

- [ ] **5b.1: Append the implementations**

Append to `analyzer/detectors/embedding.py`:

```python
def detect_missed_skill_fire(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    """Scenario 1: skill description matches session topic, skill never fired.

    Conservative on a small corpus: only fires when we see ≥10 sessions with
    no skill_invoked events at all. Real per-session matching requires reading
    the installed skills' description: fields, which the orchestrator passes
    via a future kwarg; for now this stays a degraded-mode finding.
    """
    if events.empty:
        return []
    sessions = events.session_id.unique()
    if len(sessions) < 10:
        return []
    sessions_with_skill_fires = events[events.event_type == "skill_invoked"].session_id.nunique()
    if sessions_with_skill_fires >= len(sessions) * 0.10:
        return []  # at least 10% of sessions invoked a skill — healthy
    return [Finding(
        scenario_id="scenario-1",
        title=f"Only {sessions_with_skill_fires}/{len(sessions)} sessions invoked any installed skill",
        bucket="skill-fix",
        domain=None,
        severity="normal",
        confidence="low",
        evidence_md=(
            f"Of {len(sessions)} analyzed sessions, only **{sessions_with_skill_fires}** "
            f"invoked any installed skill. This is a low-confidence aggregate signal that "
            f"installed skill `description:` fields may not match real prompts. Per-session "
            f"matching against skill descriptions is deferred to Phase 2a.\n\n"
            f"**Suggested change:** review each installed skill's `description:` field; "
            f"tighten or remove any that are not firing in practice."
        ),
        sample_session_paths=[],
    )]

detect_missed_skill_fire.id = "scenario-1"


def detect_repeated_correction(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    """Scenario 2: same correction-after-AI-output pattern repeated.

    Full implementation requires diffing each user prompt that follows an
    assistant response and clustering the diff deltas. For v0, fire only when
    we see a strong signal: ≥5 user prompts that all start with explicit
    correction phrases ("actually", "no, I meant", "you should") and cluster
    tightly.
    """
    if events.empty:
        return []
    prompts = events[
        (events.event_type == "prompt") & (events.is_first_in_session == False)
    ]
    if len(prompts) < 5:
        return []
    correction_phrases = ["actually", "no, ", "wait,", "you should", "i meant"]
    text_l = prompts.text.fillna("").str.lower()
    correction_mask = text_l.apply(lambda t: any(p in t for p in correction_phrases))
    corrections = prompts[correction_mask]
    if len(corrections) < 5:
        return []

    texts = corrections.text.fillna("").str.slice(0, 300).tolist()
    paths = corrections.session_path.tolist()
    embs = embeddings_fn(texts)
    if embs.shape[0] < 3:
        return []
    from sklearn.cluster import HDBSCAN
    labels = HDBSCAN(min_cluster_size=3, metric="cosine").fit_predict(embs)
    findings = []
    for label in set(labels.tolist()) - {-1}:
        idxs = [i for i, l in enumerate(labels) if l == label]
        sample_text = texts[idxs[0]]
        sample_paths = [paths[i] for i in idxs[:5]]
        findings.append(Finding(
            scenario_id="scenario-2",
            title=f"Repeated user-correction pattern across {len(idxs)} sessions",
            bucket="add-rule",
            domain=None,
            severity="normal",
            confidence="medium",
            evidence_md=(
                f"**{len(idxs)} sessions** contain a near-identical user correction "
                f"following an assistant response — a recurring signal that the same "
                f"AI mistake is being corrected by hand repeatedly.\n\n"
                f"**Sample correction:**\n\n```\n{sample_text[:300]}\n```\n\n"
                f"**Suggested change:** distill the correction into a rule and add it "
                f"to the appropriate `domains/<X>/CLAUDE.md`."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_repeated_correction.id = "scenario-2"
```

- [ ] **5b.2: Append the tests**

Append to `tests/test_embedding_detectors.py`:

```python
def test_detect_missed_skill_fire_degrades_on_small_corpus():
    from analyzer.detectors.embedding import detect_missed_skill_fire
    fn = make_embeddings_fn()
    findings = list(detect_missed_skill_fire(_events("repeated-priming"), embeddings_fn=fn))
    # 5 sessions < the 10-session minimum → no finding.
    assert findings == []


def test_detect_repeated_correction_degrades_on_small_corpus():
    from analyzer.detectors.embedding import detect_repeated_correction
    fn = make_embeddings_fn()
    findings = list(detect_repeated_correction(_events("repeated-priming"), embeddings_fn=fn))
    # No correction phrases in the fixture → no finding.
    assert findings == []
```

- [ ] **5b.3: Run + commit**

```bash
cd analyzer-prototype && pytest tests/test_embedding_detectors.py -v ; cd ..
git add analyzer-prototype/
git commit -m "feat(analyzer-prototype): scenarios 1 + 2 (stub detectors, conservative thresholds)"
```

---

## Task 6: Markdown rendering

One file per `Finding`. Deterministic order: severity desc, then scenario_id asc.

**Files:**
- Create: `analyzer-prototype/analyzer/render.py`
- Create: `analyzer-prototype/tests/test_render.py`

- [ ] **Step 1: Write the failing test**

Create `analyzer-prototype/tests/test_render.py`:

```python
from pathlib import Path
from analyzer.detectors.base import Finding
from analyzer.render import render_markdown_files


def _finding(sev="normal", sid="scenario-7"):
    return Finding(
        scenario_id=sid, title="Test finding", bucket="add-rule",
        domain=None, severity=sev, confidence="high",
        evidence_md="Some evidence.", sample_session_paths=["/tmp/a.jsonl"],
    )


def test_render_markdown_files_writes_one_file_per_finding(tmp_path):
    findings = [_finding("high"), _finding("low")]
    written = render_markdown_files(findings, tmp_path)
    assert len(written) == 2
    assert all(p.exists() for p in written)
    contents = [p.read_text() for p in written]
    assert any("# [add-rule] Test finding" in c for c in contents)


def test_render_markdown_files_orders_by_severity_then_scenario(tmp_path):
    findings = [_finding("low", "scenario-7"), _finding("critical", "scenario-3"), _finding("high", "scenario-5")]
    written = render_markdown_files(findings, tmp_path)
    # Filenames are 001-, 002-, 003- — first should be the critical finding.
    first = written[0].read_text()
    assert "Severity:** critical" in first
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_render.py -v ; cd ..
```
Expected: FAIL.

- [ ] **Step 2: Write the implementation**

Create `analyzer-prototype/analyzer/render.py`:

```python
"""Render Finding objects to Markdown files + HTML summary."""
from __future__ import annotations
import re
from pathlib import Path
from analyzer.detectors.base import Finding


_SEVERITY_ORDER = {"critical": 0, "high": 1, "normal": 2, "low": 3}


def _sort_key(f: Finding) -> tuple:
    return (_SEVERITY_ORDER.get(f.severity, 99), f.scenario_id, f.title)


def _slug(s: str, max_len: int = 60) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", s.lower()).strip("-")
    return s[:max_len].rstrip("-")


def _render_one(f: Finding) -> str:
    paths_block = "\n".join(f"- `{p}`" for p in f.sample_session_paths) or "_(no sample sessions)_"
    return (
        f"# [{f.bucket}] {f.title}\n\n"
        f"**Scenario:** {f.scenario_id} (see roadmap §3)\n"
        f"**Domain:** {f.domain or 'any'}\n"
        f"**Severity:** {f.severity}\n"
        f"**Confidence:** {f.confidence}\n\n"
        f"## Suggested change\n\n"
        f"{f.evidence_md}\n\n"
        f"## Sample sessions\n\n"
        f"{paths_block}\n"
    )


def render_markdown_files(findings: list[Finding], out_dir: Path) -> list[Path]:
    """Write one .md file per finding into out_dir/issues/. Returns paths in order."""
    issues_dir = Path(out_dir) / "issues"
    issues_dir.mkdir(parents=True, exist_ok=True)
    sorted_findings = sorted(findings, key=_sort_key)
    written: list[Path] = []
    for i, f in enumerate(sorted_findings, start=1):
        filename = f"{i:03d}-{_slug(f.title)}.md"
        path = issues_dir / filename
        path.write_text(_render_one(f), encoding="utf-8")
        written.append(path)
    return written
```

- [ ] **Step 3: Run the tests**

Run:
```bash
cd analyzer-prototype && pytest tests/test_render.py -v ; cd ..
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add analyzer-prototype/analyzer/render.py \
        analyzer-prototype/tests/test_render.py
git commit -m "feat(analyzer-prototype): Markdown rendering with deterministic ordering"
```

---

## Task 7: HTML summary

Single self-contained file (`summary.html`) with inline CSS and a sortable table.

**Files:**
- Create: `analyzer-prototype/analyzer/templates/summary.html.j2`
- Modify: `analyzer-prototype/analyzer/render.py`
- Modify: `analyzer-prototype/tests/test_render.py`

- [ ] **Step 1: Create the Jinja2 template**

Create `analyzer-prototype/analyzer/templates/summary.html.j2`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>AI Sherpa analyzer — summary</title>
<style>
  body { font: 14px/1.4 system-ui, sans-serif; padding: 2rem; max-width: 1100px; margin: 0 auto; }
  h1 { font-size: 1.4rem; }
  .meta { color: #666; margin-bottom: 1.5rem; font-size: 0.9rem; }
  table { border-collapse: collapse; width: 100%; }
  th, td { padding: 0.4rem 0.6rem; text-align: left; border-bottom: 1px solid #eee; }
  th { background: #f5f5f5; cursor: pointer; user-select: none; }
  th:hover { background: #ececec; }
  .sev-critical { color: #b60205; font-weight: 600; }
  .sev-high     { color: #d93f0b; font-weight: 600; }
  .sev-normal   { color: #555; }
  .sev-low      { color: #888; }
  .pill { display: inline-block; padding: 0 0.5em; border-radius: 1em; background: #ededed; font-size: 0.85em; }
</style>
</head>
<body>
<h1>AI Sherpa analyzer — {{ findings|length }} candidate change{{ '' if findings|length == 1 else 's' }}</h1>
<div class="meta">
  Generated {{ generated_at }} · input: <code>{{ input_path }}</code> · {{ session_count }} sessions analyzed
</div>
<table id="t">
<thead><tr>
  <th>#</th><th>Severity</th><th>Scenario</th><th>Bucket</th><th>Domain</th><th>Title</th><th>Confidence</th><th>Samples</th><th></th>
</tr></thead>
<tbody>
{% for f in findings %}
<tr>
  <td>{{ loop.index }}</td>
  <td class="sev-{{ f.severity }}">{{ f.severity }}</td>
  <td><span class="pill">{{ f.scenario_id }}</span></td>
  <td>{{ f.bucket }}</td>
  <td>{{ f.domain or 'any' }}</td>
  <td>{{ f.title }}</td>
  <td>{{ f.confidence }}</td>
  <td>{{ f.sample_session_paths|length }}</td>
  <td><a href="issues/{{ f._filename }}">view</a></td>
</tr>
{% endfor %}
</tbody>
</table>
<script>
document.querySelectorAll('#t th').forEach((th, i) => {
  th.addEventListener('click', () => {
    const tbody = document.querySelector('#t tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const asc = th.dataset.asc !== 'true';
    rows.sort((a, b) => {
      const av = a.children[i].innerText, bv = b.children[i].innerText;
      const n = parseFloat(av) - parseFloat(bv);
      return asc ? (isNaN(n) ? av.localeCompare(bv) : n) : (isNaN(n) ? bv.localeCompare(av) : -n);
    });
    rows.forEach(r => tbody.appendChild(r));
    th.dataset.asc = asc;
  });
});
</script>
</body>
</html>
```

- [ ] **Step 2: Extend `render.py`**

Append to `analyzer-prototype/analyzer/render.py`:

```python
from datetime import datetime, timezone
from jinja2 import Environment, FileSystemLoader, select_autoescape


def render_html_summary(
    findings: list[Finding],
    out_dir: Path,
    *,
    input_path: str,
    session_count: int,
    written_paths: list[Path],
) -> Path:
    """Write summary.html into out_dir; returns its Path."""
    out_dir = Path(out_dir)
    template_dir = Path(__file__).parent / "templates"
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        autoescape=select_autoescape(["html", "xml"]),
    )
    template = env.get_template("summary.html.j2")

    sorted_findings = sorted(findings, key=_sort_key)
    # Attach the filename each finding was written to so the template can link to it.
    annotated = []
    for f, p in zip(sorted_findings, written_paths):
        d = f.__dict__.copy()
        d["_filename"] = p.name
        annotated.append(d)

    html = template.render(
        findings=annotated,
        generated_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        input_path=input_path,
        session_count=session_count,
    )
    summary_path = out_dir / "summary.html"
    summary_path.write_text(html, encoding="utf-8")
    return summary_path
```

- [ ] **Step 3: Append a test**

Append to `tests/test_render.py`:

```python
def test_render_html_summary_emits_valid_html(tmp_path):
    findings = [_finding("high"), _finding("low")]
    written = render_markdown_files(findings, tmp_path)
    from analyzer.render import render_html_summary
    html_path = render_html_summary(
        findings, tmp_path,
        input_path="/tmp/fake", session_count=42,
        written_paths=written,
    )
    body = html_path.read_text()
    assert "<table" in body
    assert "scenario-7" in body
    assert "42 sessions analyzed" in body
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_render.py -v ; cd ..
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add analyzer-prototype/analyzer/render.py \
        analyzer-prototype/analyzer/templates/summary.html.j2 \
        analyzer-prototype/tests/test_render.py
git commit -m "feat(analyzer-prototype): HTML summary with sortable table"
```

---

## Task 8: CLI + end-to-end smoke

Wire everything together. After this task, `python -m analyzer --input tests/fixtures --output /tmp/smoke` produces real output.

**Files:**
- Create: `analyzer-prototype/analyzer/cli.py`
- Create: `analyzer-prototype/tests/test_cli_smoke.py`

- [ ] **Step 1: Write the failing test**

Create `analyzer-prototype/tests/test_cli_smoke.py`:

```python
import subprocess
import sys
from pathlib import Path

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_cli_smoke_runs_and_produces_output(tmp_path):
    # Run `python -m analyzer --input ./fixtures --output {tmp_path}` from the
    # analyzer-prototype root so the package resolves.
    proj_root = Path(__file__).parent.parent
    result = subprocess.run(
        [sys.executable, "-m", "analyzer",
         "--input", str(FIXTURE_DIR),
         "--output", str(tmp_path),
         "--scenarios", "scenario-7,scenario-8"],
        cwd=str(proj_root),
        capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0, f"CLI failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert (tmp_path / "summary.html").exists()
    issues = list((tmp_path / "issues").glob("*.md"))
    assert len(issues) >= 1
```

Run:
```bash
cd analyzer-prototype && pytest tests/test_cli_smoke.py -v ; cd ..
```
Expected: FAIL (CLI module doesn't exist or exits non-zero).

- [ ] **Step 2: Write the CLI**

Create `analyzer-prototype/analyzer/cli.py`:

```python
"""argparse-driven entry point. Run with `python -m analyzer`."""
from __future__ import annotations
import argparse
import inspect
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from analyzer.ingest import load_events
from analyzer.embeddings import make_embeddings_fn
from analyzer.detectors import ALL_DETECTORS
from analyzer.render import render_markdown_files, render_html_summary


def _read_local_aisherpa_state() -> dict:
    """Discover AI Sherpa context from local files.

    Returns keys: current_version, configured_domain, installed_skills.
    Each is None / [] if not detectable. The CLI passes whichever of these
    each detector accepts via introspection (see _call_detector).
    """
    home_claude = Path.home() / ".claude"
    claude_md = home_claude / "CLAUDE.md"
    skills_dir = home_claude / "skills"
    state: dict = {"current_version": None, "configured_domain": None, "installed_skills": []}
    if claude_md.exists():
        try:
            first_lines = claude_md.read_text(encoding="utf-8", errors="ignore").splitlines()[:3]
        except OSError:
            first_lines = []
        for line in first_lines:
            m = re.search(r"v\d{4}\.\d{2}\.\d{2}", line)
            if m and state["current_version"] is None:
                state["current_version"] = m.group(0)
            d = re.search(r"^#\s*AI Sherpa\s*[—-]\s*(\w+)", line)
            if d and state["configured_domain"] is None:
                state["configured_domain"] = d.group(1).lower()
    if skills_dir.exists():
        state["installed_skills"] = sorted(
            p.name for p in skills_dir.iterdir() if p.is_dir()
        )
    return state


def _call_detector(d, events, embeddings_fn, context: dict):
    """Call a detector, passing only kwargs from `context` that it accepts."""
    sig = inspect.signature(d)
    extra = {k: v for k, v in context.items() if k in sig.parameters}
    return list(d(events, embeddings_fn, **extra))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="analyzer",
                                     description="AI Sherpa analyzer prototype")
    parser.add_argument("--input", default=str(Path.home() / ".claude" / "projects"),
                        help="Root dir to walk for *.jsonl (default: ~/.claude/projects)")
    parser.add_argument("--output", default="./analyzer-out",
                        help="Output dir for findings (default: ./analyzer-out)")
    parser.add_argument("--scenarios", default="all",
                        help="Comma-separated scenario IDs or 'all'")
    parser.add_argument("--since", default=None,
                        help="Skip sessions older than this ISO date (e.g., 2026-04-01)")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    input_path = Path(args.input).expanduser()
    output_path = Path(args.output).expanduser()

    if args.verbose:
        print(f"[analyzer] input:  {input_path}")
        print(f"[analyzer] output: {output_path}")

    # Ingest.
    events = load_events(input_path)
    if args.since:
        cutoff = datetime.fromisoformat(args.since).replace(tzinfo=timezone.utc)
        events = events[events.timestamp >= cutoff]

    session_count = events.session_id.nunique() if not events.empty else 0
    if args.verbose:
        print(f"[analyzer] {session_count} sessions, {len(events)} events")

    # Pick detectors.
    if args.scenarios == "all":
        detectors = ALL_DETECTORS
    else:
        wanted = set(args.scenarios.split(","))
        detectors = [d for d in ALL_DETECTORS if getattr(d, "id", None) in wanted]
    if args.verbose:
        print(f"[analyzer] running {len(detectors)} detector(s)")

    embeddings_fn = make_embeddings_fn()
    context = _read_local_aisherpa_state()
    if args.verbose:
        print(f"[analyzer] context: version={context['current_version']!r}, "
              f"domain={context['configured_domain']!r}, "
              f"skills={len(context['installed_skills'])}")

    findings: list = []
    for d in detectors:
        try:
            new = _call_detector(d, events, embeddings_fn, context)
            findings.extend(new)
            if args.verbose:
                print(f"  {getattr(d, 'id', d.__name__)}: {len(new)} finding(s)")
        except Exception as exc:
            print(f"[analyzer] detector {getattr(d, 'id', d.__name__)} failed: {exc}",
                  file=sys.stderr)

    # Render.
    output_path.mkdir(parents=True, exist_ok=True)
    written = render_markdown_files(findings, output_path)
    render_html_summary(
        findings, output_path,
        input_path=str(input_path),
        session_count=session_count,
        written_paths=written,
    )

    print(f"[analyzer] {len(findings)} finding(s) → {output_path}")
    print(f"[analyzer] open {output_path / 'summary.html'} to review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run the smoke test**

Run:
```bash
cd analyzer-prototype && pytest tests/test_cli_smoke.py -v ; cd ..
```
Expected: PASS. The test fixture corpus has tool-misuse and abandonment fixtures, so at least one finding fires.

- [ ] **Step 4: Run end-to-end against fixtures manually**

Run:
```bash
cd analyzer-prototype && python -m analyzer --input tests/fixtures --output /tmp/analyzer-smoke --verbose ; cd ..
```
Expected output (substantively):
```
[analyzer] input:  …/analyzer-prototype/tests/fixtures
[analyzer] output: /tmp/analyzer-smoke
[analyzer] N sessions, M events
[analyzer] running 10 detector(s)
  scenario-3: 0 finding(s)
  scenario-7: 1 finding(s)
  …
[analyzer] X finding(s) → /tmp/analyzer-smoke
[analyzer] open /tmp/analyzer-smoke/summary.html to review.
```

Open `/tmp/analyzer-smoke/summary.html` in a browser and confirm: a table with findings, sortable columns, working "view" links to the Markdown files.

- [ ] **Step 5: Run end-to-end against real local sessions**

Run:
```bash
cd analyzer-prototype && python -m analyzer --verbose ; cd ..
```
Expected: walks your actual `~/.claude/projects/`, runs all 10 detectors, writes findings to `./analyzer-prototype/analyzer-out/`. The number of findings depends on your local data — even zero findings is a successful run.

Open `./analyzer-prototype/analyzer-out/summary.html` and self-validate: do the candidate changes look real?

- [ ] **Step 6: Commit**

```bash
git add analyzer-prototype/analyzer/cli.py \
        analyzer-prototype/tests/test_cli_smoke.py
git commit -m "feat(analyzer-prototype): CLI + end-to-end smoke test"
```

---

## Task 9: Update the program roadmap to mention Phase 0.5

Per spec §12: add a line to roadmap §13 and §14 noting Phase 0.5 exists and ships first.

**Files:**
- Modify: `docs/superpowers/specs/2026-05-28-feedback-program-roadmap.md`

- [ ] **Step 1: Update §13 (What's spec'd vs. what's not)**

Open `docs/superpowers/specs/2026-05-28-feedback-program-roadmap.md`. Find the §13 table:

```
| Phase 1 design (manual feedback + triage + release + email) | **Spec'd**: ...
```

Insert a new first row in that table:

```
| **Phase 0.5 — Analyzer prototype (local data)** | **Spec'd** + **plan**: `2026-05-29-analyzer-prototype-design.md` + `2026-05-29-analyzer-prototype.md`. Ships first to validate detection model before any infrastructure work. |
```

- [ ] **Step 2: Update §14 (Next steps)**

In §14, replace the existing step 1 (currently "User reviews this roadmap") with:

```
1. **Ship Phase 0.5 (analyzer prototype).** Run against local Claude
   Code session data; self-validate the candidate-change findings;
   tune detector thresholds. ~1 day of implementation.
2. **User reviews this roadmap and the Phase 1 spec** if not already done.
3. **Write the Phase 1 implementation plan** (done — commit `bab4924`).
4. **Implement Phase 1.** ~2–3 weeks.
```

Renumber subsequent steps accordingly.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-05-28-feedback-program-roadmap.md
git commit -m "docs(roadmap): add Phase 0.5 (analyzer prototype) to status + next steps"
```

---

## Self-review

After completing all nine tasks, run the full test suite and the smoke:

```bash
cd analyzer-prototype
pytest -v                          # all tests pass
python -m analyzer --verbose       # walks real ~/.claude/projects, produces summary.html
cd ..
git log --oneline -15              # confirms each task committed cleanly
```

The deliverable is the contents of `analyzer-prototype/analyzer-out/summary.html` plus the implementer's own judgment: *do the candidate changes feel real?* If yes, Phase 0.5 succeeded and we can productize the detector code for Phase 2a. If no, tune thresholds in the affected detector and re-run.
