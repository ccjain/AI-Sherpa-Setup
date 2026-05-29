"""Tabular detectors — pure SQL/pandas over the events DataFrame.

Each detector function takes (events, embeddings_fn) and returns
Iterable[Finding]. Embeddings are ignored here but the signature
matches the Detector protocol for uniformity.
"""
from typing import Iterable
import json
import pandas as pd
from analyzer.detectors.base import Finding


def _safe_file_path_from_args(j):
    """Pull file_path from a tool_args_json string. Tolerates None and malformed JSON."""
    if not isinstance(j, str):
        return None
    try:
        return json.loads(j).get("file_path")
    except (json.JSONDecodeError, AttributeError):
        return None


def detect_tool_misuse(events: pd.DataFrame, embeddings_fn=None) -> Iterable[Finding]:
    if events.empty:
        return []
    bash_calls = events[(events.event_type == "tool_call") & (events.tool_name == "Bash")]
    suspect = bash_calls[bash_calls.command_first_word.isin(["cat", "head", "tail", "grep"])]
    if suspect.empty:
        return []

    findings = []
    for cmd, group in suspect.groupby("command_first_word"):
        count = len(group)
        if count < 5:    # per-command threshold; was aggregate before
            continue
        replacement = {"cat": "Read", "head": "Read", "tail": "Read", "grep": "Grep"}[cmd]
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
    edits = events[
        (events.event_type == "tool_call") & events.tool_name.isin(["Edit", "Write"])
    ].copy()
    if edits.empty:
        return []
    edits = edits.sort_values(["session_id", "timestamp"]).reset_index(drop=True)

    # Parse file_path out of tool_args_json.
    edits["file_path"] = edits.tool_args_json.apply(_safe_file_path_from_args)

    # Episode = a (session_id, file_path) group with at least one pair of
    # consecutive edits within 60 seconds. Counted once per group regardless
    # of how many rapid edits are in the group.
    episodes = 0
    sample_paths: list[str] = []
    for _, group in edits.groupby(["session_id", "file_path"]):
        if len(group) < 2:
            continue
        ts = group.sort_values("timestamp").timestamp.tolist()
        has_rapid_pair = any(
            (ts[i + 1] - ts[i]).total_seconds() <= 60
            for i in range(len(ts) - 1)
        )
        if has_rapid_pair:
            episodes += 1
            sample_paths.append(group.session_path.iloc[0])

    if episodes < 3:
        return []

    return [Finding(
        scenario_id="scenario-10",
        title=f"{episodes} accept-then-revert episodes detected",
        bucket="refine-rule",
        domain=None,
        severity="normal",
        confidence="high" if episodes >= 10 else "medium",
        evidence_md=(
            f"**{episodes} (session, file) combinations** showed at least one pair "
            f"of consecutive edits within 60 seconds — a signal that Claude's first "
            f"edit was close but not quite right and the user had to follow up "
            f"immediately. (Multiple rapid edits in the same file count as one "
            f"episode here; raw pair counts would be much higher.)\n\n"
            f"**Suggested change:** sample these sessions; if a recurring pattern "
            f"is visible in what Claude got *almost* right, refine the relevant rule."
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

    # Bucket every installed skill by fire rate.
    zero_fire: list[str] = []
    low_fire: list[tuple[str, int]] = []   # (skill, count) for rate < 2% but > 0
    for skill in sorted(installed_skills):
        sessions_fired_in = fired.get(skill, 0)
        rate = sessions_fired_in / total_sessions
        if sessions_fired_in == 0:
            zero_fire.append(skill)
        elif rate < 0.02:
            low_fire.append((skill, sessions_fired_in))

    if not zero_fire and not low_fire:
        return []

    lines: list[str] = []
    if zero_fire:
        lines.append(f"**Skills that never fired** ({len(zero_fire)}):")
        lines.extend(f"- `{s}`" for s in zero_fire)
        lines.append("")
    if low_fire:
        lines.append(f"**Skills with very low fire rate** ({len(low_fire)}):")
        lines.extend(f"- `{s}` — fired in {c} of {total_sessions} sessions" for s, c in low_fire)
        lines.append("")

    body = "\n".join(lines)
    return [Finding(
        scenario_id="scenario-11",
        title=f"{len(zero_fire) + len(low_fire)} of {len(installed_skills)} installed skills have near-zero fire rate",
        bucket="skill-fix",
        domain=None,
        severity="normal",
        confidence="medium",
        evidence_md=(
            f"Across {total_sessions} analyzed sessions, the following installed skills "
            f"fired in fewer than 2% of sessions:\n\n"
            f"{body}\n"
            f"**Suggested change:** for each listed skill, either tighten its "
            f"`description:` field so it matches the prompts you actually write, or "
            f"remove it from the install list if it's not relevant to your work."
        ),
        sample_session_paths=[],
    )]

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
