# Drop Project-Level Setup Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the CWD-sniffing dual-mode (user-level vs project-level) in `setup.ps1` and `setup.sh`, so `setup.bat` / `setup.sh` install globally regardless of working directory. Closes the `C:\Windows\System32` footgun. No replacement `init` subcommand is shipped.

**Architecture:** Pure deletion + dispatch collapse. Both scripts currently branch on a CWD-derived `$isUserLevelRun` / `is_user_level` boolean; both branches' install steps are identical *except* that the project-level branch additionally writes a duplicate `CLAUDE.md` and `settings.json` into CWD. We delete the project-level branch entirely (including the "New or existing project?" prompt), delete the helpers that only the project-level branch called (`Write-ProjectSettings`, `Copy-ClaudeMd`, `write_project_settings`, `copy_claude_md`), and collapse the dispatch + summary to one path. Tests in `scripts/test-setup.sh` that exercised the deleted helpers are removed first so the test suite keeps passing throughout.

**Tech Stack:** Bash (`setup.sh`, `scripts/test-setup.sh`), PowerShell 5.1 (`setup.ps1`), Markdown docs.

**Spec:** [`docs/superpowers/specs/2026-06-05-drop-project-level-setup-mode-design.md`](../specs/2026-06-05-drop-project-level-setup-mode-design.md)

---

## Task 1: Remove project-level tests from `scripts/test-setup.sh`

**Why this is first:** the test file sources `setup.sh` and invokes `write_project_settings` / `copy_claude_md` directly. If we delete the helpers first, the test run fails before we can verify anything. Strip the now-irrelevant test blocks first; the rest of the suite (which still passes today) becomes our regression net for tasks 2–3.

**Files:**
- Modify: `scripts/test-setup.sh:51-94`

- [ ] **Step 1: Capture the current test pass count as a baseline**

Run:
```bash
bash scripts/test-setup.sh
```
Expected: the script prints `PASS:` lines for `write_project_settings` and three `copy_claude_md` cases, plus all other tests. Note the final `Total: PASS=<N> FAIL=0` line (or equivalent — read the bottom of the file to confirm output format) and record `<N>` so we can verify the new pass count after deletions = `<N> - 4`.

- [ ] **Step 2: Delete the four test blocks**

Open `scripts/test-setup.sh` and remove lines 51-94 inclusive (the four `--- Test: write_project_settings ---` and `--- Test: copy_claude_md ... ---` blocks plus their trailing `popd > /dev/null; rm -rf "$TMP"` cleanups).

The block to delete starts with:
```bash
# --- Test write_project_settings ---
echo "=== Test: write_project_settings ==="
```
…and ends with:
```bash
copy_claude_md "web" "existing"
assert_file_exists "CLAUDE.md created even with existing type" "$TMP/CLAUDE.md"
assert_file_contains "CLAUDE.md has web rules" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"
```

After the deletion, the next surviving line should be `# --- Test install_core_skills reads global plugins from plugins.json ---` (currently line 96).

- [ ] **Step 3: Re-run the test suite**

Run:
```bash
bash scripts/test-setup.sh
```
Expected: pass count = baseline `<N> - 4`. FAIL count still 0. No "command not found" or "undefined function" errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-setup.sh
git commit -m "$(cat <<'EOF'
test(setup): drop write_project_settings/copy_claude_md tests

Prep for removing the dual-mode (user-level vs project-level) dispatch
from setup.sh / setup.ps1. The helpers these tests exercised will be
deleted in follow-up commits; removing the tests first keeps the suite
green throughout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Collapse dual-mode dispatch in `setup.sh`

**Files:**
- Modify: `setup.sh:580-599` (summary print)
- Modify: `setup.sh:1557-1562` (mode detection)
- Modify: `setup.sh:1644-1658` (project-type prompt)
- Modify: `setup.sh:1660-1674` (install dispatch)
- Modify: `setup.sh:1709-1721` (post-verify summary calls)

- [ ] **Step 1: Replace the `print_summary` body to drop the user_level branch**

In `setup.sh`, find lines 580-599 (the full `print_summary()` function — read the file first to confirm the closing brace position; line numbers in this plan may have drifted by a few lines from edits). Replace the whole function with:

```bash
print_summary() {
  local domain="$1"
  echo -e "\n${CYAN}======================================================${NC}"
  echo -e "${CYAN}  AI Sherpa Setup Complete${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo "  Domain:   $domain"
  echo "  Settings: $EFFECTIVE_HOME/.claude/settings.json  (secrets protection active)"
  echo "  Rules:    $EFFECTIVE_HOME/.claude/CLAUDE.md  (active for all projects)"
  echo ""
  echo "  Next steps:"
  echo "  1. Start Claude Code:   claude"
  echo "  2. Code-review graph runs in auto-mode via SessionStart hook (no manual step)."
  echo "  3. Start coding — AI Sherpa rules are active automatically"
  echo ""
  echo "  Update later: bash \"$SCRIPT_DIR/setup.sh\" --update"
```

(Preserve any lines that came after `echo "  Update later: ..."` and before the closing `}` — read the surviving tail of the function in the live file and keep it intact. Only the `if/else` branch on `user_level` is being removed.)

The `local domain="$1" user_level="${2:-false}"` parameter line drops its `user_level` parameter, and the `if [[ "$user_level" == true ]]; then ... else ... fi` block is replaced by the single `Rules:` line that used to live in the `true` branch.

- [ ] **Step 2: Remove the mode detection block**

In `setup.sh`, find lines 1557-1562:

```bash
  # Detect user-level (run from inside the AI Sherpa repo) vs project-level run
  local is_user_level=false
  if [[ -f "$SCRIPT_DIR/core/CLAUDE.md" && "$PWD" == "$SCRIPT_DIR" ]]; then
    is_user_level=true
    log_info "Running from inside AI Sherpa repo — installing at USER level (~/.claude/)."
  fi
```

Delete the entire block. Replace with nothing (no log line — every run is user-level now, so saying so is noise).

- [ ] **Step 3: Remove the "New or existing project?" prompt**

In `setup.sh`, find lines 1644-1658:

```bash
  # --- New or existing project (project-level only) ---
  local project_type=""
  if [[ "$is_user_level" != true ]]; then
    echo ""
    echo "New project or existing project?"
    echo "  [1] New project"
    echo "  [2] Existing project (CLAUDE.md will be appended, not replaced)"
    echo ""
    read -rp "Enter number [1-2]: " project_choice
    case "$project_choice" in
      1) project_type="new" ;;
      2) project_type="existing" ;;
      *) log_error "Invalid choice: $project_choice. Run the script again."; exit 1 ;;
    esac
  fi
```

Delete the entire block.

- [ ] **Step 4: Collapse the install dispatch**

In `setup.sh`, find lines 1660-1674:

```bash
  # --- Install ---
  register_marketplaces "$domain"
  install_core_skills
  install_domain_skills "$domain"
  install_skills "$domain"
  write_settings
  if [[ "$is_user_level" == true ]]; then
    write_global_claude_md "$domain"
  else
    write_project_settings
    copy_claude_md "$domain" "$project_type"
  fi
  install_tools "$domain"
  write_ai_sherpa_state "$domain"
```

Replace with:

```bash
  # --- Install ---
  register_marketplaces "$domain"
  install_core_skills
  install_domain_skills "$domain"
  install_skills "$domain"
  write_settings
  write_global_claude_md "$domain"
  install_tools "$domain"
  write_ai_sherpa_state "$domain"
```

- [ ] **Step 5: Update the two `print_summary` call sites**

In `setup.sh`, find both `print_summary "$domain" "$is_user_level"` call sites (currently lines 1715 and 1721). Replace each with:

```bash
  print_summary "$domain"
```

(Drop the second positional arg now that `print_summary` only takes `$domain`.)

- [ ] **Step 6: Bash syntax check**

Run:
```bash
bash -n setup.sh
```
Expected: no output, exit 0. Any syntax error means a deletion broke a control-flow structure — re-read the affected region and fix.

- [ ] **Step 7: Run the test suite**

Run:
```bash
bash scripts/test-setup.sh
```
Expected: same pass count as end of Task 1. FAIL=0. (The deleted dispatch is not directly exercised by the unit test file, so the count is unchanged.)

- [ ] **Step 8: Confirm `is_user_level` and `project_type` are gone**

Run:
```bash
grep -nE 'is_user_level|project_type|"New project or existing project"|New or existing project' setup.sh
```
Expected: no output (zero matches). If anything remains, it's a missed reference — delete it.

- [ ] **Step 9: Commit**

```bash
git add setup.sh
git commit -m "$(cat <<'EOF'
fix(setup.sh): drop CWD-sniffing dual-mode dispatch

setup.sh always installs at user level now. The "user-level" branch's
body becomes unconditional; the project-level branch (which only added
duplicate CLAUDE.md + settings.json into CWD) is gone, along with the
"New or existing project?" prompt and the is_user_level / project_type
variables. print_summary's two-branch output collapses to one form.

Spec: docs/superpowers/specs/2026-06-05-drop-project-level-setup-mode-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Delete orphaned `setup.sh` helpers and lock in their absence

**Files:**
- Modify: `setup.sh:186-228` (delete `write_project_settings` + `copy_claude_md`)
- Modify: `scripts/test-setup.sh` (append anti-resurrection assertions)

- [ ] **Step 1: Verify the helpers are unreferenced**

Run:
```bash
grep -nE 'write_project_settings|copy_claude_md' setup.sh
```
Expected: only matches inside the two function *definitions* themselves (lines 186 and 198 with their bodies). No call sites elsewhere. If there are stray call sites, Task 2 missed something — go back and fix before continuing.

- [ ] **Step 2: Delete `write_project_settings`**

In `setup.sh`, delete lines 186-196 (the entire `write_project_settings() { ... }` function including its trailing blank line):

```bash
write_project_settings() {
  local project_settings_dir="$PWD/.claude"
  local project_settings_file="$project_settings_dir/settings.json"
  mkdir -p "$project_settings_dir"
  if [[ -f "$project_settings_file" ]]; then
    cp "$project_settings_file" "${project_settings_file}.bak"
    log_warn "Backed up existing project settings.json"
  fi
  write_rendered_settings "$project_settings_file"
  log_info "Project-level secrets protection + hooks written to $project_settings_file"
}
```

- [ ] **Step 3: Delete `copy_claude_md`**

In `setup.sh`, delete the entire `copy_claude_md() { ... }` function (was lines 198-228, now slightly earlier after Step 2):

```bash
copy_claude_md() {
  local domain="$1" project_type="$2"
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  if [[ ! -f "$domain_md" ]]; then
    log_error "Domain CLAUDE.md not found at: $domain_md"
    exit 1
  fi
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending AI Sherpa rules to existing CLAUDE.md (original preserved)"
    {
      printf '\n---\n'
      echo "<!-- AI Sherpa core + $domain rules — do not edit below this line -->"
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } >> "$target"
  else
    {
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } > "$target"
  fi
  log_info "Merged core + $domain CLAUDE.md installed at $target"
}
```

- [ ] **Step 4: Add anti-resurrection assertions to the test suite**

In `scripts/test-setup.sh`, find the `# --- Test write_settings ---` block (still at lines ~34-49 — read to confirm). Immediately after the line `HOME="$HOME_BAK"; rm -rf "$TMP"` that closes that block, insert:

```bash

# --- Test: project-level helpers are gone (regression guard) ---
echo "=== Test: project-level helpers are not defined ==="
declare -F write_project_settings > /dev/null \
  && fail "write_project_settings should not be defined" "no function" "function exists" \
  || ok "write_project_settings is not defined"
declare -F copy_claude_md > /dev/null \
  && fail "copy_claude_md should not be defined" "no function" "function exists" \
  || ok "copy_claude_md is not defined"
```

This guards against either function being re-introduced.

- [ ] **Step 5: Bash syntax check**

Run:
```bash
bash -n setup.sh && bash -n scripts/test-setup.sh
```
Expected: no output, exit 0 for both.

- [ ] **Step 6: Run the test suite**

Run:
```bash
bash scripts/test-setup.sh
```
Expected: pass count = (end of Task 2 count) + 2 (the two new assertions). FAIL=0.

- [ ] **Step 7: Confirm no remaining references**

Run:
```bash
grep -nE 'write_project_settings|copy_claude_md' setup.sh scripts/test-setup.sh
```
Expected: only the two new assertions inside `scripts/test-setup.sh` (which use the names as strings inside `declare -F` / `ok` / `fail`). Zero matches in `setup.sh`.

- [ ] **Step 8: Commit**

```bash
git add setup.sh scripts/test-setup.sh
git commit -m "$(cat <<'EOF'
fix(setup.sh): delete orphaned write_project_settings + copy_claude_md

These were only called from the project-level dispatch branch removed
in the prior commit. Adds regression tests asserting both functions
are not redefined.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Collapse dual-mode dispatch in `setup.ps1`

**Files:**
- Modify: `setup.ps1:2102-2104` (mode detection)
- Modify: `setup.ps1:2232-2280` (install dispatch including the prompt)

- [ ] **Step 1: Remove the mode detection lines**

In `setup.ps1`, find lines 2102-2104:

```powershell
# Detect whether this is a user-level (double-click) or project-level run
$currentPath = (Get-Location).Path
$isUserLevelRun = ((Test-Path "$currentPath\core\CLAUDE.md") -and ($currentPath -eq $ScriptDir))
```

Delete all three lines.

- [ ] **Step 2: Collapse the dispatch block**

In `setup.ps1`, find lines 2232-2280 (the `if ($isUserLevelRun) { ... } else { ... }` block). Read the current file first to anchor exact line numbers, then replace the entire `if/else` with the contents of the previous `if ($isUserLevelRun)` branch — i.e., the user-level install path, unconditional:

```powershell
# Global install: write CLAUDE.md to ~/.claude/ — active for all projects
Write-GlobalClaudeMd $domain
Enable-WindowsLongPaths
Install-Tools -Domain $domain -Upgrade:$isReinstall
Initialize-Rtk
Write-AiSherpaState -Domain $domain
$missing = Test-Installation $domain
if ($missing.Count -gt 0) {
    Show-VerificationReport $missing
    Show-SkippedStepsReport
    Show-UserActionsReport
    Print-Summary $domain -UserLevel
    exit 1
}
Write-Info "All expected plugins verified in installed_plugins.json."
Show-SkippedStepsReport
Show-UserActionsReport
Print-Summary $domain -UserLevel
```

(Drop the `if ($isUserLevelRun) {` opening, drop the `} else { ... }` block entirely, drop the `Write-Host "New project or existing project?"` prompt and `$projectType` plumbing, drop the closing `}`.)

- [ ] **Step 3: PowerShell syntax parse**

Run (from the repo root, on a Windows box or any machine with PowerShell):
```powershell
powershell -NoProfile -Command "$errs = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\setup.ps1').Path, [ref]$null, [ref]$errs); if ($errs) { $errs | ForEach-Object { Write-Host $_.Message }; exit 1 } else { Write-Host 'parse OK' }"
```
Expected: `parse OK`. Any parse error means a deletion broke a brace pairing — re-read the dispatch region and fix.

- [ ] **Step 4: Confirm `$isUserLevelRun`, `$projectType`, and the prompt are gone**

Run:
```bash
grep -nE '\$isUserLevelRun|\$projectType|New project or existing project' setup.ps1
```
Expected: no output (zero matches).

- [ ] **Step 5: Commit**

```bash
git add setup.ps1
git commit -m "$(cat <<'EOF'
fix(setup.ps1): drop CWD-sniffing dual-mode dispatch

setup.ps1 always installs at user level now. Removes the
$isUserLevelRun detection (CWD-based) and the project-level branch
that wrote CLAUDE.md + .claude/settings.json into the current
directory. Removes the "New project or existing project?" prompt and
$projectType plumbing. Fixes the C:\Windows\System32 footgun where an
Admin shell's default CWD was treated as a project directory.

Spec: docs/superpowers/specs/2026-06-05-drop-project-level-setup-mode-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Delete orphaned `setup.ps1` helpers

**Files:**
- Modify: `setup.ps1:1037-1077` (delete `Write-ProjectSettings` + `Copy-ClaudeMd`)

- [ ] **Step 1: Verify the helpers are unreferenced**

Run:
```bash
grep -nE 'Write-ProjectSettings|Copy-ClaudeMd' setup.ps1
```
Expected: only matches inside the two function *definitions* themselves. No call sites elsewhere. If anything else matches, Task 4 missed something — go back and fix before continuing.

- [ ] **Step 2: Delete `Write-ProjectSettings`**

In `setup.ps1`, find and delete the entire function (was lines 1037-1047):

```powershell
function Write-ProjectSettings {
    $projectSettingsDir  = "$(Get-Location)\.claude"
    $projectSettingsFile = "$projectSettingsDir\settings.json"
    if (-not (Test-Path $projectSettingsDir)) { New-Item -ItemType Directory -Path $projectSettingsDir -Force | Out-Null }
    if (Test-Path $projectSettingsFile) {
        Copy-Item $projectSettingsFile "$projectSettingsFile.bak" -Force
        Write-Warn "Backed up existing project settings.json"
    }
    Write-RenderedSettings -DestPath $projectSettingsFile
    Write-Info "Project-level secrets protection + hooks written to $projectSettingsFile"
}
```

- [ ] **Step 3: Delete `Copy-ClaudeMd`**

In `setup.ps1`, find and delete the entire function (was lines 1049-1077, now slightly earlier after Step 2):

```powershell
function Copy-ClaudeMd {
    param([string]$Domain, [string]$ProjectType)
    $core   = "$ScriptDir\core\CLAUDE.md"
    # ... full body through closing brace
}
```

(Open the file and remove the entire function block — from the `function Copy-ClaudeMd {` line through its matching closing `}`. Read the file to find the exact closing-brace line before editing.)

- [ ] **Step 4: PowerShell syntax parse**

Run:
```powershell
powershell -NoProfile -Command "$errs = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\setup.ps1').Path, [ref]$null, [ref]$errs); if ($errs) { $errs | ForEach-Object { Write-Host $_.Message }; exit 1 } else { Write-Host 'parse OK' }"
```
Expected: `parse OK`.

- [ ] **Step 5: Confirm no references remain**

Run:
```bash
grep -nE 'Write-ProjectSettings|Copy-ClaudeMd' setup.ps1
```
Expected: zero matches.

- [ ] **Step 6: Commit**

```bash
git add setup.ps1
git commit -m "$(cat <<'EOF'
fix(setup.ps1): delete orphaned Write-ProjectSettings + Copy-ClaudeMd

These were only called from the project-level dispatch branch removed
in the prior commit. No callers remain.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update user-facing docs (`docs/user-guide.md`, `AGENTS.md`)

**Files:**
- Modify: `docs/user-guide.md:35-111` (drop project-level / user-level wording from "What setup does" and three Quick Start sections)
- Modify: `AGENTS.md:11-16` (rewrite "When a developer runs the setup script" list)
- Modify: `AGENTS.md:141-143` (rewrite "Setup scripts write these rules ... global ... project-level")

- [ ] **Step 1: Rewrite the "what setup does" lines in user-guide.md**

In `docs/user-guide.md`, find lines 44-47:

```markdown
7. Writes secrets-protection rules to `~/.claude/settings.json` (global) and
   `.claude/settings.json` (project-level run).
8. Writes domain rules to `~/.claude/CLAUDE.md` (user-level run) or
   `<project>/CLAUDE.md` (project-level run).
```

Replace with:

```markdown
7. Writes secrets-protection rules to `~/.claude/settings.json` (active for every Claude session, every project).
8. Writes the merged core + domain rules to `~/.claude/CLAUDE.md` (active for every Claude session, every project).
```

- [ ] **Step 2: Rewrite Quick Start — Native Windows**

In `docs/user-guide.md`, find lines 53-78 (the entire `## 2. Quick Start — Native Windows` section, ending just before `## 3. Quick Start — Native macOS / Linux`). Replace with:

```markdown
## 2. Quick Start — Native Windows

> Run from PowerShell or cmd.

```powershell
cd C:\tools\ai-sherpa
.\setup.bat
```

The script can also be invoked from anywhere by full path (e.g. `C:\tools\ai-sherpa\setup.bat`) — the current working directory does not affect the install. Setup writes only to `~/.claude/`.

You'll be prompted for one thing only:
- Domain (1–11)

Setup runs for 2–5 minutes. Restart your terminal, then:

```powershell
claude
```

code-review-graph runs in **auto mode** — no manual indexing step. The
SessionStart hook starts `crg-daemon` on first session and reuses it on
subsequent sessions. Drop a `.code-review-graphignore` at your project
root (template at `templates/code-review-graphignore` in this repo) to
control what gets indexed.

```

- [ ] **Step 3: Rewrite Quick Start — Native macOS / Linux**

In `docs/user-guide.md`, find lines 88-111 (the `## 3. Quick Start — Native macOS / Linux` section, ending just before `## 4. Quick Start — WSL + Windows Hybrid`). Replace with:

```markdown
## 3. Quick Start — Native macOS / Linux

> Always invoke with `bash`. **Do not** use `sh setup.sh` — `sh` is dash on Ubuntu/Debian and
> lacks bash features used by the script. The script will auto-correct if you do, but it's
> cleaner to call it right.

```bash
cd ~/tools/ai-sherpa
bash setup.sh
```

The script can also be invoked from anywhere by full path (e.g. `bash ~/tools/ai-sherpa/setup.sh`) — the current working directory does not affect the install. Setup writes only to `~/.claude/`.

After setup:

```bash
claude
# code-review-graph is in auto mode — no manual step needed
```

```

- [ ] **Step 4: Rewrite the "When a developer runs the setup script" list in AGENTS.md**

In `AGENTS.md`, find lines 11-16:

```markdown
When a developer runs the setup script from their project directory, the script:
1. Installs missing prerequisites (Node.js 20+, Git, Claude Code CLI)
2. Registers Claude Code plugin marketplaces and installs core + domain-specific plugins
3. Writes secrets-protection deny rules to `~/.claude/settings.json` (global) and `.claude/settings.json` (project-level)
4. Copies the selected domain's `CLAUDE.md` rules into the project root
5. Optionally installs the Graphify Python package for codebase indexing
```

Replace with:

```markdown
When a developer runs the setup script, the script:
1. Installs missing prerequisites (Node.js 20+, Git, Claude Code CLI)
2. Registers Claude Code plugin marketplaces and installs core + domain-specific plugins
3. Writes secrets-protection deny rules to `~/.claude/settings.json` (active for every Claude session)
4. Writes the merged core + domain `CLAUDE.md` rules to `~/.claude/CLAUDE.md` (active for every Claude session)
5. Installs the code-review-graph Python package (auto-mode via SessionStart hook)
```

(The phrase "from their project directory" is removed because CWD no longer affects what setup does. The "global + project-level" line collapses to "global only". Item 4 is rewritten so it matches what setup actually does today — the project-root copy is gone. Item 5 is updated from the long-stale "optionally installs Graphify" to the current code-review-graph behavior.)

- [ ] **Step 5: Rewrite the security note about settings rules in AGENTS.md**

In `AGENTS.md`, find line 143:

```markdown
- Setup scripts write these rules both globally (`~/.claude/settings.json`) and project-level (`.claude/settings.json`).
```

Replace with:

```markdown
- Setup scripts write these rules globally to `~/.claude/settings.json`. The rules apply to every Claude session regardless of project.
```

- [ ] **Step 6: Sanity-check no other "project-level" or "user-level" wording survived in user-guide or AGENTS**

Run:
```bash
grep -nE 'project-level|user-level run|user level|New project or existing|new vs existing' docs/user-guide.md AGENTS.md
```
Expected: no output. If anything matches, decide whether it's stale (rewrite) or correct in context (leave). Most likely all surviving hits are stale and should go.

- [ ] **Step 7: Commit**

```bash
git add docs/user-guide.md AGENTS.md
git commit -m "$(cat <<'EOF'
docs: drop user-level vs project-level setup distinction

setup.bat / setup.sh always install globally now. Rewrites the Quick
Start sections in user-guide.md and the "what setup does" / security
notes in AGENTS.md to match. Drops the "New or existing project?"
prompt note and the duplicate-config-in-project-root description.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: End-to-end smoke verification on a real machine

This task is manual and *should not* run on the engineer's primary machine unless they're comfortable with their `~/.claude/` being mutated. Prefer a throwaway VM, container, or CI runner. The goal is to confirm the spec's behavior: setup is CWD-independent and never writes to CWD.

**Files:** None modified — verification only.

- [ ] **Step 1: Pick a non-setup-repo CWD and run setup.bat (Windows)**

On a Windows machine with the repo at `D:\AI-Sherpa-Setup-master`:

```powershell
cd D:\some-empty-test-dir
D:\AI-Sherpa-Setup-master\setup.bat
```

When prompted for domain, pick `1` (embedded) or whatever the engineer prefers.

Expected behavior during the run:
- No "New project or existing project?" prompt fires.
- Log lines mention writes to `~/.claude/` only — never `D:\some-empty-test-dir\.claude\` or `D:\some-empty-test-dir\CLAUDE.md`.

- [ ] **Step 2: After Step 1 finishes, assert CWD is clean**

```powershell
Test-Path D:\some-empty-test-dir\CLAUDE.md
Test-Path D:\some-empty-test-dir\.claude
```
Expected: both print `False`. If either is `True`, a deletion was incomplete — go back and grep for any remaining write to `$PWD` / `$(Get-Location)` paths in `setup.ps1`.

- [ ] **Step 3: Assert the global install landed correctly**

```powershell
Test-Path $env:USERPROFILE\.claude\CLAUDE.md
Test-Path $env:USERPROFILE\.claude\settings.json
Get-Content $env:USERPROFILE\.claude\.ai-sherpa-state.json
```
Expected: both `Test-Path` print `True`; state file shows `{"domain": "...", "installed": "...", "version": "1"}`.

- [ ] **Step 4: Repeat the matrix on Linux/Mac with `setup.sh`**

```bash
cd /tmp/empty-test-dir   # any dir that's not the setup repo
bash /path/to/ai-sherpa/setup.sh
```

Then:

```bash
test ! -f /tmp/empty-test-dir/CLAUDE.md   && echo "OK: no CLAUDE.md in CWD"
test ! -d /tmp/empty-test-dir/.claude     && echo "OK: no .claude/ in CWD"
test -f ~/.claude/CLAUDE.md               && echo "OK: global CLAUDE.md written"
test -f ~/.claude/settings.json           && echo "OK: global settings written"
```

Expected: all four `OK:` lines print.

- [ ] **Step 5: Confirm `--update` and `--uninstall` still work**

```bash
bash /path/to/ai-sherpa/setup.sh --update    # or: setup.bat --update on Windows
```
Expected: existing behavior — no prompts, plugins refreshed. No regression.

```bash
bash /path/to/ai-sherpa/setup.sh --uninstall  # only if the engineer wants to actually uninstall
```

- [ ] **Step 6: No commit needed**

Task 7 is verification only. If any step fails, file an issue or re-open the relevant prior task to fix the gap, then re-run from Step 1.

---

## Self-Review (already performed during plan authoring)

**Spec coverage:**
- ✅ Spec "What Changes / setup.ps1" → Tasks 4, 5
- ✅ Spec "What Changes / setup.sh" → Tasks 2, 3
- ✅ Spec "Files Changed / docs/user-guide.md" → Task 6 Steps 1-3
- ✅ Spec "Files Changed / AGENTS.md" → Task 6 Steps 4-5
- ✅ Spec "Files Changed / scripts/test-setup.sh" → Tasks 1 (remove) and 3 (add regression guard)
- ✅ Spec Testing section 1-3 (Windows from various CWDs) → Task 7 Steps 1-3
- ✅ Spec Testing section 4-5 (--update, --uninstall) → Task 7 Step 5
- ✅ Spec Testing section 6 (no Read-Host / read -rp prompt) → covered by Task 2 Step 8 (grep) and Task 4 Step 4 (grep) plus Task 7 Step 1's expected behavior
- ✅ Spec Testing section 7 (Unix matrix) → Task 7 Step 4

**Placeholder scan:** every step has either exact code, an exact command with expected output, or an exact `git commit` invocation. No "TBD", no "add appropriate validation", no "similar to Task N". The "drop the `else` branch's full body" instructions reproduce the exact code they replace.

**Type / name consistency:** function names match between tasks (`write_project_settings`, `copy_claude_md`, `Write-ProjectSettings`, `Copy-ClaudeMd`); variable names match (`$isUserLevelRun`, `is_user_level`, `$projectType`, `project_type`); commit message references stay aligned with their respective task scope.
