from pathlib import Path
import shutil
import tempfile
import pandas as pd
from analyzer.ingest import load_events
from analyzer.embeddings import make_embeddings_fn

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def _events(name: str) -> pd.DataFrame:
    """Load a single fixture in isolation."""
    src = FIXTURE_DIR / name
    with tempfile.TemporaryDirectory() as tmp_str:
        tmp = Path(tmp_str)
        if src.is_dir():
            for f in src.rglob("*.jsonl"):
                shutil.copy(f, tmp / f.name)
        else:
            shutil.copy(src, tmp / src.name)
        return load_events(tmp)


def test_detect_repeated_priming():
    from analyzer.detectors.embedding import detect_repeated_priming
    fn = make_embeddings_fn()
    findings = list(detect_repeated_priming(_events("repeated-priming"), embeddings_fn=fn))
    assert any(f.scenario_id == "scenario-5" for f in findings), \
        f"expected scenario-5 finding, got: {[f.scenario_id for f in findings]}"
