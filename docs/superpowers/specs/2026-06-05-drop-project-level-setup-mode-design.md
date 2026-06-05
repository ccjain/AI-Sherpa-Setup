# AI Sherpa — Drop Project-Level Setup Mode

**Date:** 2026-06-05
**Status:** Approved
**Supersedes scope of:** original Phase 1 "install/init split" proposal (no `init` subcommand will ship)

---

## Goal

Make `setup.bat` (Windows) and `setup.sh` (Linux/Mac) behave identically for every user, regardless of the shell's working directory. Eliminate the silent dual-mode (user-level vs project-level) selection that depends on CWD, which produced the `C:\Windows\System32` footgun where a teammate's Admin shell defaulted to System32 and the script wrote a project's worth of files into the Windows system directory. The underlying mode dispatch exists in `setup.sh` as well (lines 1557-1559, 1644-1652) and must be removed in the same change so the team's Windows and Unix users get the same contract.

## Problem

Today, both `setup.ps1` (Windows) and `setup.sh` (Linux/Mac) detect two modes from CWD using equivalent logic.

`setup.ps1:2102-2104`:

```powershell
$currentPath = (Get-Location).Path
$isUserLevelRun = ((Test-Path "$currentPath\core\CLAUDE.md") -and ($currentPath -eq $ScriptDir))
```

`setup.sh:1557-1559`:

```bash
local is_user_level=false
if [[ -f "$SCRIPT_DIR/core/CLAUDE.md" && "$PWD" == "$SCRIPT_DIR" ]]; then
  is_user_level=true
fi
```

In both scripts:

- **User-level run** (CWD = setup repo): writes `~/.claude/CLAUDE.md`, installs plugins/MCP/hooks globally.
- **Project-level run** (any other CWD): writes `<CWD>/CLAUDE.md` and `<CWD>/.claude/settings.json` in addition to the global install, after prompting "New project or existing project?" (setup.sh:1648, setup.ps1:2254).

This pattern breaks two industry norms followed by every other Windows install tool (Git, Node.js, VS Code, rustup, uv, GitHub CLI, AWS CLI, Claude Code itself): **installers install the tool; project initialization is a separate, explicit action.** The CWD-sniff also has no failsafe — System32, Program Files, drive roots, and the user's home directory are all "valid" project-level targets.

Worse, the project-level files are not project-specific. They are **duplicates of the global config dropped into the project directory** — the same `core/CLAUDE.md` + domain rules merge that user-level mode writes to `~/.claude/CLAUDE.md`. Claude Code already auto-loads the global file for every session, so the project-level copy adds nothing for installed teammates and confuses the boundary between "AI Sherpa global rules" and "this codebase's own rules" (which only the project owner can author).

## Decision

Drop project-level mode entirely. `setup.bat` becomes a pure global installer. No subcommand is added in this change. A project-init feature may be designed later if and when a real use case emerges that AI Sherpa can meaningfully scaffold (e.g., a CLAUDE.md template with placeholders for the user to fill in — explicitly out of scope here).

## User-Facing Contract

```
setup.bat                  → Global install. Identical for every user.
                             Writes to ~/.claude/ and other user-global
                             locations. NEVER touches CWD. No interactive
                             prompts about projects.

setup.bat --update         → Unchanged. Re-runs the global install pipeline
                             with upgrades.

setup.bat --uninstall      → Unchanged.
```

No new flags. No new subcommands.

## What Changes

### `setup.ps1`

**Delete:**

| Lines (current master) | What | Why |
|---|---|---|
| 2102-2104 | `$isUserLevelRun = ...` and the surrounding CWD-sniff comment | No more dual-mode |
| 2232 (`if ($isUserLevelRun) {`) through 2280 (closing `}` of else branch) | The mode dispatch | Only one path remains |
| 2251-2264 | The "New project or existing project?" `Read-Host` prompt and `$projectType` plumbing | No more project-level mode |
| `Write-ProjectSettings` (1037-1047) | Project-CWD `.claude/settings.json` writer | Unused after delete |
| `Copy-ClaudeMd` (1049-1077) | Project-CWD CLAUDE.md writer / appender | Unused after delete |

**Keep and collapse:** the body of the old `if ($isUserLevelRun)` branch becomes the unconditional install flow:

```powershell
Write-GlobalClaudeMd $domain
Enable-WindowsLongPaths
Install-Tools -Domain $domain -Upgrade:$isReinstall
Initialize-Rtk
Write-AiSherpaState -Domain $domain
$missing = Test-Installation $domain
# ... existing summary / verification logic
```

`Print-Summary` always called with `-UserLevel`. Renaming the now-meaningless switch is a follow-up cleanup; not required for this change.

### `setup.sh`

Mirror the same removal:

| Lines (current master) | What | Why |
|---|---|---|
| 1555-1559 | `is_user_level` detection block | No more dual-mode |
| 1644-1652 | "New project or existing project?" `read -rp` prompt and `project_type` plumbing | No more project-level mode |
| 587-592 | Summary block's `if user-level / else project-level` branch | Always print the user-level form |
| Any `is_user_level == true` / `!= true` branches further down the file that dispatch on the variable | Collapse to the user-level body unconditionally | One path remains |
| Bash equivalents of `Write-ProjectSettings` and `Copy-ClaudeMd` (the functions invoked only in the project-level branch) | Delete | Unused after delete |

Implementation plan will enumerate the exact bash functions to remove after a full read of `setup.sh` — the line ranges above are anchor points, not the complete list.

## What Stays the Same

- All plugin installs, marketplace registration, MCP config, hooks, skills, CLI tool installs (rtk, claude-mem, code-review-graph), toolchain detection — unchanged. These were already global in both modes.
- `setup.bat --update` and `setup.bat --uninstall` semantics — unchanged.
- `~/.claude/.ai-sherpa-state.json` location, format, and lifecycle — unchanged.
- `setup.sh` (Linux/Mac) — same removal applied; see the `setup.sh` subsection under "What Changes" above.

## Files Changed

| File | Change |
|---|---|
| `setup.ps1` | Delete `$isUserLevelRun` detection, delete `Write-ProjectSettings`, delete `Copy-ClaudeMd`, delete the project-level dispatch branch and its prompt, collapse the dispatch to a single path |
| `setup.sh` | Delete `is_user_level` detection, delete project-level prompt, delete project-level functions, collapse summary + dispatch to single path |
| `setup.bat` | No change (already forwards `%*` to `setup.ps1`; arg surface unchanged) |
| `docs/user-guide.md` | Rewrite lines 44-47: drop "(project-level run)" vs "(user-level run)" distinction. State only that setup writes to `~/.claude/`. |
| `AGENTS.md` | Rewrite lines 12-16 ("Quick start" steps) and 141-143 ("Security" notes) to drop project-level references. Setup writes secrets-protection deny rules to `~/.claude/settings.json` only; no `<project>/.claude/settings.json` is created by setup any more. |
| `scripts/test-setup.sh` | Audit and remove any tests that assert project-level behavior (file appears in grep hits for "project-level"). |

## Migration / Breaking Changes

- **Breaking for any user who was running `setup.bat` from a project directory expecting project-level files to be written.** After this change, `setup.bat` only ever writes to `~/.claude/`; CWD is ignored.
- No `--legacy` flag. Hard cut. Release notes must call out the change explicitly.
- Anyone who had per-project `CLAUDE.md` or `.claude/settings.json` previously generated by AI Sherpa: those files remain on disk untouched. The user can keep them, hand-edit them, or delete them. Re-running `setup.bat` will not regenerate them and will not remove them.
- The `C:\Windows\System32\...` files generated by the System32 incident must still be cleaned up manually by the affected user — this change does not auto-remove them (out of scope; one-off cleanup).

## Testing

Manual verification on a Windows box (PowerShell 5.1 and 7+), plus a Linux/Mac box for the `setup.sh` equivalents:

1. **Fresh install from setup repo dir:**
   `cd D:\AI-Sherpa-Setup-master; .\setup.bat`
   → expect identical output to today's user-level run; `~/.claude/CLAUDE.md` and `~/.claude/settings.json` written.

2. **Fresh install from arbitrary CWD:**
   `cd D:\some-project; D:\AI-Sherpa-Setup-master\setup.bat`
   → expect *identical* output to test 1. `D:\some-project\CLAUDE.md` and `D:\some-project\.claude\` must NOT exist after the run.

3. **Fresh install from System32 (Admin shell default):**
   `cd C:\Windows\System32; D:\AI-Sherpa-Setup-master\setup.bat`
   → expect identical output to test 1. `C:\Windows\System32\CLAUDE.md` and `C:\Windows\System32\.claude\` must NOT be created.

4. **Re-run / update:**
   `setup.bat --update` → unchanged behaviour from current master.

5. **Uninstall:**
   `setup.bat --uninstall` → unchanged behaviour from current master.

6. **No prompt regression:**
   No interactive `Read-Host` (PowerShell) or `read -rp` (bash) call should fire during a normal `setup.bat` / `setup.sh` run.

7. **Unix equivalents of 1-6:** run the same matrix on Linux/Mac with `./setup.sh`, including launching from `$HOME`, from `/`, and from an arbitrary project dir.

## Out of Scope

- A future `setup.bat init` for scaffolding a project-specific CLAUDE.md template, project allowlist starter, etc. If a real use case for this surfaces, it gets its own design doc; the design will not duplicate global config into the project (the original mistake).
- Cleanup of `C:\Windows\System32\.claude\` files left behind by the original footgun on affected machines — manual cleanup by the user.
- Renaming `Print-Summary -UserLevel` to drop the now-redundant switch — follow-up cleanup, not blocking.
