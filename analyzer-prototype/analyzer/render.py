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
