"""Render Finding objects to Markdown files + HTML summary."""
from __future__ import annotations
import re
from datetime import datetime, timezone
from pathlib import Path
from analyzer.detectors.base import Finding
from jinja2 import Environment, FileSystemLoader, select_autoescape


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
