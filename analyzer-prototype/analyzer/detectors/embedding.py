"""Embedding-based detectors — sentence-transformer + HDBSCAN clustering."""
from typing import Iterable
import numpy as np
import pandas as pd
from analyzer.detectors.base import Finding


def _is_real_user_prompt(text: str) -> bool:
    """Return True if text looks like an actual user message, not system metadata.

    Excludes:
    - Empty / whitespace-only
    - Starts with a likely-system tag like `<local-command-caveat>`, `<system-reminder>`,
      `<command-name>`, `<command-message>`, `<command-args>`, `<local-command-stdout>`,
      `<command-output>`, `<user-prompt-submit-hook>` — anything beginning with `<` and
      a known-system word, or just any `<...>` opener followed by ASCII text.
    - Begins with a slash command (`/foo`) — those are slash-command shells, not prompts.
    """
    if not text:
        return False
    s = text.lstrip()
    if not s:
        return False
    if s.startswith("/"):
        return False
    if s.startswith("<") and ">" in s[:200]:
        # Looks like an HTML/XML-style tag opener within the first 200 chars.
        # That's overwhelmingly a system-injected wrapper, not a user prompt.
        return False
    return True


def _cluster_labels(embs: np.ndarray, min_cluster_size: int = 3) -> np.ndarray:
    """Cluster embeddings, returning integer labels (-1 = noise).

    Uses HDBSCAN for larger corpora (>=15 points) where it performs well.
    Falls back to AgglomerativeClustering with a cosine distance threshold for
    smaller corpora where HDBSCAN collapses everything to noise.
    """
    n = embs.shape[0]
    if n >= 15:
        from sklearn.cluster import HDBSCAN
        return HDBSCAN(min_cluster_size=min_cluster_size, metric="cosine").fit_predict(embs)

    # Small corpus: agglomerative with a similarity threshold.
    # cosine distance < 0.25 ≈ cosine similarity > 0.75 — clearly related prompts.
    from sklearn.cluster import AgglomerativeClustering
    from sklearn.metrics.pairwise import cosine_similarity
    raw = AgglomerativeClustering(
        n_clusters=None,
        distance_threshold=0.25,
        metric="cosine",
        linkage="average",
    ).fit_predict(embs)
    # Suppress clusters smaller than min_cluster_size (mark as noise = -1).
    from collections import Counter
    counts = Counter(raw.tolist())
    return np.array([l if counts[l] >= min_cluster_size else -1 for l in raw])


def detect_repeated_priming(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    if events.empty:
        return []
    first_prompts = events[
        (events.event_type == "prompt") & (events.is_first_in_session == True)
    ]
    if len(first_prompts) < 3:
        return []

    texts_all = first_prompts.text.fillna("").str.slice(0, 500).tolist()
    paths_all = first_prompts.session_path.tolist()
    # NEW: filter out system-tag / slash-command first prompts.
    pairs = [(t, p) for t, p in zip(texts_all, paths_all) if _is_real_user_prompt(t)]
    if len(pairs) < 3:
        return []
    texts = [t for t, _ in pairs]
    paths = [p for _, p in pairs]

    embs = embeddings_fn(texts)
    if embs.shape[0] == 0:
        return []

    labels = _cluster_labels(embs, min_cluster_size=3)

    findings = []
    for label in set(labels.tolist()) - {-1}:
        idxs = [i for i, l in enumerate(labels) if l == label]
        sample_text = texts[idxs[0]]
        sample_paths = [paths[i] for i in idxs[:5]]
        findings.append(Finding(
            scenario_id="scenario-5",
            title=f"Repeated session-opening prompt across {len(idxs)} sessions",
            bucket="add-rule",
            domain=None,
            severity="high" if len(idxs) >= 10 else "normal",
            confidence="high" if len(idxs) >= 5 else "medium",
            evidence_md=(
                f"**{len(idxs)} sessions** open with a near-identical prompt opening. "
                f"This is a strong signal that the content belongs in a CLAUDE.md "
                f"rule or a skill's `description:` instead of being re-typed each session.\n\n"
                f"**Sample opening (cluster centroid):**\n\n"
                f"```\n{sample_text[:400]}\n```\n\n"
                f"**Suggested change:** review the sample sessions, distill the "
                f"recurring context into a one-paragraph rule, and add it to the "
                f"appropriate `domains/<X>/CLAUDE.md` or `core/CLAUDE.md`."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_repeated_priming.id = "scenario-5"


def detect_missed_skill_fire(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    """Scenario 1: skill description matches session topic, skill never fired.

    Conservative on a small corpus: only fires when we see >=10 sessions with
    no skill_invoked events at all. Real per-session matching requires reading
    the installed skills' description: fields, which the orchestrator passes
    via a future kwarg; for now this stays a degraded-mode finding.
    """
    if events.empty:
        return []
    sessions = events.session_id.unique()
    if len(sessions) < 10:
        return []
    sessions_with_skill_fires = events[events.event_type == "skill_invoked"].session_id.nunique()
    if sessions_with_skill_fires >= len(sessions) * 0.10:
        return []  # at least 10% of sessions invoked a skill — healthy
    return [Finding(
        scenario_id="scenario-1",
        title=f"Only {sessions_with_skill_fires}/{len(sessions)} sessions invoked any installed skill",
        bucket="skill-fix",
        domain=None,
        severity="normal",
        confidence="low",
        evidence_md=(
            f"Of {len(sessions)} analyzed sessions, only **{sessions_with_skill_fires}** "
            f"invoked any installed skill. This is a low-confidence aggregate signal that "
            f"installed skill `description:` fields may not match real prompts. Per-session "
            f"matching against skill descriptions is deferred to Phase 2a.\n\n"
            f"**Suggested change:** review each installed skill's `description:` field; "
            f"tighten or remove any that are not firing in practice."
        ),
        sample_session_paths=[],
    )]

detect_missed_skill_fire.id = "scenario-1"


def detect_repeated_correction(events: pd.DataFrame, embeddings_fn) -> Iterable[Finding]:
    """Scenario 2: same correction-after-AI-output pattern repeated.

    Full implementation requires diffing each user prompt that follows an
    assistant response and clustering the diff deltas. For v0, fire only when
    we see a strong signal: >=5 user prompts that all start with explicit
    correction phrases ("actually", "no, I meant", "you should") and cluster
    tightly.
    """
    if events.empty:
        return []
    prompts = events[
        (events.event_type == "prompt") & (events.is_first_in_session == False)
    ]
    if len(prompts) < 5:
        return []
    correction_phrases = ["actually", "no, ", "wait,", "you should", "i meant"]
    text_l = prompts.text.fillna("").str.lower()
    correction_mask = text_l.apply(lambda t: any(p in t for p in correction_phrases))
    corrections = prompts[correction_mask]
    if len(corrections) < 5:
        return []

    texts_all = corrections.text.fillna("").str.slice(0, 300).tolist()
    paths_all = corrections.session_path.tolist()
    # NEW: filter out system-tag prompts.
    pairs = [(t, p) for t, p in zip(texts_all, paths_all) if _is_real_user_prompt(t)]
    if len(pairs) < 3:
        return []
    texts = [t for t, _ in pairs]
    paths = [p for _, p in pairs]

    embs = embeddings_fn(texts)
    if embs.shape[0] < 3:
        return []
    labels = _cluster_labels(embs, min_cluster_size=3)
    findings = []
    for label in set(labels.tolist()) - {-1}:
        idxs = [i for i, l in enumerate(labels) if l == label]
        sample_text = texts[idxs[0]]
        sample_paths = [paths[i] for i in idxs[:5]]
        findings.append(Finding(
            scenario_id="scenario-2",
            title=f"Repeated user-correction pattern across {len(idxs)} sessions",
            bucket="add-rule",
            domain=None,
            severity="normal",
            confidence="medium",
            evidence_md=(
                f"**{len(idxs)} sessions** contain a near-identical user correction "
                f"following an assistant response — a recurring signal that the same "
                f"AI mistake is being corrected by hand repeatedly.\n\n"
                f"**Sample correction:**\n\n```\n{sample_text[:300]}\n```\n\n"
                f"**Suggested change:** distill the correction into a rule and add it "
                f"to the appropriate `domains/<X>/CLAUDE.md`."
            ),
            sample_session_paths=sample_paths,
        ))
    return findings

detect_repeated_correction.id = "scenario-2"
