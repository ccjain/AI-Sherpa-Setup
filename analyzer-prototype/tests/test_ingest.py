from pathlib import Path
import pandas as pd
from analyzer.ingest import load_events

FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_load_events_returns_dataframe_with_expected_columns():
    events = load_events(FIXTURE_DIR)
    expected_cols = {
        "session_id", "session_path", "project_path_hash",
        "timestamp", "event_type", "text", "tool_name",
        "command_first_word", "is_first_in_session",
        "slash_command_name",
    }
    assert expected_cols.issubset(events.columns), \
        f"missing: {expected_cols - set(events.columns)}"


def test_load_events_recognises_prompt_response_tool_call_tool_result_slashcmd():
    events = load_events(FIXTURE_DIR)
    types_seen = set(events.event_type.unique())
    assert {"prompt", "response", "tool_call", "tool_result", "slash_command"} <= types_seen


def test_load_events_marks_first_prompt_in_session():
    events = load_events(FIXTURE_DIR)
    first_prompts = events[(events.event_type == "prompt") & (events.is_first_in_session == True)]
    assert len(first_prompts) == 1, f"expected exactly 1 first prompt, got {len(first_prompts)}"


def test_load_events_extracts_bash_command_first_word():
    events = load_events(FIXTURE_DIR)
    bash_calls = events[(events.event_type == "tool_call") & (events.tool_name == "Bash")]
    assert (bash_calls.command_first_word == "cat").all()


def test_load_events_handles_empty_dir(tmp_path):
    events = load_events(tmp_path)
    assert isinstance(events, pd.DataFrame)
    assert len(events) == 0
