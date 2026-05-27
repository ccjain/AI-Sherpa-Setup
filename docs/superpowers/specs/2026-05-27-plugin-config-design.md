# AI Sherpa — Plugin Config Design

**Date:** 2026-05-27
**Status:** Approved

---

## Goal

Replace hardcoded plugin lists in setup scripts with a single `plugins.json` config file. Admin adds or removes plugins by editing the file — setup scripts pick up changes automatically with no code changes required.

## Architecture

One config file at the repo root (`plugins.json`) read by both `setup.sh` and `setup.ps1` at install time.

```
plugins.json          ← admin edits this
setup.sh              ← reads plugins.json, installs accordingly
setup.ps1             ← reads plugins.json, installs accordingly
```

## Config File Format

**File:** `plugins.json` (repo root)

```json
{
  "global": [
    { "name": "superpowers", "marketplace": "claude-plugins-official" }
  ],
  "domains": {
    "embedded": [],
    "web": [
      { "name": "vercel",     "marketplace": "claude-plugins-official" },
      { "name": "playwright", "marketplace": "claude-plugins-official" }
    ],
    "backend": [],
    "data":    [],
    "devops":  []
  }
}
```

### Plugin Entry Types

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Plugin name (used in `claude plugin install`) |
| `marketplace` | For official plugins | Marketplace identifier, e.g. `claude-plugins-official` |
| `github` | For GitHub plugins | GitHub `owner/repo`, e.g. `safishamsi/graphify` |

Exactly one of `marketplace` or `github` must be present per entry.

### GitHub Plugin Requirement

GitHub-based entries require the target repo to have a valid Claude Code plugin structure (a `.claude-plugin/marketplace.json` file). If the repo lacks this structure, `claude plugin marketplace add` will fail and setup will log a warning and continue.

## Install Behaviour

At setup time:

1. Read `plugins.json` from the AI Sherpa repo root
2. Install all entries in `global` (every domain, every run)
3. Install all entries in `domains.<chosen-domain>`
4. For each `"marketplace"` entry: `claude plugin install <name>@<marketplace> --scope user`
5. For each `"github"` entry:
   - `claude plugin marketplace add <github-repo> --scope user`
   - `claude plugin install <name> --scope user`
   - On failure: log warning and continue (non-fatal)

## Update Behaviour (`--update` flag)

`setup.bat --update` / `setup.sh --update`:
- Re-reads `plugins.json`
- Runs `claude plugin update <name>` for every entry in `global`
- Does NOT touch domain plugins or project CLAUDE.md

## How Admin Adds a Plugin

1. Open `plugins.json`
2. Add an entry to `global` (all domains) or to a specific domain array
3. Commit and push
4. Next developer who runs `setup.bat` or `setup.sh` gets it automatically

No script changes required.

## Error Handling

- Missing `plugins.json`: setup exits with a clear error message pointing to the file
- Unknown domain key in `plugins.json`: logged as a warning, setup continues with an empty domain plugin list
- Failed plugin install (network, wrong structure): logged as a warning, setup continues — partial install is better than no install
- Malformed JSON: setup exits with a parse error message

## Files Changed

| File | Change |
|---|---|
| `plugins.json` | Create — new config file |
| `setup.ps1` | Replace hardcoded plugin calls with JSON reader + install loop |
| `setup.sh` | Replace hardcoded plugin calls with JSON reader + install loop |
