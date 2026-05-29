import subprocess
import sys
from pathlib import Path

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_cli_smoke_runs_and_produces_output(tmp_path):
    proj_root = Path(__file__).parent.parent  # analyzer-prototype/
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
