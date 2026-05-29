"""Detector registry.

ALL_DETECTORS is the ordered list used by analyzer.cli to run every
detector against the events DataFrame. Add a new scenario by appending
its function here.

The try/except below makes this file importable before the tabular and
embedding modules exist (created in Tasks 3 and 5). Once they exist the
import succeeds and ALL_DETECTORS is populated.
"""
ALL_DETECTORS = []

try:
    from analyzer.detectors import tabular, embedding
    ALL_DETECTORS = [
        # Tabular (no embeddings needed)
        tabular.detect_domain_mismatch,        # scenario-3
        tabular.detect_tool_misuse,            # scenario-7
        tabular.detect_abandonment,            # scenario-8
        tabular.detect_accept_then_revert,     # scenario-10
        tabular.detect_skill_roi,              # scenario-11
        tabular.detect_onboarding_velocity,    # scenario-12
        tabular.detect_stale_install,          # scenario-13
        # Embedding-based
        embedding.detect_missed_skill_fire,    # scenario-1
        embedding.detect_repeated_correction,  # scenario-2
        embedding.detect_repeated_priming,     # scenario-5
    ]
except ImportError:
    # Detector modules not yet created (Tasks 3 and 5). ALL_DETECTORS
    # stays empty; the registry will populate once the modules exist.
    pass
