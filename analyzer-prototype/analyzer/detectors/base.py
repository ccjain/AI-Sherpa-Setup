"""Long-lived types shared by every detector.

These are the contract. Detector implementations may change; this file
should change very rarely.
"""
from dataclasses import dataclass
from typing import Callable, Iterable, Protocol
import numpy as np
import pandas as pd

EmbeddingsFn = Callable[[list[str]], np.ndarray]


@dataclass(frozen=True)
class Finding:
    scenario_id: str          # "scenario-7", matches roadmap §3 numbering
    title: str                # one-line headline; becomes the Markdown <h1>
    bucket: str               # roadmap §12.2: "add-rule" | "refine-rule" |
                              #   "skill-fix" | "plugin-change" |
                              #   "setup-fix" | "docs"
    domain: str | None        # "embedded" | "web" | … | None if any/unknown
    severity: str             # "critical" | "high" | "normal" | "low"
    confidence: str           # "high" | "medium" | "low"
    evidence_md: str          # Markdown body (≥ one paragraph)
    sample_session_paths: list[str]   # absolute paths to source JSONL


class Detector(Protocol):
    id: str
    def __call__(
        self,
        events: pd.DataFrame,
        embeddings_fn: EmbeddingsFn,
    ) -> Iterable[Finding]: ...
