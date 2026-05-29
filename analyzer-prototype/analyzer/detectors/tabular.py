"""Tabular detectors — pure SQL/pandas over the events DataFrame.

Each detector function takes (events, embeddings_fn) and returns
Iterable[Finding]. Embeddings are ignored here but the signature
matches the Detector protocol for uniformity.
"""
from typing import Iterable
import pandas as pd
from analyzer.detectors.base import Finding


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


def detect_accept_then_revert(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    import json
    edits = events[
        (events.event_type == "tool_call") & events.tool_name.isin(["Edit", "Write"])
    ].copy()
    if edits.empty:
        return []
    edits = edits.sort_values(["session_id", "timestamp"]).reset_index(drop=True)

    # Parse file_path out of tool_args_json.
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
