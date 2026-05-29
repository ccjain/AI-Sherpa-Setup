from pathlib import Path
import pandas as pd
from analyzer.ingest import load_events

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def _events(name: str) -> pd.DataFrame:
    """Helper: load just one fixture file as a DataFrame.

    Uses a temp dir so sibling fixtures don't leak into the test."""
    import shutil, tempfile
    tmp = Path(tempfile.mkdtemp())
    src = FIXTURE_DIR / name
    if src.is_dir():
        # Copy the directory's *.jsonl files into the tmp dir
        for f in src.rglob("*.jsonl"):
            shutil.copy(f, tmp / f.name)
    else:
        # Fall back to a single file
        shutil.copy(src, tmp / src.name)
    return load_events(tmp)


def test_detect_tool_misuse():
    from analyzer.detectors.tabular import detect_tool_misuse
    findings = list(detect_tool_misuse(_events("tool-misuse"), embeddings_fn=None))
    assert len(findings) == 1
    f = findings[0]
    assert f.scenario_id == "scenario-7"
    assert "cat" in f.title.lower()
    assert f.bucket == "add-rule"
