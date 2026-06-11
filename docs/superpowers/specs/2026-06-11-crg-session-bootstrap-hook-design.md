# AI Sherpa — Fix SessionStart Hook for code-review-graph

**Date:** 2026-06-11
**Status:** Approved

---

## Goal

Make the `SessionStart` hook actually do what its name and documentation
already promise: on every Claude Code session start inside a git repo,
ensure the `code-review-graph` daemon is running, this repo is registered
with it, and an initial graph exists. The user runs `setup.ps1` /
`setup.sh` once; from that point on, the graph stays fresh for every
project they open — no manual `crg-daemon add` / `code-review-graph build`
commands ever required.

`core/CLAUDE.md` and `.github/code-review-graph.instruction.md` already
tell Claude to use the graph MCP tools *before* `Grep`/`Glob`/`Read`,
and they assert "The graph auto-updates on file changes (via hooks)."
Today that sentence is false on every Windows install we've checked: the
hook is a silent no-op (root cause in §Problem) and only `Files: 11`
of a several-hundred-file repo end up indexed.

## Problem

The hook installed by setup today (`settings/settings-template.json`,
inlined into `~/.claude/settings.json` as
`hooks.SessionStart[0].hooks[0].command`) is a three-step `try/catch`
cascade encoded as a single `node -e` blob:

```js
try   { execSync('crg-daemon status') }
catch { try   { spawn('crg-daemon', ['start'], {detached:true}) }
        catch { execSync('code-review-graph build --quiet') } }
```

**Bug 1 — `crg-daemon status` always exits 0.** The intent is "if the
daemon's down, fall through to `start`." But the CLI returns exit 0 even
when it prints `Daemon: not running. No repositories configured.` So
`execSync` never throws, the `catch` branches never fire, and neither
`start` nor `build` ever runs. Verified on this machine
(2026-06-11 GMT+5:30): the SessionStart banner reports
`Nodes: 109 / Edges: 1407 / Files: 11`, frozen at the timestamp of the
one-time `postInstall: "code-review-graph install"` that ran during
setup. Nothing else has touched the DB since.

**Bug 2 — even if the cascade fired, this repo is never registered.**
`crg-daemon start` only starts the watcher process. It watches whatever
is in `~/.code-review-graph/watch.toml`. That config is empty until
something runs `crg-daemon add <repo-path>`. The current hook never
calls `add`. So on a clean machine the daemon would start, watch zero
repos, and the current project's graph would stay frozen.

**Bug 3 — no bootstrap if `.code-review-graph/graph.db` is missing.**
`crg-daemon` only performs *incremental* updates. The first-ever graph
for a repo must be built with `code-review-graph build`. The current
cascade only reaches `build` if `crg-daemon start` itself throws — a
path that never triggers in practice.

The net effect is that AI Sherpa promises auto-updating graphs and
silently doesn't deliver them. Users who follow the CLAUDE.md guidance
("ALWAYS use the code-review-graph MCP tools BEFORE using Grep/Glob/Read")
get nearly-empty results because the graph covers a sliver of the repo.

## Decision

Replace the inline `node -e` cascade with a proper Node script shipped
in `hooks/crg-bootstrap.js` that runs the correct sequence:

1. Gate on the current directory being a git repo.
2. Gate on `code-review-graph` being installed (setup may have failed).
3. `crg-daemon start` — idempotent; exits 0 whether it started fresh or
   was already running. No more `status`-based detection.
4. `crg-daemon add <cwd>` — idempotent; no-op if already registered.
5. If `<cwd>/.code-review-graph/graph.db` does not exist, spawn
   `code-review-graph build --quiet` detached so a slow first build
   doesn't block session start.

`setup.ps1` and `setup.sh` already copy `hooks/*.js` into
`~/.claude/hooks/` via `Install-Hooks` / `install_hooks`, and the
template's `__CLAUDE_HOOKS_DIR__` token is already substituted to the
real path. No installer code changes are required — the new file is
picked up automatically by both flavors.

## User-Facing Contract

```
setup.ps1 / setup.sh        → Unchanged invocation. Identical surface.
                              Now also writes hooks/crg-bootstrap.js
                              into ~/.claude/hooks/ and references it
                              from settings.json's SessionStart array.

(every Claude Code session)  → Inside any git repo with code-review-graph
                              installed:
                                - daemon is started if down
                                - cwd is added to daemon watch list
                                - graph is bootstrapped if missing
                              All silent. CRG_HOOK_DEBUG=1 enables
                              stderr trace for troubleshooting.

(outside a git repo)         → Hook exits 0 silently. No noise.

(code-review-graph missing)  → Hook exits 0 silently. Setup logged the
                              install failure separately; runtime hook
                              must not crash sessions.
```

No new flags, no new commands, no new user-visible CLI surface.

## How Existing Users Pick Up The Fix

Existing AI Sherpa installs have the broken inline cascade in their
`~/.claude/settings.json`. They get the fix by re-running setup:

1. `git pull` AI Sherpa.
2. `setup.ps1` (Windows) or `setup.sh` (Linux/macOS).
3. `Merge-JsonObjects` in setup.ps1 deep-merges the new template into the
   existing `settings.json`. Per `setup.ps1:1075-1080` the merge
   **replaces arrays wholesale** — exactly so "stale template-managed
   hook entries can't accumulate across upgrades." The broken
   `SessionStart` array is replaced with the fixed one.
4. `setup.sh write_rendered_settings` overwrites `settings.json`
   wholesale (no merge step yet; this is a pre-existing asymmetry,
   tracked separately). The new hook lands the same way.
5. `Install-Hooks` / `install_hooks` copies the new `crg-bootstrap.js`
   into `~/.claude/hooks/`.
6. Next Claude session in any git repo triggers the corrected behavior.

The CHANGELOG entry must explicitly tell users to re-run setup. Without
that step, no machine self-heals — the broken hook keeps running until
the template is re-rendered.

## Files Changed

| File | Change | Notes |
| ---- | ------ | ----- |
| `hooks/crg-bootstrap.js` | NEW | ~50 lines. See §Behavior for full source. |
| `settings/settings-template.json` | MODIFIED | Replace the inline `node -e "..."` blob in `hooks.SessionStart[0].hooks[0].command` with `node "__CLAUDE_HOOKS_DIR__/crg-bootstrap.js"`. One-line change. |
| `CHANGELOG.md` | MODIFIED | Note the fix and the required `re-run setup` step. |
| `setup.ps1` | UNCHANGED | `Install-Hooks` (line 1050) already globs `hooks/*.js`. |
| `setup.sh` | UNCHANGED | `install_hooks` (line 155) already globs `hooks/*.js`. |
| `core/CLAUDE.md` | UNCHANGED | The "graph auto-updates on file changes (via hooks)" claim at line 50 becomes true after this fix. |
| `.github/code-review-graph.instruction.md` | UNCHANGED | Same. |

## Behavior (`hooks/crg-bootstrap.js`)

```js
#!/usr/bin/env node
// SessionStart hook: keep the code-review-graph fresh for the current project.
// Runs on startup | resume | clear | compact. Silent unless CRG_HOOK_DEBUG=1.

const cp = require('child_process');
const fs = require('fs');
const path = require('path');

const cwd = process.cwd();
const debug = !!process.env.CRG_HOOK_DEBUG;
const log = (msg) => debug && process.stderr.write(`[crg-bootstrap] ${msg}\n`);

// Gate 1: only run inside git repos. Skip $HOME, scratch dirs, etc.
if (!fs.existsSync(path.join(cwd, '.git'))) {
  log('not a git repo, skipping');
  process.exit(0);
}

// Gate 2: only run if code-review-graph is actually installed. Setup may have
// failed to install it (uv/pipx/pip cascade exhausted) — don't crash sessions.
const has = (bin) => {
  const probe = process.platform === 'win32' ? `where ${bin}` : `command -v ${bin}`;
  try { cp.execSync(probe, {stdio: 'ignore'}); return true; }
  catch { return false; }
};
if (!has('code-review-graph')) {
  log('code-review-graph not installed, skipping');
  process.exit(0);
}

const run = (cmd, args) => {
  try {
    cp.execFileSync(cmd, args, {
      stdio: debug ? 'inherit' : 'ignore',
      timeout: 15000,
    });
    return true;
  } catch (e) {
    log(`${cmd} ${args.join(' ')} failed: ${e.message}`);
    return false;
  }
};

// Step 1: ensure daemon is running. `crg-daemon start` is idempotent —
// exits 0 whether it started fresh or was already running. Safer than
// parsing `status` stdout (which exits 0 even when the daemon is down —
// the original Bug 1).
if (has('crg-daemon')) {
  run('crg-daemon', ['start']);

  // Step 2: register this repo with the daemon. Idempotent — `add` on
  // an already-registered repo is a no-op. Without this, the daemon
  // watches nothing and the graph never updates (original Bug 2).
  run('crg-daemon', ['add', cwd]);
}

// Step 3: bootstrap the initial graph if it doesn't exist yet. The
// daemon only does INCREMENTAL updates — it won't build a graph from
// scratch (original Bug 3). Spawn detached so a slow first build
// doesn't block session start.
const dbPath = path.join(cwd, '.code-review-graph', 'graph.db');
if (!fs.existsSync(dbPath)) {
  log('no graph.db — bootstrapping in background');
  const child = cp.spawn('code-review-graph', ['build', '--quiet'], {
    cwd,
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
}
```

### Behavioral Choices

| Choice | Reason |
| ------ | ------ |
| Use `crg-daemon start` instead of `status` check | Avoids Bug 1. `start` is the idempotent primitive; verified against `crg-daemon --help` output. |
| Run `crg-daemon add <cwd>` unconditionally | `add` is documented as a registry mutation; on an already-registered path it's a no-op. The CLI exposes no read-only "is X registered?" query, so the "ask forgiveness, not permission" path is the only correct one. |
| Bootstrap build is `spawn + detached + unref` | First-time builds on large repos can take 10–60 s. Blocking session start that long is unacceptable. Trade-off: the first session may finish before the build does. Every later session sees the full graph. |
| Silent by default; `CRG_HOOK_DEBUG=1` to verbose | The hook fires on every session start / resume / clear / compact. Any stderr noise pollutes the chat. Debug env flag for troubleshooting. |
| 15-second per-command timeout | A hung `crg-daemon start` (e.g. corrupt pidfile) must not block Claude Code from launching. |
| Two pre-flight gates (`.git` exists, binary on PATH) | `$HOME` and scratch dirs aren't repos. Setup may have failed to install the binary. Both must silently no-op, not crash. |

### Explicit Non-Behaviors

- **No rebuild on every session.** The daemon's filesystem watcher
  handles incremental updates after the first build.
- **No `crg-daemon remove` cleanup.** The daemon's config grows
  monotonically. Trivial to add later if it becomes a problem.
- **No per-platform path translation.** Node's `process.cwd()` returns
  the right native path on every platform; both `crg-daemon` and
  `code-review-graph` accept native paths.
- **No git `post-commit` hook.** The daemon's filesystem watcher already
  sees commits as file writes. A separate `post-commit` hook would
  duplicate work and reopens the Windows Unicode bug that caused the
  previous post-commit attempt to be removed (memory observation 249).
- **No `crgignore` / opt-out file.** Auto-registering every git repo
  the user opens is intended behavior. If the daemon's repo list grows
  unwieldy, that's a future cleanup, not a current limitation.
- **No Windows-service / systemd-unit migration for the daemon.** The
  daemon still dies on reboot; SessionStart re-registers anything
  missing. Service-ization is its own body of work.

## Testing

### Manual reproduction of the current bug

1. Open Claude Code in any AI Sherpa repo on a Windows machine that ran
   `setup.ps1` before this fix.
2. `crg-daemon status` — observe `Daemon: not running. No repositories
   configured.` and exit code 0.
3. `code-review-graph status` — observe a frozen, tiny graph
   (e.g. `Files: 11`).
4. Start a new Claude session, then re-run step 2. State is unchanged:
   the hook ran and did nothing.

### Manual verification of the fix

On a machine after the fix lands and setup has been re-run:

1. `crg-daemon stop ; rm -rf .code-review-graph/` (Linux/macOS) or
   `Stop-Process -Name crg-daemon -ErrorAction SilentlyContinue ;
   Remove-Item .\.code-review-graph -Recurse -Force` (Windows) — simulate
   a fresh machine.
2. Start a new Claude Code session in the repo.
3. Within ~1 s: `crg-daemon status` shows `Daemon: running` and the
   repo path in the watched list.
4. Within ~30–60 s (depends on repo size): `.code-review-graph/graph.db`
   exists and `code-review-graph status` reports hundreds of files
   across multiple languages, not `Files: 11`.
5. Edit a source file and save. Within the daemon's poll interval
   (`Poll: 2s` per `crg-daemon status`), `code-review-graph status`
   reflects the change in `Last updated`.

### Negative paths

- Run a Claude session in `$HOME` (no `.git`). Hook exits 0 silently;
  no daemon activity for that path.
- Temporarily rename the `code-review-graph` binary to simulate a failed
  install. Hook exits 0 silently; no crash, no error banner.
- Set `CRG_HOOK_DEBUG=1` and start a session. Stderr trace shows each
  gate decision and command outcome.

### Out-of-scope tests

- No automated CI test for this hook. It depends on a live
  `code-review-graph` install and a real Claude Code session context;
  the cost of a meaningful integration test outweighs the benefit at
  this stage. Manual verification on Windows + Linux is sufficient.

## Out of Scope

Tracked separately, do not address in this change:

- **`setup.sh` overwrite-vs-merge asymmetry.** `setup.sh write_rendered_settings`
  overwrites `settings.json` wholesale instead of deep-merging, losing
  user customizations. Pre-existing; should be a follow-up that ports
  `Merge-JsonObjects` semantics to bash via `jq`.
- **Daemon process-supervision.** The daemon dies on reboot, on user
  logout, and on OOM. SessionStart re-registers anything missing, but
  between reboot and the first Claude session, no graph updates happen.
  Resolution paths (Windows service, systemd user unit, scheduled task)
  are their own design.
- **Multi-repo registry cleanup.** `crg-daemon` has no concept of
  "forget repos I haven't visited in N days." If the watch list grows
  to hundreds of repos, performance may degrade. Not a current problem.
- **`.crgignore` files** for excluding specific repos from auto-registration.
  Not needed until someone has a concrete reason to suppress the hook.
