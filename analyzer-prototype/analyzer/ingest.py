"""Walk JSONL session files under a root, emit a normalized events DataFrame.

If you probed a real Claude Code JSONL in Task 2 step 1 and saw fields named
differently than below (e.g., `type` is actually nested under `message.role`),
adjust `_classify_event` and `_extract_*` helpers. The test fixture is shaped
to match these assumed names; if you change the assumptions, also update the
fixture in tests/fixtures/minimal-session.jsonl.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable
import pandas as pd


_COLUMNS = [
    "session_id", "session_path", "project_path_hash",
    "timestamp", "event_type",
    "text", "tool_name", "tool_args_json", "tool_success",
    "command_first_word", "file_extension",
    "skill_name", "slash_command_name",
    "is_first_in_session",
]


def load_events(root: Path | str) -> pd.DataFrame:
    """Walk JSONL files under `root`, return all events as a DataFrame."""
    root = Path(root)
    rows: list[dict[str, Any]] = []
    for jsonl_path in root.rglob("*.jsonl"):
        rows.extend(_parse_session_file(jsonl_path))

    df = pd.DataFrame(rows, columns=_COLUMNS)
    if df.empty:
        return df

    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True, errors="coerce")
    df = df.sort_values(["session_id", "timestamp"]).reset_index(drop=True)

    # Mark first prompt per session.
    df["is_first_in_session"] = False
    first_prompts = (
        df[df.event_type == "prompt"]
        .groupby("session_id", group_keys=False)
        .head(1)
        .index
    )
    df.loc[first_prompts, "is_first_in_session"] = True
    return df


def _parse_session_file(path: Path) -> Iterable[dict[str, Any]]:
    project_path_hash = hashlib.sha256(str(path.parent).encode()).hexdigest()[:16]
    try:
        with path.open("r", encoding="utf-8") as f:
            lines = [ln for ln in f if ln.strip()]
    except OSError:
        return

    for line in lines:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        session_id = obj.get("sessionId") or obj.get("session_id") or path.stem
        timestamp = obj.get("timestamp")
        for event in _classify_event(obj):
            event.update({
                "session_id": session_id,
                "session_path": str(path),
                "project_path_hash": project_path_hash,
                "timestamp": timestamp,
            })
            # Fill in missing columns with None so DataFrame is rectangular.
            for col in _COLUMNS:
                event.setdefault(col, None)
            yield event


def _classify_event(obj: dict[str, Any]) -> Iterable[dict[str, Any]]:
    typ = obj.get("type")
    msg = obj.get("message") or {}
    content = msg.get("content")

    if typ == "user":
        if isinstance(content, str):
            if content.startswith("/"):
                yield {"event_type": "slash_command",
                       "slash_command_name": content.split()[0]}
            else:
                yield {"event_type": "prompt", "text": content}
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "tool_result":
                    yield {"event_type": "tool_result",
                           "tool_success": _infer_tool_success(block.get("content"))}
                else:
                    txt = block.get("text") if isinstance(block, dict) else None
                    if txt:
                        yield {"event_type": "prompt", "text": txt}
    elif typ == "assistant":
        if isinstance(content, str):
            yield {"event_type": "response", "text": content}
        elif isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                btyp = block.get("type")
                if btyp == "text":
                    yield {"event_type": "response", "text": block.get("text", "")}
                elif btyp == "tool_use":
                    tool_name = block.get("name", "")
                    args = block.get("input") or {}
                    args_json = json.dumps(args)
                    first_word = None
                    if tool_name == "Bash":
                        cmd = args.get("command", "")
                        first_word = cmd.strip().split(maxsplit=1)[0] if cmd else None
                    file_ext = None
                    if tool_name in ("Read", "Edit", "Write"):
                        fp = args.get("file_path", "")
                        if "." in fp:
                            file_ext = "." + fp.rsplit(".", 1)[1].lower()
                    yield {"event_type": "tool_call",
                           "tool_name": tool_name,
                           "tool_args_json": args_json,
                           "command_first_word": first_word,
                           "file_extension": file_ext}


def _infer_tool_success(content: Any) -> bool | None:
    if isinstance(content, str):
        lower = content.lower()
        if "error" in lower or "failed" in lower:
            return False
        return True
    return None
