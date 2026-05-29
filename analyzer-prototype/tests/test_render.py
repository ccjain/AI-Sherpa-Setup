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
