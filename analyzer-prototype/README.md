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
