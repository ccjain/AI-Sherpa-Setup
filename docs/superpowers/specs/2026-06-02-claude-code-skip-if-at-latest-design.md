# Claude Code Skip-If-At-Latest — Design

**Status:** Draft, pending review
**Date:** 2026-06-02
**Owner:** AI Sherpa core
**Related files:** `setup.ps1` (`Install-ClaudeCode`), `setup.sh` (`install_claude_code` equivalent)

---

## Summary

Add a registry-vs-local version check before invoking `npm install -g
@anthropic-ai/claude-code@latest`. Skip the install when local equals npm's
published latest; upgrade only when actually behind. Matches the pattern we
just shipped for PyPI / cargo tools — re-runs become fast and quiet, explicit
upgrades go through `setup.bat --update`.

Net effect: no more 5–15 seconds of npm churn (plus the EPERM cleanup
warnings caused by the running `claude.exe` being locked) on every plain
re-run of `setup.bat`.

## Goal

For each `setup.bat` / `setup.sh` invocation that finds Claude Code already
installed locally, the user's experience should be:

- If local **==** npm registry's latest stable → log a single OK line, skip
  `npm install` entirely.
- If local **<** registry's latest → run the upgrade with a precise log
  ("Upgrading X → Y") instead of today's vague "Upgrading to latest...".
- If the registry query fails (offline, corporate firewall, npm view broken)
  → fall through to the existing upgrade attempt. **Never leave the user
  worse off than today.**
- If the user passed `--update` explicitly → always run `npm install`. No
  registry query (the user already told us they want to update; don't pretend
  to check).

## Non-goals

- **Same treatment for Node.js / Git.** Their `winget upgrade` is fast and
  quiet enough that the query overhead isn't worth it. Separate concern.
- **Caching `npm view` results across runs.** A single query per setup run is
  ~300ms; caching adds complexity (invalidation, schema, file location) for
  no measurable benefit.
- **Notifying user when behind but not running --update.** When `local <
  latest`, we just run the upgrade automatically (same as today's behavior).
  No separate "update available, do you want to install?" prompt.
- **Probing for pre-release tags.** Treat `npm view @anthropic-ai/claude-code
  version` (default = `latest` tag) as the only target. Pre-releases /
  `@beta` are out of scope.

## Background — current behavior

`setup.ps1`'s `Install-ClaudeCode` and its `setup.sh` counterpart always run
`npm install -g @anthropic-ai/claude-code@latest` when Claude Code is already
installed:

```powershell
# Always try to bump to latest so newly-added CLI flags ... are available.
# npm install -g is idempotent and a no-op if already at latest.
Write-Info "Claude Code $current found. Upgrading to latest..."
npm install -g @anthropic-ai/claude-code@latest
```

The "no-op if already at latest" comment is partially correct — npm doesn't
modify the install if versions match. But it still:

1. Hits the registry to resolve `@latest`.
2. Resolves the full dependency tree.
3. Touches `node_modules/.bin/claude.exe` and adjacent files (which is why
   `npm warn cleanup EPERM unlink claude.exe` appears every time — the
   running `claude.exe` is locked because the user almost certainly launched
   setup from inside Claude Code).
4. Takes 5–15 seconds even on a no-op.

For comparison, `Install-Git` says `Git 2.51.0 OK (>= 2.30.0).` and exits.
That's the experience Claude Code should match.

## Architecture

```
setup.ps1
├─ Get-NpmLatestVersion           ← new helper
│   └─ runs `npm view @anthropic-ai/claude-code version`
│   └─ parses with existing Get-VersionFromString
│   └─ returns [version] or $null on ANY failure (exit non-zero, parse failure, timeout)
│
└─ Install-ClaudeCode              ← modified (decision flow below)

setup.sh
├─ npm_latest_version              ← new helper (equivalent to PS one)
└─ install_claude_code             ← modified
```

### Install-ClaudeCode decision flow

```
$current = Get-ToolVersion 'claude'

CASE A: $current is null  (Claude Code not installed)
  └─ "Claude Code not found. Installing latest (minimum required: $min)..."
  └─ npm install -g @anthropic-ai/claude-code@latest
  └─ existing post-install validation

CASE B: $current set AND -Upgrade switch passed  (explicit setup.bat --update)
  └─ "Claude Code $current found. --update specified, running npm install..."
  └─ npm install -g @anthropic-ai/claude-code@latest
  └─ skip the registry query — user told us to update; don't pretend to check

CASE C: $current set AND NOT -Upgrade  (plain re-run, the common case)
  ├─ $latest = Get-NpmLatestVersion
  │
  ├─ CASE C1: $latest is null  (registry query failed for any reason)
  │   └─ Write-Warn "Could not check npm for latest version (continuing with upgrade attempt)."
  │   └─ npm install -g ...  ← graceful fallback to today's behavior
  │
  ├─ CASE C2: $current >= $latest  (at latest or somehow ahead)
  │   └─ "Claude Code $current OK (>= $min, latest is $latest). No upgrade needed."
  │   └─ return  ← skip
  │
  └─ CASE C3: $current < $latest  (real upgrade available)
      └─ "Claude Code $current found. Upgrading to $latest..."
      └─ npm install -g @anthropic-ai/claude-code@latest
      └─ existing post-install validation
```

### Get-NpmLatestVersion contract

```powershell
function Get-NpmLatestVersion {
    # Returns [version] of the latest stable @anthropic-ai/claude-code on
    # the npm registry, or $null on any failure. Caller must treat $null as
    # "couldn't determine; fall back to upgrade attempt."
    #
    # No exceptions thrown. No global state mutated. No stdout pollution.
}
```

Bash counterpart:

```bash
# npm_latest_version
#   Echoes the latest version string on success (exit 0).
#   On failure: empty stdout, exit non-zero.
#   Caller pattern:  latest=$(npm_latest_version) || latest=""
```

## Data flow

```
                  ┌─────────────────────────────────────────────┐
                  │ npm registry                                │
                  └─────────────────────┬───────────────────────┘
                                        │ HTTPS  (npm view)
                                        ▼
                  ┌─────────────────────────────────────────────┐
                  │ Get-NpmLatestVersion  /  npm_latest_version │
                  │   timeout: trust npm's default (~5s)        │
                  │   on any failure → return null              │
                  └─────────────────────┬───────────────────────┘
                                        │
                                        ▼
                  ┌─────────────────────────────────────────────┐
                  │ Install-ClaudeCode                          │
                  │   decision flow (Cases A/B/C above)         │
                  └─────────────────────┬───────────────────────┘
                                        │
                ┌───────────────────────┼───────────────────────┐
                ▼                       ▼                       ▼
        SKIP (Case C2)         npm install (A/B/C1/C3)    log + return
        Write-Info ...                  │
                                        ▼
                              existing post-install +
                              version validation
```

## Error handling

| Condition | Behavior |
|---|---|
| `npm view` exit 0, parseable version | Compare to local; skip or upgrade per decision flow |
| `npm view` exit 0, unparseable output | Helper returns null → fall through to upgrade attempt |
| `npm view` exit non-zero (network, package not found, npm missing on PATH) | Helper returns null → fall through to upgrade attempt |
| `npm view` hangs / times out | Trust npm's default timeout. If npm doesn't return reasonably, the existing `npm install` would have hit the same network issue — fallback gives identical UX to today. |
| `npm` itself not on PATH | Upstream `Install-NodeJS` runs before `Install-ClaudeCode`. If npm is missing here, the script has bigger problems and would have failed `npm install` regardless. Treated as a registry-query failure (returns null), upgrade attempt also fails, existing error path takes over. |
| `npm view` writes to stderr but exits 0 (e.g. deprecation warnings) | Stderr ignored; parse stdout for version. Existing `Get-VersionFromString` handles ambient noise. |

**Graceful degradation invariant:** every failure mode from the helper falls
back to the existing upgrade path. The user is never blocked by registry
issues that weren't blockers before.

## Testing

### Unit (PowerShell — Pester or hand-rolled mock)

| Test | Setup | Expected |
|---|---|---|
| At-latest skip | Mock `npm view` returning `2.1.153`, local is `2.1.153` | Install-ClaudeCode emits OK line, does NOT call `npm install` |
| Upgrade behind | Mock `npm view` returning `2.1.180`, local is `2.1.100` | Install-ClaudeCode logs "Upgrading 2.1.100 → 2.1.180", calls `npm install` |
| Registry failure fallback | Mock `npm view` exit non-zero | Install-ClaudeCode warns, calls `npm install` (current behavior preserved) |
| Unparseable npm view output | Mock `npm view` exit 0 with garbage | Get-NpmLatestVersion returns null, Install-ClaudeCode fallbacks |
| --update bypass | Local is `2.1.153`, latest is `2.1.153`, `-Upgrade` switch on | Install-ClaudeCode runs `npm install` without querying registry |

### Unit (Bash — extend `scripts/test-setup.sh`)

Mirror the five PS scenarios. Use a function-override pattern for `npm`:

```bash
# Override npm in the test shell to return controlled output
npm() {
  if [[ "$1" == "view" ]]; then echo "2.1.180"; return 0; fi
  command npm "$@"
}
```

### Manual smoke

- Local install with Claude Code already at npm's `latest` → assert SKIP
  message, no `npm install` output.
- Local install with `npm uninstall -g @anthropic-ai/claude-code` first
  (revert to "not installed") → assert fresh install path (Case A).
- Local install with `--update` flag → assert always-install (Case B), no
  registry query.
- Disconnect network → assert fallback message + attempted `npm install`
  (Case C1).

## Migration / rollout

Single PR, single commit. No data migration. No backwards-compat concerns —
the behavior change is a strict UX improvement (faster + quieter on re-runs,
identical when registry unreachable).

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `npm view` returns 5+ second response on slow networks every run | Medium | Low — adds ~5s on first slow run, then setup is much faster than today's 15s | Acceptable trade-off. Caching is non-goal. |
| Pre-release / beta tagged as `latest` on npm | Low | Low — Anthropic's package follows semver; no betas at @latest tag historically | Trust npm's `latest` dist-tag. If this becomes a problem, scope expansion adds version-filter. |
| Corporate firewall blocks npm registry but not other operations | Medium | Low — fallback to npm install hits the same firewall, same failure mode as today | No new failure mode introduced. |
| Get-NpmLatestVersion parsing breaks on future npm output format change | Low | Low — falls back to upgrade attempt, identical to today | Keep parser tolerant; use existing Get-VersionFromString helper. |

## Acceptance criteria

This spec is implemented when:

1. `setup.ps1` has a `Get-NpmLatestVersion` helper that runs `npm view
   @anthropic-ai/claude-code version`, parses output, and returns
   `[version]` or `$null` on any failure.
2. `setup.sh` has the equivalent `npm_latest_version` shell function.
3. `Install-ClaudeCode` (PS) and `install_claude_code` (Bash) implement the
   decision flow above (Cases A, B, C1, C2, C3).
4. `setup.bat --update` bypasses the registry query and always runs
   `npm install`.
5. On a machine where Claude Code is at the published latest, plain
   `setup.bat` re-run shows a single OK line for Claude Code and does NOT
   invoke `npm install -g`.
6. On a machine without network access, plain `setup.bat` re-run logs the
   "could not check" warning and falls through to the existing upgrade
   attempt — UX matches today's offline behavior.
7. Unit tests cover the five scenarios listed above; setup-script syntax
   checks pass.

## Open questions

None blocking. Three deferred to implementation discretion:

- **Exact warning wording** when registry query fails. Spec proposes "Could
  not check npm for latest version (continuing with upgrade attempt)." —
  refine during implementation if a clearer phrasing emerges.
- **Whether to log the latest version even when skipping.** Spec says yes
  ("...latest is $latest..."). If that's noise, drop to just "OK".
- **Timeout for `npm view`.** Spec defers to npm's default (~5s). If that
  proves too long for some users, can be capped via `Start-Process` with
  explicit timeout — but YAGNI until a real complaint.
