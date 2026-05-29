# `submit-feedback.{ps1,sh}` — calling convention (ABI)

The `/ai-sherpa-feedback` slash command shells out to a helper script
(`submit-feedback.ps1` on Windows, `submit-feedback.sh` elsewhere). The same
helper is also called non-interactively by the Gate E auto-filer. This file
documents the calling convention both producers must respect.

See `docs/superpowers/2026-05-30-program-v2.md` §5.1 for context.

## Invocation modes

The helper supports two modes selected by the `--mode` flag.

### `--mode=interactive` (default)

Used by the `/ai-sherpa-feedback` slash command. Behavior:

- Reads the four-question complaint via stdin prompts (or from `--complaint-file`
  if Claude has already collected it).
- Auto-collects environment context (`ai_sherpa_version` from `VERSION`, `os`
  from platform detection, `domain` from the user's setup config, active plugins
  and skills via `gh api` / config inspection).
- Captures `session_ref.session_id` from `$env:CLAUDE_SESSION_ID` (PowerShell) or
  `$CLAUDE_SESSION_ID` (bash). Empty string is acceptable; the field is omitted
  rather than null.
- Renders the assembled Issue body for review.
- Asks for explicit confirmation before submission. NEVER auto-submits in this mode.
- Submits via `gh issue create` using the developer's own `gh` auth.

### `--mode=batch`

Used by the Gate E auto-filer. Behavior:

- Reads the full payload (already-assembled, conformant to
  `schemas/feedback_issue.schema.json`) from stdin as one JSON document, OR
  from `--payload-file <path>`.
- Performs schema validation against `feedback_issue.schema.json`; exits non-zero
  on failure without submitting.
- Submits via `gh issue create` using the **`AI_SHERPA_BOT_TOKEN`** environment
  variable (NOT the developer's `gh` auth). The token must have only `issues:write`
  scope.
- Prints the created Issue number to stdout, nothing else, on success.

## Flags

| Flag | Modes | Description |
|---|---|---|
| `--mode=interactive\|batch` | both | Default: interactive. |
| `--payload-file <path>` | batch | Path to a JSON file matching `feedback_issue.schema.json`. Mutually exclusive with stdin payload. |
| `--complaint-file <path>` | interactive | Pre-filled complaint object (skips the four-question prompts). |
| `--dry-run` | both | Print the assembled Issue body to stdout; do not call `gh`. Useful for testing. |
| `--labels-extra <comma,list>` | both | Append additional labels beyond what schema rules produce. Validated against `schemas/label_taxonomy.yml`. |
| `--repo <owner/repo>` | both | Override the target repo. Default reads from `.git/config` or `AI_SHERPA_FEEDBACK_REPO` env. |

## Environment variables read

| Variable | Modes | Required? | Description |
|---|---|---|---|
| `CLAUDE_SESSION_ID` | interactive | optional | Captured into `session_ref.session_id`. |
| `AI_SHERPA_BOT_TOKEN` | batch | required | GitHub PAT or installation token with `issues:write`. |
| `AI_SHERPA_FEEDBACK_REPO` | both | optional | Override target repo (e.g., for fork testing). |
| `AI_SHERPA_HELPER_LOG` | both | optional | Path to append a structured log line per invocation. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Issue created (success) OR dry-run completed. |
| `1` | Schema validation failed (batch mode) or user cancelled (interactive). |
| `2` | `gh` not installed or not authed. |
| `3` | Network error reaching GitHub. |
| `4` | GitHub returned 4xx (often: missing permissions, invalid labels). |
| `5` | GitHub returned 5xx (transient — caller may retry). |
| Any other non-zero | Unexpected internal error; check stderr. |

## stdin / stdout contract

- **interactive stdin**: line-buffered text prompts and responses. Not a
  programmatic contract; humans only.
- **batch stdin**: a single valid JSON object conforming to
  `feedback_issue.schema.json`. Trailing whitespace permitted.
- **stdout (success, batch)**: a single line containing only the created Issue
  number as a decimal integer, followed by a newline. No other output.
- **stdout (success, interactive)**: human-readable confirmation including the
  Issue URL.
- **stderr**: warnings and errors. Not parsed by callers; for human/log
  consumption only.

## Idempotency

The helper does NOT dedupe. Calling it twice with the same payload creates two
Issues. Dedup is the caller's responsibility:
- Interactive caller: the human reviews and confirms.
- Batch caller (Gate E auto-filer): consults the `fingerprint` field on prior
  Issues via `gh issue list --search "fingerprint:<value>"` before invoking,
  per `feedback_issue.schema.json` finding.fingerprint description.

## Versioning

The helper script declares its ABI version with `submit-feedback --abi-version`.
Current version: `1`.

A change that is non-backward-compatible (renames a flag, changes exit codes,
changes the stdout contract) bumps the ABI version. The Gate E auto-filer
inspects the ABI version at startup and refuses to call a helper with an
unsupported version.

## History

- v1 (2026-05-30): initial ABI matching the v2 program brief.
