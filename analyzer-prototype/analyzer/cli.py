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

    print(f"[analyzer] {len(findings)} finding(s) -> {output_path}")
    print(f"[analyzer] open {output_path / 'summary.html'} to review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
