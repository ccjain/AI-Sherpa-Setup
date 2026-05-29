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


def detect_skill_roi(
    events: pd.DataFrame,
    embeddings_fn=None,
    installed_skills: list[str] | None = None,
) -> Iterable[Finding]:
    if events.empty or not installed_skills:
        return []
    total_sessions = events.session_id.nunique()
    if total_sessions == 0:
        return []

    fired = (
        events[events.event_type == "skill_invoked"]
        .groupby("skill_name").session_id.nunique()
        .to_dict()
    )

    findings = []
    for skill in installed_skills:
        sessions_fired_in = fired.get(skill, 0)
        rate = sessions_fired_in / total_sessions
        if rate < 0.02:  # less than 2% of sessions
            findings.append(Finding(
                scenario_id="scenario-11",
                title=f"Skill `{skill}` has near-zero fire rate ({sessions_fired_in}/{total_sessions} sessions)",
                bucket="skill-fix",
                domain=None,
                severity="low" if sessions_fired_in > 0 else "normal",
                confidence="medium",
                evidence_md=(
                    f"`{skill}` is installed but fired in only **{sessions_fired_in} of "
                    f"{total_sessions} analyzed sessions** ({rate:.1%}).\n\n"
                    f"**Suggested change:** review the skill's `description:` field. "
                    f"Either tighten it to match real usage patterns, or remove the "
                    f"skill from the install list if it is no longer relevant."
                ),
                sample_session_paths=[],
            ))
    return findings

detect_skill_roi.id = "scenario-11"


_EXTENSION_TO_DOMAIN = {
    ".c": "embedded", ".h": "embedded", ".cpp": "embedded",
    ".py": "data",
    ".ts": "web", ".tsx": "web", ".js": "web", ".jsx": "web",
    ".go": "devops", ".tf": "devops",
}


def detect_domain_mismatch(
    events: pd.DataFrame,
    embeddings_fn=None,
    configured_domain: str | None = None,
) -> Iterable[Finding]:
    if events.empty or not configured_domain:
        return []
    edits = events[events.event_type == "tool_call"]
    edits = edits[edits.file_extension.notna()]
    if edits.empty:
        return []
    inferred = edits.file_extension.map(_EXTENSION_TO_DOMAIN).dropna()
    if inferred.empty:
        return []
    top_inferred = inferred.value_counts().idxmax()
    if top_inferred == configured_domain:
        return []
    return [Finding(
        scenario_id="scenario-3",
        title=f"Configured domain `{configured_domain}` but file extensions suggest `{top_inferred}`",
        bucket="setup-fix",
        domain=None,
        severity="normal",
        confidence="medium",
        evidence_md=(
            f"The current AI Sherpa install is configured for domain "
            f"`{configured_domain}`, but the files touched across the analyzed "
            f"sessions match the `{top_inferred}` domain.\n\n"
            f"**Suggested change:** re-run `setup --reconfigure` and pick "
            f"`{top_inferred}`, or update the onboarding doc if this is "
            f"intentional mixed work."
        ),
        sample_session_paths=edits.session_path.unique().tolist()[:3],
    )]

detect_domain_mismatch.id = "scenario-3"


def detect_onboarding_velocity(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    session_lengths = (
        events.groupby("session_id")
        .agg(start=("timestamp", "min"), end=("timestamp", "max"))
    )
    session_lengths["minutes"] = (session_lengths.end - session_lengths.start).dt.total_seconds() / 60.0
    if len(session_lengths) < 5:
        return []
    median_minutes = session_lengths.minutes.median()
    return [Finding(
        scenario_id="scenario-12",
        title=f"Median session length: {median_minutes:.1f} min across {len(session_lengths)} sessions",
        bucket="docs",
        domain=None,
        severity="low",
        confidence="low",
        evidence_md=(
            f"Informational. Across the analyzed corpus, median session length "
            f"is **{median_minutes:.1f} minutes** over {len(session_lengths)} sessions.\n\n"
            f"Useful baseline for tracking onboarding velocity once multi-engineer "
            f"data is available (Phase 1.5+)."
        ),
        sample_session_paths=[],
    )]

detect_onboarding_velocity.id = "scenario-12"


def detect_stale_install(
    events: pd.DataFrame,
    embeddings_fn=None,
    current_version: str | None = None,
) -> Iterable[Finding]:
    if not current_version:
        return []
    return [Finding(
        scenario_id="scenario-13",
        title=f"Current install version: {current_version}",
        bucket="docs",
        domain=None,
        severity="low",
        confidence="low",
        evidence_md=(
            f"Informational. The current AI Sherpa install reports version "
            f"`{current_version}`. Once Phase 1 ships and a `VERSION` file is "
            f"updated per release, this detector will flag installs more than N "
            f"releases behind."
        ),
        sample_session_paths=[],
    )]

detect_stale_install.id = "scenario-13"
