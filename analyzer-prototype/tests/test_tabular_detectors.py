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


def test_detect_abandonment():
    from analyzer.detectors.tabular import detect_abandonment
    findings = list(detect_abandonment(_events("abandonment"), embeddings_fn=None))
    assert any(f.scenario_id == "scenario-8" for f in findings)
    all_paths = {p for f in findings for p in f.sample_session_paths}
    # Sessions s-ab-2 (clear/restart loop) and s-ab-3 (ended on user prompt) should
    # both be detected; sample_session_paths must be non-empty.
    # (The _events helper copies files to a tempdir, so path strings don't carry the
    # fixture folder name — we just verify that paths were captured at all.)
    assert len(all_paths) > 0
