# RTK GitHub-Release Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch `rtk` installation from `cargo install --git ...` to downloading the pre-built binary from `rtk-ai/rtk` GitHub releases. Eliminates the MSVC linker dependency that's blocking Windows installs without VS Build Tools.

**Architecture:** New `source: "github-release"` value in `plugins.json` tool schema, routed by `Install-Tools` (PS) / `install_tools` (Bash) to a new `Install-GitHubReleaseTool` / `install_github_release_tool` function that queries the GitHub Releases API, downloads the platform-specific asset, extracts the binary, and installs it to `~/.local/bin`. Skip-if-installed gate matches the pattern in commit `ff03996`. All failure modes surface as `[ACTION REQUIRED]` in the end-of-run report with copy-pasteable remediation.

**Tech Stack:** PowerShell 5.1+ (`Invoke-RestMethod`, `Invoke-WebRequest`, `Expand-Archive`), Bash 4+ (`curl`, `unzip`, `tar`, `node` for JSON parsing), GitHub REST API v3.

**Spec reference:** `docs/superpowers/specs/2026-06-02-rtk-github-release-installer-design.md`

**Out of scope:** Claude Code skip-if-at-latest (separate plan against spec `9352a41`). VS Build Tools detection or auto-install (no longer needed once rtk is off cargo).

---

## File structure for this plan

| Path | Action | Responsibility |
|---|---|---|
| `setup.ps1` | Modify | Add `Get-PlatformArchKey` helper + `Install-GitHubReleaseTool` function. Wire `Install-Tools` switch to route `source: "github-release"` entries. |
| `setup.sh` | Modify | Add `platform_arch_key` helper + `install_github_release_tool` function. Wire `install_tools` switch the same way. |
| `scripts/test-setup.ps1` | **Create** | PowerShell test harness (follows existing `scripts/test-setup.sh` pattern: dot-source `setup.ps1`, override key cmdlets via function shadowing, assert with helpers). |
| `scripts/test-setup.sh` | Modify | Extend with bash test cases for `install_github_release_tool`. |
| `plugins.json` | Modify | Switch the rtk entry in `tools.global[]` from `source: "cargo"` to `source: "github-release"` with platform-asset map. |
| `docs/admin-guide.md` | Modify | Document the new `source: "github-release"` value and its fields. |

---

## Task 1: Platform-arch detection helpers

**Files:**
- Modify: `setup.ps1` (add `Get-PlatformArchKey` near the existing `Test-CommandExists` / version helpers, around line 100)
- Modify: `setup.sh` (add `platform_arch_key` near `check_command`, around line 67)
- Create: `scripts/test-setup.ps1` (new PowerShell test harness)
- Modify: `scripts/test-setup.sh` (append platform_arch_key test)

- [ ] **Step 1.1: Create the new PowerShell test harness with platform-key test (failing — function doesn't exist yet)**

Create `scripts/test-setup.ps1`:

```powershell
#!/usr/bin/env pwsh
# Tests for setup.ps1 helper functions.
# Dot-sources setup.ps1 to load helpers; the main flow is guarded by an
# `if (-not $script:SourcedAsLibrary)` block so it won't run during tests.
# Exit 0 = all pass, exit 1 = at least one failure.

$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:SourcedAsLibrary = $true

# Dot-source the script under test
. "$RepoDir\setup.ps1"

$script:PASS = 0
$script:FAIL = 0

function Assert-True {
    param([string]$Name, $Value)
    if ($Value) { Write-Host "  PASS: $Name"; $script:PASS++ }
    else        { Write-Host "  FAIL: $Name (got falsy)"; $script:FAIL++ }
}

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ($Expected -eq $Actual) { Write-Host "  PASS: $Name"; $script:PASS++ }
    else                        { Write-Host "  FAIL: $Name"; Write-Host "        Expected: $Expected"; Write-Host "        Got:      $Actual"; $script:FAIL++ }
}

function Assert-Match {
    param([string]$Name, [string]$Pattern, $Actual)
    if ($Actual -match $Pattern) { Write-Host "  PASS: $Name"; $script:PASS++ }
    else                          { Write-Host "  FAIL: $Name"; Write-Host "        Pattern: $Pattern"; Write-Host "        Got:     $Actual"; $script:FAIL++ }
}

# ----- Test: Get-PlatformArchKey -----
Write-Host "=== Test: Get-PlatformArchKey ==="
$key = Get-PlatformArchKey
Assert-Match "Get-PlatformArchKey returns <os>-<arch>" '^(windows|linux|macos)-(x64|arm64)$' $key

# ----- Summary -----
Write-Host ""
Write-Host "Total: $($script:PASS) PASS / $($script:FAIL) FAIL"
exit $(if ($script:FAIL -gt 0) { 1 } else { 0 })
```

- [ ] **Step 1.2: Add the `$script:SourcedAsLibrary` guard to `setup.ps1` so the test harness can dot-source it without triggering the main flow**

In `setup.ps1`, find the line near the very bottom that begins the main flow (search for `# --- Main flow ---` or the first `Install-NodeJS` call). Wrap the entire main flow in a guard:

Use the Edit tool. The exact old_string depends on the current `setup.ps1` content (the line just before `Install-NodeJS` is invoked at top level). First inspect with:

```bash
grep -n "^Install-NodeJS\|^# --- Main flow\|^Show-Logo" "E:/cjain/AI sherpa/setup.ps1" | head -5
```

Then wrap the main-flow block with:

```powershell
# Skip the main flow when this script is dot-sourced as a library (e.g. by
# scripts/test-setup.ps1). The guard variable is set by the sourcing script
# before dot-sourcing.
if (-not $script:SourcedAsLibrary) {
    # ... existing main flow ...
}
```

- [ ] **Step 1.3: Run the test, verify it fails**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: `FAIL: Get-PlatformArchKey returns <os>-<arch>` (the function doesn't exist yet), exit code 1.

- [ ] **Step 1.4: Implement `Get-PlatformArchKey` in `setup.ps1`**

Use the Edit tool to add this function in `setup.ps1`, immediately after `Test-CommandExists` (search `grep -n "function Test-CommandExists" setup.ps1` to find the insertion point). Insert AFTER its closing `}`:

```powershell
# Returns a platform-arch key like "windows-x64", "linux-arm64", "macos-arm64".
# Used by Install-GitHubReleaseTool to look up the right asset in plugins.json.
# Defaults to "x64" on unrecognized architectures (no current tool ships
# 32-bit or exotic-arch binaries, so misdetection just falls into the
# platform-missing error path in the installer).
function Get-PlatformArchKey {
    $os = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'windows' }
          elseif ($IsLinux)   { 'linux' }
          elseif ($IsMacOS)   { 'macos' }
          else                { 'windows' }   # PS 5.1 has none of $IsWindows/$IsLinux/$IsMacOS; assume Windows
    $archRaw = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $arch = switch -Regex ($archRaw) {
        'Arm64'   { 'arm64'; break }
        'Arm'     { 'arm64'; break }   # 32-bit ARM treated as arm64 fallback
        'X64'     { 'x64'; break }
        default   { 'x64' }
    }
    return "$os-$arch"
}
```

- [ ] **Step 1.5: Run the test, verify it passes**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: `PASS: Get-PlatformArchKey returns <os>-<arch>`, exit 0.

- [ ] **Step 1.6: Append the bash test to `scripts/test-setup.sh` (failing — function doesn't exist yet)**

Find the end of the existing tests in `scripts/test-setup.sh` (the line `[[ $FAIL -gt 0 ]] && exit 1 || exit 0` near the bottom, or the last cleanup line if no final exit). Insert BEFORE that line:

```bash

# --- Test: platform_arch_key ---
echo "=== Test: platform_arch_key ==="
key=$(platform_arch_key)
if [[ "$key" =~ ^(windows|linux|macos)-(x64|arm64)$ ]]; then
  ok "platform_arch_key returns <os>-<arch>"
else
  fail "platform_arch_key returns <os>-<arch>" "<os>-<arch>" "$key"
fi
```

- [ ] **Step 1.7: Run, verify failure**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -10
```

Expected: `FAIL: platform_arch_key returns <os>-<arch>` (the function doesn't exist yet), exit 1 (some failure).

- [ ] **Step 1.8: Implement `platform_arch_key` in `setup.sh`**

In `setup.sh`, add immediately after the existing `check_command` function (`grep -n "^check_command()" setup.sh` to find it). Use the Edit tool, with old_string of `check_command() { command -v "$1" &>/dev/null; }` (or whatever the exact existing definition is — confirm first), and append after its closing `}`:

```bash

# Returns a platform-arch key like "windows-x64", "linux-arm64", "macos-arm64".
# Used by install_github_release_tool to look up the right asset in plugins.json.
platform_arch_key() {
  local os arch
  case "$(uname -s 2>/dev/null)" in
    Linux*)   os=linux ;;
    Darwin*)  os=macos ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *)        os=linux ;;  # fallback
  esac
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)        arch=x64 ;;
    aarch64|arm64)       arch=arm64 ;;
    *)                   arch=x64 ;;  # fallback; no current tool ships exotic arches
  esac
  echo "${os}-${arch}"
}
```

- [ ] **Step 1.9: Run, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -10
```

Expected: `PASS: platform_arch_key returns <os>-<arch>`, exit 0.

- [ ] **Step 1.10: Commit (exactly 4 files)**

```bash
cd "E:/cjain/AI sherpa"
git status --short setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only
# Expected: exactly the 4 files. Abort if anything else is staged.
git commit -m "$(cat <<'EOF'
feat(setup): add platform-arch detection helpers + PS test harness

Get-PlatformArchKey (PS) and platform_arch_key (Bash) return a
"<os>-<arch>" key like "windows-x64" or "macos-arm64". Used by the
forthcoming Install-GitHubReleaseTool to pick the right asset from a
plugins.json platform map.

Adds scripts/test-setup.ps1 as the PowerShell-side equivalent of
scripts/test-setup.sh — dot-sources setup.ps1 (guarded by a
$script:SourcedAsLibrary flag so the main flow doesn't run during
tests), provides Assert-True / Assert-Equal / Assert-Match helpers.

Implements only the platform-key helper; the rest of the
github-release installer follows in subsequent commits per the plan at
docs/superpowers/plans/2026-06-02-rtk-github-release-installer.md.
EOF
)"
```

---

## Task 2: GitHubReleaseTool skeleton with skip-if-installed gate

**Files:**
- Modify: `setup.ps1` (add `Install-GitHubReleaseTool` skeleton)
- Modify: `setup.sh` (add `install_github_release_tool` skeleton)
- Modify: `scripts/test-setup.ps1` (add skip-gate test)
- Modify: `scripts/test-setup.sh` (add skip-gate test)

- [ ] **Step 2.1: Add a failing test for the skip case to `scripts/test-setup.ps1`**

Use the Edit tool to insert the test BEFORE the `# ----- Summary -----` line:

```powershell

# ----- Test: Install-GitHubReleaseTool skip-if-installed -----
Write-Host "=== Test: Install-GitHubReleaseTool skip-if-installed ==="

# Override Test-CommandExists so "alreadyinstalledtool" looks installed.
function Test-CommandExists {
    param([string]$Cmd)
    return ($Cmd -eq 'alreadyinstalledtool')
}

# Override Get-Command (returns an object with .Source for the skip log line)
function Get-Command {
    param([string]$Cmd, [string]$ErrorAction)
    if ($Cmd -eq 'alreadyinstalledtool') {
        return [pscustomobject]@{ Source = 'C:\fake\path\alreadyinstalledtool.exe' }
    }
    return $null
}

# Capture Write-Info output by temporarily overriding it
$script:CapturedInfo = @()
function Write-Info {
    param([string]$msg)
    $script:CapturedInfo += $msg
}

# Call the function with a fake entry
$entry = [pscustomobject]@{
    name = 'alreadyinstalledtool'
    repo = 'fake/repo'
    asset = @{ 'windows-x64' = 'fake.zip' }
    binary = 'alreadyinstalledtool'
    destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entry

$found = $false
foreach ($line in $script:CapturedInfo) {
    if ($line -match '\[SKIP\]\s+alreadyinstalledtool already installed') { $found = $true; break }
}
Assert-True "Install-GitHubReleaseTool logs SKIP when already installed" $found
```

- [ ] **Step 2.2: Run, verify failure**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: `FAIL: Install-GitHubReleaseTool logs SKIP when already installed` (function doesn't exist), exit 1.

- [ ] **Step 2.3: Implement the skeleton in `setup.ps1` with only the skip gate**

Insert this function in `setup.ps1` near other `Install-*Tool` functions (search `grep -n "^function Install-CargoTool" setup.ps1` to find a sibling location, then insert AFTER its closing `}`):

```powershell
# Install a tool by downloading its pre-built binary from a GitHub release.
# Required Entry fields (from plugins.json):
#   - name        : binary name (without .exe; .exe is appended on Windows)
#   - repo        : "<owner>/<name>" — used to query /repos/<repo>/releases/latest
#   - asset       : hashtable of platform-arch -> asset filename in the release
#   - binary      : binary name to look for inside the extracted archive
#   - destination : install dir (~/.local/bin etc.; ~ is expanded)
# Optional:
#   - Upgrade switch: bypass the skip-if-installed gate
#
# Decision flow follows spec §Decision Flow Cases A through H.
function Install-GitHubReleaseTool {
    param($Entry, [switch]$Upgrade)

    # CASE A: skip if already installed and not forcing an upgrade.
    if (-not $Upgrade -and (Test-CommandExists $Entry.name)) {
        $loc = try { (Get-Command $Entry.name -ErrorAction SilentlyContinue).Source } catch { $null }
        $locSuffix = if ($loc) { " at $loc" } else { '' }
        Write-Info "  [SKIP]   $($Entry.name) already installed$locSuffix (run setup.bat --update to upgrade)"
        return
    }

    # Subsequent CASES B-H added in later tasks per the plan.
    Write-Info "  [TODO]   $($Entry.name) — Install-GitHubReleaseTool body pending (Tasks 3-6)"
}
```

- [ ] **Step 2.4: Run, verify pass**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: `PASS: Install-GitHubReleaseTool logs SKIP when already installed`, exit 0.

- [ ] **Step 2.5: Add bash skip-gate test to `scripts/test-setup.sh`**

Insert BEFORE the final summary lines:

```bash

# --- Test: install_github_release_tool skip-if-installed ---
echo "=== Test: install_github_release_tool skip-if-installed ==="
# Override check_command so "alreadyinstalledtool" looks installed
check_command() {
  [[ "$1" == "alreadyinstalledtool" ]] && return 0 || return 1
}
# Override command so `command -v` returns a fake path
command() {
  if [[ "$1" == "-v" && "$2" == "alreadyinstalledtool" ]]; then
    echo "/fake/path/alreadyinstalledtool"
    return 0
  fi
  builtin command "$@"
}
# Capture log output
captured_info=()
log_info() { captured_info+=("$*"); }

# Build a fake entry and call
fake_entry='{"name":"alreadyinstalledtool","repo":"fake/repo","asset":{"linux-x64":"fake.tar.gz"},"binary":"alreadyinstalledtool","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry" "false"

found=false
for line in "${captured_info[@]}"; do
  if [[ "$line" == *"[SKIP]"*"alreadyinstalledtool already installed"* ]]; then
    found=true
    break
  fi
done
if $found; then ok "install_github_release_tool logs SKIP when already installed"
else fail "install_github_release_tool logs SKIP" "[SKIP] line in output" "no SKIP line"
fi

# Restore originals
unset -f check_command command log_info
```

- [ ] **Step 2.6: Implement `install_github_release_tool` skeleton in `setup.sh`**

Insert after the existing `install_cargo_tool` (find with `grep -n "^install_cargo_tool()" setup.sh`):

```bash
# Install a tool by downloading its pre-built binary from a GitHub release.
# Args: <entry_json> <upgrade_bool>
# Required Entry fields (from plugins.json, parsed via node -e):
#   - name        : binary name
#   - repo        : "<owner>/<name>"
#   - asset       : object mapping platform-arch -> asset filename
#   - binary      : binary name to look for inside the extracted archive
#   - destination : install dir (~/.local/bin etc.)
install_github_release_tool() {
  local entry_json="$1" upgrade="${2:-false}"
  local name; name=$(echo "$entry_json" | node -e "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{const j=JSON.parse(s);process.stdout.write(j.name||'')})")

  # CASE A: skip if already installed and not forcing an upgrade.
  if [[ "$upgrade" != "true" ]] && check_command "$name"; then
    local loc; loc=$(command -v "$name" 2>/dev/null)
    log_info "  [SKIP]   $name already installed${loc:+ at $loc} (run setup.sh --update to upgrade)"
    return 0
  fi

  # CASES B-H added in later tasks per the plan.
  log_info "  [TODO]   $name — install_github_release_tool body pending (Tasks 3-6)"
}
```

- [ ] **Step 2.7: Run bash tests, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -10
```

Expected: `PASS: install_github_release_tool logs SKIP when already installed`, exit 0.

- [ ] **Step 2.8: Commit (exactly 4 files)**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only   # confirm exactly 4 files
git commit -m "$(cat <<'EOF'
feat(setup): Install-GitHubReleaseTool skeleton with skip-if-installed

Adds the function shell in both setup.ps1 and setup.sh, implementing
only Case A from spec §Decision Flow: if the tool's binary is already
on PATH and we're not in explicit --update mode, log [SKIP] and return.

Tests in scripts/test-setup.ps1 and scripts/test-setup.sh verify the
skip path by overriding Test-CommandExists / check_command. The body
of the function (Cases B-H) is stubbed with a [TODO] log line for now;
subsequent commits per the plan flesh out the remaining cases.
EOF
)"
```

---

## Task 3: GitHub release manifest fetch (CASE C: API failure handling)

**Files:**
- Modify: `setup.ps1` (`Install-GitHubReleaseTool` — add manifest fetch + CASE C)
- Modify: `setup.sh` (`install_github_release_tool` — same)
- Modify: `scripts/test-setup.ps1` (add API-failure test)
- Modify: `scripts/test-setup.sh` (add API-failure test)

- [ ] **Step 3.1: Add a failing test for CASE C (API rate-limit / network failure) to `scripts/test-setup.ps1`**

Insert BEFORE the summary block:

```powershell

# ----- Test: Install-GitHubReleaseTool surfaces API failure as ACTION REQUIRED -----
Write-Host "=== Test: Install-GitHubReleaseTool API failure ==="

# Override Test-CommandExists so the tool looks NOT installed (bypass skip gate).
function Test-CommandExists { param([string]$Cmd) return $false }

# Override Invoke-RestMethod to throw (simulating network / 403 rate limit)
function Invoke-RestMethod { throw "rate limited (test)" }

# Capture Write-Action output
$script:CapturedAction = @()
function Write-Action {
    param([string]$msg)
    $script:CapturedAction += $msg
}

# Capture Add-UserAction calls
$script:CapturedUserActions = @()
function Add-UserAction {
    param([string]$Title, [string]$Why, [string]$Command)
    $script:CapturedUserActions += [pscustomobject]@{ Title = $Title; Why = $Why; Command = $Command }
}

$entry = [pscustomobject]@{
    name = 'rtk'
    repo = 'rtk-ai/rtk'
    asset = @{ 'windows-x64' = 'rtk-x86_64-pc-windows-msvc.zip' }
    binary = 'rtk'
    destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entry

Assert-True "API failure emits Write-Action" ($script:CapturedAction.Count -gt 0)
Assert-True "API failure adds a UserAction" ($script:CapturedUserActions.Count -gt 0)
if ($script:CapturedUserActions.Count -gt 0) {
    Assert-Match "UserAction Command mentions browser_download_url or releases page" 'releases' $script:CapturedUserActions[0].Command
}
```

- [ ] **Step 3.2: Run, verify failure**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: the API-failure test fails (function doesn't fetch manifest yet, so no Write-Action / Add-UserAction emitted), exit 1.

- [ ] **Step 3.3: Implement manifest fetch + CASE C in `setup.ps1`**

Use the Edit tool to replace the entire `Install-GitHubReleaseTool` function body. The old_string is the current skeleton (from Task 2):

```powershell
function Install-GitHubReleaseTool {
    param($Entry, [switch]$Upgrade)

    # CASE A: skip if already installed and not forcing an upgrade.
    if (-not $Upgrade -and (Test-CommandExists $Entry.name)) {
        $loc = try { (Get-Command $Entry.name -ErrorAction SilentlyContinue).Source } catch { $null }
        $locSuffix = if ($loc) { " at $loc" } else { '' }
        Write-Info "  [SKIP]   $($Entry.name) already installed$locSuffix (run setup.bat --update to upgrade)"
        return
    }

    # Subsequent CASES B-H added in later tasks per the plan.
    Write-Info "  [TODO]   $($Entry.name) — Install-GitHubReleaseTool body pending (Tasks 3-6)"
}
```

The new_string adds manifest fetch + CASE C:

```powershell
function Install-GitHubReleaseTool {
    param($Entry, [switch]$Upgrade)

    # CASE A: skip if already installed and not forcing an upgrade.
    if (-not $Upgrade -and (Test-CommandExists $Entry.name)) {
        $loc = try { (Get-Command $Entry.name -ErrorAction SilentlyContinue).Source } catch { $null }
        $locSuffix = if ($loc) { " at $loc" } else { '' }
        Write-Info "  [SKIP]   $($Entry.name) already installed$locSuffix (run setup.bat --update to upgrade)"
        return
    }

    Write-Info "Installing $($Entry.name) (github-release: $($Entry.repo))..."

    # Fetch latest release manifest from GitHub.
    $apiUrl = "https://api.github.com/repos/$($Entry.repo)/releases/latest"
    $manifest = $null
    try {
        $manifest = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'ai-sherpa-setup' } -TimeoutSec 30
    } catch {
        # CASE C: API query failed (network, 403 rate limit, 5xx)
        Write-Action "$($Entry.name) download failed: GitHub API at $apiUrl returned an error ($($_.Exception.Message))."
        Add-UserAction -Title "Manually install $($Entry.name)" `
                       -Why "Setup couldn't reach GitHub's release API for $($Entry.repo). The API call failed with: $($_.Exception.Message). This is usually transient (rate limit, network), but if it persists check corporate firewall / proxy settings." `
                       -Command "Download the latest release manually from https://github.com/$($Entry.repo)/releases, extract the binary '$($Entry.binary)' from the platform-appropriate asset, and place it on PATH."
        return
    }

    # Subsequent CASES B, D, E, F, G, H added in later tasks per the plan.
    Write-Info "  [TODO]   $($Entry.name) — Install-GitHubReleaseTool body pending (Tasks 4-6)"
}
```

- [ ] **Step 3.4: Run, verify pass**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: all PS tests pass including the new API-failure one. Exit 0.

- [ ] **Step 3.5: Add the same test to `scripts/test-setup.sh`**

Insert BEFORE the final summary lines:

```bash

# --- Test: install_github_release_tool surfaces API failure as ACTION REQUIRED ---
echo "=== Test: install_github_release_tool API failure ==="
# Bypass skip gate: tool looks NOT installed
check_command() { return 1; }
# Override curl to fail
curl() { return 22; }
# Capture log_action and add_user_action calls
captured_action=()
captured_user_actions=()
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

fake_entry='{"name":"rtk","repo":"rtk-ai/rtk","asset":{"linux-x64":"rtk-x86_64-unknown-linux-musl.tar.gz"},"binary":"rtk","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry" "false"

if [[ ${#captured_action[@]} -gt 0 ]]; then
  ok "API failure emits log_action"
else
  fail "API failure emits log_action" "non-empty captured_action" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then
  ok "API failure adds a user_action"
  if [[ "${captured_user_actions[0]}" == *"releases"* ]]; then
    ok "user_action command mentions releases page"
  else
    fail "user_action command mentions releases page" "releases in command" "${captured_user_actions[0]}"
  fi
else
  fail "API failure adds a user_action" "non-empty captured_user_actions" "empty"
fi

# Restore originals
unset -f check_command curl log_action add_user_action
```

- [ ] **Step 3.6: Implement manifest fetch + CASE C in `setup.sh`**

Replace `install_github_release_tool`'s current body (the skeleton from Task 2) with the manifest-fetch version. Use the Edit tool — the old_string is the entire current function body, new_string is:

```bash
install_github_release_tool() {
  local entry_json="$1" upgrade="${2:-false}"
  local name repo binary destination
  # Parse entry fields via node (already a dependency for plugins.json parsing)
  read -r name repo binary destination <<<"$(echo "$entry_json" | node -e "
let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{const j=JSON.parse(s);
process.stdout.write([j.name||'',j.repo||'',j.binary||'',j.destination||''].join(' '))})")"

  # CASE A: skip if already installed and not forcing an upgrade.
  if [[ "$upgrade" != "true" ]] && check_command "$name"; then
    local loc; loc=$(command -v "$name" 2>/dev/null)
    log_info "  [SKIP]   $name already installed${loc:+ at $loc} (run setup.sh --update to upgrade)"
    return 0
  fi

  log_info "Installing $name (github-release: $repo)..."

  # Fetch latest release manifest from GitHub.
  local api_url="https://api.github.com/repos/$repo/releases/latest"
  local manifest
  if ! manifest=$(curl --fail --silent --show-error \
      --user-agent "ai-sherpa-setup" \
      --connect-timeout 10 --max-time 30 \
      "$api_url" 2>&1); then
    # CASE C: API query failed
    log_action "$name download failed: GitHub API at $api_url returned an error."
    add_user_action "Manually install $name" \
      "Setup couldn't reach GitHub's release API for $repo. This is usually transient (rate limit, network), but if it persists check corporate firewall / proxy." \
      "Download the latest release manually from https://github.com/$repo/releases, extract the binary '$binary' from the platform-appropriate asset, and place it on PATH."
    return 0
  fi

  # Subsequent CASES B, D, E, F, G, H added in later tasks per the plan.
  log_info "  [TODO]   $name — install_github_release_tool body pending (Tasks 4-6)"
}
```

- [ ] **Step 3.7: Run bash tests, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -15
```

Expected: all bash tests still pass + the 3 new ones. Exit 0.

- [ ] **Step 3.8: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(setup): Install-GitHubReleaseTool fetches release manifest (Case C)

Adds the GitHub API call to /repos/<repo>/releases/latest. On any
failure (network error, rate limit, 5xx, timeout) the installer
surfaces a [ACTION REQUIRED] entry with a manual-download URL
pointing at https://github.com/<repo>/releases.

Tests verify that an Invoke-RestMethod (PS) / curl (Bash) failure
results in non-empty Write-Action / log_action output and an
Add-UserAction / add_user_action entry that mentions the releases page.

Subsequent commits per the plan add asset selection (Cases B + D),
download + extract (Cases E + F + G), and the happy path (Case H).
EOF
)"
```

---

## Task 4: Asset selection (CASE B: platform missing; CASE D: asset rename)

**Files:**
- Modify: `setup.ps1` (`Install-GitHubReleaseTool` — add platform key lookup + asset URL resolution)
- Modify: `setup.sh` (same)
- Modify: `scripts/test-setup.ps1` (add CASE B + CASE D tests)
- Modify: `scripts/test-setup.sh` (same)

- [ ] **Step 4.1: Add failing tests for CASES B and D to `scripts/test-setup.ps1`**

Insert BEFORE the summary block:

```powershell

# ----- Test: Install-GitHubReleaseTool ACTION REQUIRED on missing platform asset -----
Write-Host "=== Test: Install-GitHubReleaseTool platform missing (CASE B) ==="

function Test-CommandExists { return $false }

# Return a successful manifest with one asset (but for a different platform than ours)
function Invoke-RestMethod {
    return [pscustomobject]@{
        assets = @(
            [pscustomobject]@{ name = 'something-else.zip'; browser_download_url = 'https://example.invalid/x' }
        )
    }
}

$script:CapturedAction = @()
$script:CapturedUserActions = @()
function Write-Action { param([string]$msg) $script:CapturedAction += $msg }
function Add-UserAction {
    param([string]$Title, [string]$Why, [string]$Command)
    $script:CapturedUserActions += [pscustomobject]@{ Title = $Title; Why = $Why; Command = $Command }
}

# Entry with NO key for the current platform (force CASE B via empty asset map)
$entry = [pscustomobject]@{
    name = 'rtk'
    repo = 'rtk-ai/rtk'
    asset = @{ 'freebsd-x64' = 'fake.zip' }   # not the current platform
    binary = 'rtk'
    destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entry

Assert-True "CASE B: no asset for platform -> Write-Action emitted" ($script:CapturedAction.Count -gt 0)
Assert-True "CASE B: no asset for platform -> Add-UserAction collected" ($script:CapturedUserActions.Count -gt 0)


# ----- Test: Install-GitHubReleaseTool ACTION REQUIRED on asset rename (CASE D) -----
Write-Host "=== Test: Install-GitHubReleaseTool asset rename (CASE D) ==="

$script:CapturedAction = @()
$script:CapturedUserActions = @()

# Entry whose asset name is NOT present in the (mocked) manifest's assets[]
$entry2 = [pscustomobject]@{
    name = 'rtk'
    repo = 'rtk-ai/rtk'
    asset = @{ "$(Get-PlatformArchKey)" = 'expected-name-not-in-manifest.zip' }
    binary = 'rtk'
    destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entry2

Assert-True "CASE D: asset name mismatch -> Write-Action emitted" ($script:CapturedAction.Count -gt 0)
Assert-True "CASE D: asset name mismatch -> Add-UserAction collected" ($script:CapturedUserActions.Count -gt 0)
if ($script:CapturedUserActions.Count -gt 0) {
    Assert-Match "CASE D: UserAction Why lists actual asset names" 'something-else\.zip' $script:CapturedUserActions[0].Why
}
```

- [ ] **Step 4.2: Run, verify failures**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: 4 of the new CASE B + D assertions fail (the function hits the manifest-success path but has no asset-selection logic yet, so it falls into the `[TODO]` log line). Exit 1.

- [ ] **Step 4.3: Extend `Install-GitHubReleaseTool` with CASE B + CASE D logic**

Replace the `# Subsequent CASES B, D, E, F, G, H added in later tasks per the plan.` line + the `[TODO]` log line at the bottom of `Install-GitHubReleaseTool` with:

```powershell
    # CASE B: no asset declared for this platform.
    $platformKey = Get-PlatformArchKey
    $assetName = $Entry.asset.$platformKey
    if (-not $assetName) {
        Write-Action "$($Entry.name): no pre-built asset declared for platform '$platformKey'."
        Add-UserAction -Title "Manually install $($Entry.name) for $platformKey" `
                       -Why "$($Entry.repo) doesn't ship a binary for $platformKey via this plugins.json entry. You can build from source, use a package manager, or check the repo's README for platform-specific instructions." `
                       -Command "Build from source: cargo install --git https://github.com/$($Entry.repo)   (requires Rust + native build tools on $platformKey)"
        return
    }

    # CASE D: declared asset name not in the latest release.
    $asset = $manifest.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        $availableNames = ($manifest.assets | ForEach-Object { $_.name }) -join ', '
        Write-Action "$($Entry.name): expected asset '$assetName' not found in latest release of $($Entry.repo)."
        Add-UserAction -Title "Update $($Entry.name) asset name in plugins.json" `
                       -Why "plugins.json declares asset '$assetName' for $platformKey, but the latest release of $($Entry.repo) doesn't have that file. Upstream likely renamed it. Available assets in this release: $availableNames" `
                       -Command "Edit plugins.json tools.global[] entry for '$($Entry.name)'. Change asset.$platformKey to one of the names listed above, then re-run setup."
        return
    }

    # Subsequent CASES E, F, G, H added in later tasks per the plan.
    Write-Info "  [TODO]   $($Entry.name) — download+extract pending (Tasks 5-6)"
```

- [ ] **Step 4.4: Run, verify pass**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: all PS tests pass including the new B + D ones. Exit 0.

- [ ] **Step 4.5: Add the equivalent bash tests to `scripts/test-setup.sh`**

Insert BEFORE the final summary lines:

```bash

# --- Test: install_github_release_tool platform missing (CASE B) ---
echo "=== Test: install_github_release_tool platform missing (CASE B) ==="
check_command() { return 1; }
# curl returns a manifest with an asset that doesn't match our platform
curl() {
  echo '{"assets":[{"name":"something-else.tar.gz","browser_download_url":"https://example.invalid/x"}]}'
  return 0
}
captured_action=()
captured_user_actions=()
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

# Use an asset map that DOES NOT contain the current platform key
fake_entry_b='{"name":"rtk","repo":"rtk-ai/rtk","asset":{"freebsd-x64":"fake.zip"},"binary":"rtk","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry_b" "false"

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE B emits log_action"
else fail "CASE B emits log_action" "non-empty" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then ok "CASE B adds user_action"
else fail "CASE B adds user_action" "non-empty" "empty"
fi

# --- Test: install_github_release_tool asset rename (CASE D) ---
echo "=== Test: install_github_release_tool asset rename (CASE D) ==="
captured_action=()
captured_user_actions=()

current_key=$(platform_arch_key)
# Asset map contains the current platform key, but the asset name doesn't match the (mocked) manifest
fake_entry_d="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"expected-name-not-in-manifest.zip\"},\"binary\":\"rtk\",\"destination\":\"/tmp/test-dest\"}"
install_github_release_tool "$fake_entry_d" "false"

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE D emits log_action"
else fail "CASE D emits log_action" "non-empty" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then
  ok "CASE D adds user_action"
  if [[ "${captured_user_actions[0]}" == *"something-else.tar.gz"* ]]; then
    ok "CASE D user_action lists actual asset names"
  else
    fail "CASE D user_action lists actual asset names" "something-else.tar.gz in why" "${captured_user_actions[0]}"
  fi
else
  fail "CASE D adds user_action" "non-empty" "empty"
fi

unset -f check_command curl log_action add_user_action
```

- [ ] **Step 4.6: Extend `install_github_release_tool` with CASE B + CASE D in `setup.sh`**

Use the Edit tool to replace the `# Subsequent CASES B, D, E, F, G, H added in later tasks per the plan.` line and the `[TODO]` log line at the bottom with:

```bash
  # Parse platform key and asset map from the entry
  local platform_key; platform_key=$(platform_arch_key)
  local asset_name; asset_name=$(echo "$entry_json" | node -e "
let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{const j=JSON.parse(s);
const a=(j.asset||{})['$platform_key']||'';process.stdout.write(a)})")

  # CASE B: no asset declared for this platform.
  if [[ -z "$asset_name" ]]; then
    log_action "$name: no pre-built asset declared for platform '$platform_key'."
    add_user_action "Manually install $name for $platform_key" \
      "$repo doesn't ship a binary for $platform_key via this plugins.json entry. You can build from source, use a package manager, or check the repo's README for platform-specific instructions." \
      "Build from source: cargo install --git https://github.com/$repo   (requires Rust + native build tools on $platform_key)"
    return 0
  fi

  # CASE D: declared asset name not in the latest release.
  local asset_url; asset_url=$(echo "$manifest" | node -e "
let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{
  try{const j=JSON.parse(s);
    const found=(j.assets||[]).find(a=>a.name==='$asset_name');
    process.stdout.write(found?found.browser_download_url:'')
  }catch(e){}
})")
  if [[ -z "$asset_url" ]]; then
    local available; available=$(echo "$manifest" | node -e "
let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{
  try{const j=JSON.parse(s);process.stdout.write((j.assets||[]).map(a=>a.name).join(', '))}catch(e){}
})")
    log_action "$name: expected asset '$asset_name' not found in latest release of $repo."
    add_user_action "Update $name asset name in plugins.json" \
      "plugins.json declares asset '$asset_name' for $platform_key, but the latest release of $repo doesn't have that file. Upstream likely renamed it. Available assets in this release: $available" \
      "Edit plugins.json tools.global[] entry for '$name'. Change asset.$platform_key to one of the names listed above, then re-run setup."
    return 0
  fi

  # Subsequent CASES E, F, G, H added in later tasks per the plan.
  log_info "  [TODO]   $name — download+extract pending (Tasks 5-6) (asset: $asset_name)"
```

- [ ] **Step 4.7: Run bash tests, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -20
```

Expected: all bash tests pass including B + D. Exit 0.

- [ ] **Step 4.8: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(setup): Install-GitHubReleaseTool asset selection (Cases B + D)

CASE B: if plugins.json's asset map has no entry for the current
platform-arch key, surface [ACTION REQUIRED] with a cargo-install
fallback (build from source).

CASE D: if the declared asset name isn't in the latest release's
assets[] list, surface [ACTION REQUIRED] listing the actual asset
names from the manifest so the admin can update plugins.json with
the right name.

Tests cover both cases by overriding Invoke-RestMethod / curl to
return controlled manifests and verifying Write-Action /
Add-UserAction are populated.
EOF
)"
```

---

## Task 5: Download + extract + locate binary (CASES E + F + G)

**Files:**
- Modify: `setup.ps1` (`Install-GitHubReleaseTool` — add download, extract, find-binary)
- Modify: `setup.sh` (same)
- Modify: `scripts/test-setup.ps1` (add CASE E + F + G tests)
- Modify: `scripts/test-setup.sh` (same)

- [ ] **Step 5.1: Add failing tests for CASES E + F + G to `scripts/test-setup.ps1`**

Insert BEFORE the summary block:

```powershell

# ----- Test: Install-GitHubReleaseTool CASE E (HTTP download fails) -----
Write-Host "=== Test: Install-GitHubReleaseTool download failure (CASE E) ==="

function Test-CommandExists { return $false }

# Manifest succeeds, returning an asset that matches the entry
$assetUrl = 'https://example.invalid/rtk.zip'
function Invoke-RestMethod {
    return [pscustomobject]@{
        assets = @([pscustomobject]@{ name = 'rtk-test.zip'; browser_download_url = $assetUrl })
    }
}

# But Invoke-WebRequest fails
function Invoke-WebRequest { param($Uri, $OutFile, $TimeoutSec) throw "connection refused (test)" }

$script:CapturedAction = @()
$script:CapturedUserActions = @()
function Write-Action { param([string]$msg) $script:CapturedAction += $msg }
function Add-UserAction {
    param([string]$Title, [string]$Why, [string]$Command)
    $script:CapturedUserActions += [pscustomobject]@{ Title = $Title; Why = $Why; Command = $Command }
}

$entryE = [pscustomobject]@{
    name = 'rtk'; repo = 'rtk-ai/rtk'
    asset = @{ "$(Get-PlatformArchKey)" = 'rtk-test.zip' }
    binary = 'rtk'; destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entryE

Assert-True "CASE E: download failure -> Write-Action emitted" ($script:CapturedAction.Count -gt 0)
if ($script:CapturedUserActions.Count -gt 0) {
    Assert-Match "CASE E: UserAction Command contains the asset URL for manual download" 'example\.invalid' $script:CapturedUserActions[0].Command
}


# ----- Test: Install-GitHubReleaseTool CASE G (binary missing from archive) -----
Write-Host "=== Test: Install-GitHubReleaseTool binary missing (CASE G) ==="

# Override Invoke-WebRequest to actually create a temp zip without the expected binary
function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    # Create an empty zip on disk so Expand-Archive succeeds but produces no binary
    $tmpDir = Split-Path -Parent $OutFile
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $emptyContentDir = Join-Path $tmpDir 'empty-zip-content'
    if (Test-Path $emptyContentDir) { Remove-Item $emptyContentDir -Recurse -Force }
    New-Item -ItemType Directory -Path $emptyContentDir -Force | Out-Null
    'placeholder' | Set-Content (Join-Path $emptyContentDir 'something-else.txt')
    Compress-Archive -Path "$emptyContentDir\*" -DestinationPath $OutFile -Force
    Remove-Item $emptyContentDir -Recurse -Force
}

$script:CapturedAction = @()
$script:CapturedUserActions = @()

$entryG = [pscustomobject]@{
    name = 'rtk'; repo = 'rtk-ai/rtk'
    asset = @{ "$(Get-PlatformArchKey)" = 'rtk-test.zip' }
    binary = 'rtk-not-in-archive'; destination = "$env:TEMP\test-dest"
}
Install-GitHubReleaseTool -Entry $entryG

Assert-True "CASE G: binary not in archive -> Write-Action emitted" ($script:CapturedAction.Count -gt 0)
```

- [ ] **Step 5.2: Run, verify failures**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: CASE E + G tests fail (function still hits the `[TODO]` after asset selection). Exit 1.

- [ ] **Step 5.3: Extend `Install-GitHubReleaseTool` with CASES E + F + G in `setup.ps1`**

Replace the `# Subsequent CASES E, F, G, H added in later tasks per the plan.` line + the `[TODO]` log line with:

```powershell
    # Download asset to a temp file.
    $tmpDir = Join-Path $env:TEMP "ghrt-$([Guid]::NewGuid().ToString().Substring(0,8))"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpFile = Join-Path $tmpDir $assetName
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpFile -TimeoutSec 120
    } catch {
        # CASE E: download failed
        Write-Action "$($Entry.name) download failed: $($_.Exception.Message)"
        Add-UserAction -Title "Manually download $($Entry.name)" `
                       -Why "Setup couldn't download the asset at $($asset.browser_download_url). $($_.Exception.Message)" `
                       -Command "Download $($asset.browser_download_url) to a folder, extract '$($Entry.binary)' from it, and place the binary on PATH."
        try { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        return
    }

    # Extract archive.
    $extractDir = Join-Path $tmpDir 'extracted'
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    try {
        if ($assetName -match '\.zip$') {
            Expand-Archive -Path $tmpFile -DestinationPath $extractDir -Force
        } elseif ($assetName -match '\.tar\.gz$|\.tgz$') {
            # Windows 10+ ships bsdtar as 'tar'. On Win 7/8 fall back to error.
            & tar -xzf $tmpFile -C $extractDir
            if ($LASTEXITCODE -ne 0) { throw "tar exited non-zero ($LASTEXITCODE)" }
        } else {
            throw "unsupported archive format: $assetName"
        }
    } catch {
        # CASE F: extraction failed
        Write-Action "$($Entry.name) extract failed: $($_.Exception.Message)"
        Add-UserAction -Title "Manually extract $($Entry.name)" `
                       -Why "Setup downloaded $assetName to $tmpFile but couldn't extract it. $($_.Exception.Message)" `
                       -Command "Open $tmpFile in a file manager, extract '$($Entry.binary)' to a folder on your PATH."
        return
    }

    # Locate binary in extracted tree.
    $binFileName = if ($platformKey -like 'windows-*') { "$($Entry.binary).exe" } else { $Entry.binary }
    $foundBin = Get-ChildItem -Path $extractDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq $binFileName } |
                Select-Object -First 1
    if (-not $foundBin) {
        # CASE G: binary not in archive
        $contents = (Get-ChildItem -Path $extractDir -Recurse -File | ForEach-Object { $_.Name }) -join ', '
        Write-Action "$($Entry.name): archive '$assetName' didn't contain expected binary '$binFileName'."
        Add-UserAction -Title "Locate $($Entry.name) binary manually" `
                       -Why "Expected to find '$binFileName' in the extracted archive but didn't. Files in the archive: $contents. Upstream may have restructured the release." `
                       -Command "Inspect $extractDir, find the binary, copy it to a folder on your PATH (e.g. `$env:USERPROFILE\.local\bin)."
        return
    }

    # Subsequent CASE H added in the next task per the plan.
    Write-Info "  [TODO]   $($Entry.name) — install to destination pending (Task 6) (found at $($foundBin.FullName))"
```

- [ ] **Step 5.4: Run PS tests, verify pass**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: all PS tests pass. Exit 0.

- [ ] **Step 5.5: Add equivalent bash tests to `scripts/test-setup.sh`**

Insert BEFORE the final summary:

```bash

# --- Test: install_github_release_tool download failure (CASE E) ---
echo "=== Test: install_github_release_tool CASE E ==="
check_command() { return 1; }
current_key=$(platform_arch_key)
# First curl call (manifest) succeeds; second (download) is expected to fail.
# We track invocation count via a global.
_curl_count=0
curl() {
  _curl_count=$((_curl_count + 1))
  if [[ $_curl_count -eq 1 ]]; then
    # manifest call
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  # download call: fail
  return 22
}
captured_action=()
captured_user_actions=()
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

fake_entry_e="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk\",\"destination\":\"/tmp/test-dest\"}"
install_github_release_tool "$fake_entry_e" "false"

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE E emits log_action"
else fail "CASE E emits log_action" "non-empty" "empty"
fi

# --- Test: install_github_release_tool binary missing in archive (CASE G) ---
echo "=== Test: install_github_release_tool CASE G ==="
captured_action=()
captured_user_actions=()
_curl_count=0
# Manifest call succeeds; download call creates an empty zip on disk
curl() {
  _curl_count=$((_curl_count + 1))
  if [[ $_curl_count -eq 1 ]]; then
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  # Download: take the --output path (5th arg after --output flag) and create a fake zip there
  # curl args are: --fail --silent --show-error --user-agent X --connect-timeout X --max-time X --output <path> <url>
  # We extract the --output path from $@
  local out_path=""
  local prev=""
  for a in "$@"; do
    if [[ "$prev" == "--output" || "$prev" == "-o" ]]; then out_path="$a"; break; fi
    prev="$a"
  done
  [[ -z "$out_path" ]] && return 22
  local empty_dir
  empty_dir=$(mktemp -d)
  echo placeholder > "$empty_dir/something-else.txt"
  (cd "$empty_dir" && zip -q -r "$out_path" .)
  rm -rf "$empty_dir"
  return 0
}

fake_entry_g="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk-not-in-archive\",\"destination\":\"/tmp/test-dest\"}"
install_github_release_tool "$fake_entry_g" "false"

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE G emits log_action"
else fail "CASE G emits log_action" "non-empty" "empty"
fi

unset -f check_command curl log_action add_user_action
```

- [ ] **Step 5.6: Extend `install_github_release_tool` with CASES E + F + G in `setup.sh`**

Replace the existing `# Subsequent CASES E, F, G, H added in later tasks per the plan.` line + the `[TODO]` log line at the bottom with:

```bash
  # Download asset to a temp file.
  local tmp_dir; tmp_dir=$(mktemp -d -t ghrt-XXXXXXXX)
  local tmp_file="$tmp_dir/$asset_name"
  if ! curl --fail --silent --show-error \
       --user-agent "ai-sherpa-setup" \
       --connect-timeout 10 --max-time 120 \
       --output "$tmp_file" "$asset_url" 2>/dev/null; then
    # CASE E: download failed
    log_action "$name download failed: could not fetch $asset_url"
    add_user_action "Manually download $name" \
      "Setup couldn't download the asset at $asset_url. This is usually transient (network) but may also be corporate firewall / proxy." \
      "Download $asset_url to a folder, extract '$binary' from it, and place the binary on PATH."
    rm -rf "$tmp_dir"
    return 0
  fi

  # Extract archive.
  local extract_dir="$tmp_dir/extracted"
  mkdir -p "$extract_dir"
  local extract_ok=true
  if [[ "$asset_name" == *.zip ]]; then
    unzip -q "$tmp_file" -d "$extract_dir" || extract_ok=false
  elif [[ "$asset_name" == *.tar.gz || "$asset_name" == *.tgz ]]; then
    tar -xzf "$tmp_file" -C "$extract_dir" || extract_ok=false
  else
    extract_ok=false
  fi
  if ! $extract_ok; then
    # CASE F: extraction failed
    log_action "$name extract failed for $asset_name"
    add_user_action "Manually extract $name" \
      "Setup downloaded $asset_name to $tmp_file but couldn't extract it." \
      "Open $tmp_file in a file manager / extract manually, find '$binary' inside, copy to a folder on your PATH."
    return 0
  fi

  # Locate binary in extracted tree.
  local bin_file_name="$binary"
  [[ "$platform_key" == windows-* ]] && bin_file_name="${binary}.exe"
  local found_bin
  found_bin=$(find "$extract_dir" -type f -name "$bin_file_name" 2>/dev/null | head -1)
  if [[ -z "$found_bin" ]]; then
    # CASE G: binary not in archive
    local contents; contents=$(find "$extract_dir" -type f -printf "%f, " 2>/dev/null | sed 's/, $//')
    log_action "$name: archive '$asset_name' didn't contain expected binary '$bin_file_name'."
    add_user_action "Locate $name binary manually" \
      "Expected to find '$bin_file_name' in the extracted archive but didn't. Files in archive: $contents. Upstream may have restructured the release." \
      "Inspect $extract_dir, find the binary, copy it to a folder on PATH (e.g. ~/.local/bin)."
    return 0
  fi

  # Subsequent CASE H added in the next task per the plan.
  log_info "  [TODO]   $name — install to destination pending (Task 6) (found at $found_bin)"
```

- [ ] **Step 5.7: Run bash tests, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -20
```

Expected: all tests pass including E + G. Exit 0.

- [ ] **Step 5.8: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(setup): Install-GitHubReleaseTool download + extract (Cases E,F,G)

CASE E: download via Invoke-WebRequest (PS) / curl (Bash). On any
network failure or non-2xx, surface [ACTION REQUIRED] with the direct
asset URL for manual download.

CASE F: extract via Expand-Archive for .zip, `tar -xzf` for .tar.gz /
.tgz. On extraction failure (corrupt archive, missing unzip/tar),
surface [ACTION REQUIRED] with the downloaded file path.

CASE G: locate the expected binary inside the extracted tree
(appending .exe on Windows). If missing, surface [ACTION REQUIRED]
listing the actual files in the archive so the admin can update
plugins.json `binary` field if upstream restructured.

Tests cover CASE E (download failure) and CASE G (binary missing).
CASE F is exercised implicitly by the unsupported-format branch when
plugins.json declares a non-zip/non-tar.gz asset.
EOF
)"
```

---

## Task 6: Move binary to destination + PATH (CASE H happy path)

**Files:**
- Modify: `setup.ps1` (complete `Install-GitHubReleaseTool` with Case H)
- Modify: `setup.sh` (same)
- Modify: `scripts/test-setup.ps1` (add happy-path test)
- Modify: `scripts/test-setup.sh` (same)

- [ ] **Step 6.1: Add a happy-path test to `scripts/test-setup.ps1`**

Insert BEFORE the summary block:

```powershell

# ----- Test: Install-GitHubReleaseTool happy path (CASE H) -----
Write-Host "=== Test: Install-GitHubReleaseTool happy path (CASE H) ==="

function Test-CommandExists { return $false }

$assetUrlH = 'https://example.invalid/rtk.zip'
function Invoke-RestMethod {
    return [pscustomobject]@{
        assets = @([pscustomobject]@{ name = 'rtk-test.zip'; browser_download_url = $assetUrlH })
    }
}

# Invoke-WebRequest creates a real zip on disk that DOES contain the expected binary
function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    $tmpDir = Split-Path -Parent $OutFile
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $stagingDir = Join-Path $tmpDir 'staging'
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    # Build the binary filename to embed in the zip
    $binName = if ((Get-PlatformArchKey) -like 'windows-*') { 'rtk.exe' } else { 'rtk' }
    'fake-binary-contents' | Set-Content (Join-Path $stagingDir $binName)
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $OutFile -Force
    Remove-Item $stagingDir -Recurse -Force
}

# Capture log lines
$script:CapturedInfo = @()
function Write-Info { param([string]$msg) $script:CapturedInfo += $msg }

# Override Add-WindowsUserPath so we can detect a call without actually mutating PATH
$script:PathDirsAdded = @()
function Add-WindowsUserPath { param([string]$Dir) $script:PathDirsAdded += $Dir }

$destDir = Join-Path $env:TEMP "ghrt-test-dest-$([Guid]::NewGuid().ToString().Substring(0,8))"
$entryH = [pscustomobject]@{
    name = 'rtk'; repo = 'rtk-ai/rtk'
    asset = @{ "$(Get-PlatformArchKey)" = 'rtk-test.zip' }
    binary = 'rtk'; destination = $destDir
}
Install-GitHubReleaseTool -Entry $entryH

$binNameH = if ((Get-PlatformArchKey) -like 'windows-*') { 'rtk.exe' } else { 'rtk' }
$expectedPath = Join-Path $destDir $binNameH

Assert-True "CASE H: binary moved to destination" (Test-Path $expectedPath)
Assert-True "CASE H: destination dir added to PATH" ($script:PathDirsAdded -contains $destDir)
$gotReadyLog = $false
foreach ($line in $script:CapturedInfo) {
    if ($line -match '\[READY\]\s+rtk') { $gotReadyLog = $true; break }
}
Assert-True "CASE H: [READY] log line emitted" $gotReadyLog

# Cleanup
try { Remove-Item $destDir -Recurse -Force } catch {}
```

- [ ] **Step 6.2: Run, verify failure**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: CASE H assertions fail (function still hits `[TODO]` at end). Exit 1.

- [ ] **Step 6.3: Complete `Install-GitHubReleaseTool` with CASE H in `setup.ps1`**

Replace the `# Subsequent CASE H added in the next task per the plan.` line + the `[TODO]` log line at the bottom of `Install-GitHubReleaseTool` with:

```powershell
    # CASE H: success. Move binary to destination, add to PATH.
    $destDir = $Entry.destination
    if ($destDir.StartsWith('~')) { $destDir = $destDir -replace '^~', $env:USERPROFILE }
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    $destPath = Join-Path $destDir $binFileName
    try {
        Move-Item -Path $foundBin.FullName -Destination $destPath -Force
    } catch {
        Write-Action "$($Entry.name) install failed: couldn't move binary to $destPath"
        Add-UserAction -Title "Manually move $($Entry.name) binary" `
                       -Why "Setup extracted the binary but couldn't write to $destPath. $($_.Exception.Message)" `
                       -Command "Copy $($foundBin.FullName) to a folder on your PATH (e.g. `$env:USERPROFILE\.local\bin) manually."
        try { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        return
    }
    Add-WindowsUserPath $destDir
    try { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Info "  [READY]  $($Entry.name) installed to $destPath"
```

- [ ] **Step 6.4: Run PS tests, verify pass**

```bash
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: all PS tests pass. Exit 0.

- [ ] **Step 6.5: Add the happy-path test to `scripts/test-setup.sh`**

Insert BEFORE the final summary:

```bash

# --- Test: install_github_release_tool happy path (CASE H) ---
echo "=== Test: install_github_release_tool CASE H ==="
check_command() { return 1; }
current_key=$(platform_arch_key)
_curl_count=0
curl() {
  _curl_count=$((_curl_count + 1))
  if [[ $_curl_count -eq 1 ]]; then
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  # Download: create a real zip on disk with the binary inside
  local out_path=""
  local prev=""
  for a in "$@"; do
    if [[ "$prev" == "--output" || "$prev" == "-o" ]]; then out_path="$a"; break; fi
    prev="$a"
  done
  [[ -z "$out_path" ]] && return 22
  local staging; staging=$(mktemp -d)
  local bin_name="rtk"
  [[ "$current_key" == windows-* ]] && bin_name="rtk.exe"
  echo fake-binary-contents > "$staging/$bin_name"
  (cd "$staging" && zip -q -r "$out_path" .)
  rm -rf "$staging"
  return 0
}

captured_info=()
log_info() { captured_info+=("$*"); }

# Override the bash equivalent of Add-WindowsUserPath. For Linux/macOS, we
# just track invocations; the actual implementation will export PATH.
path_dirs_added=()
_record_path_dir() { path_dirs_added+=("$1"); }

# Replace export to track destination dir addition (bash equivalent)
# We use a wrapper since install_github_release_tool runs `export PATH=...`
# Actually for the test, we just verify the destination file exists.

# Pick a fresh tmp dest
dest_dir=$(mktemp -d -t ghrt-test-dest-XXXXXXXX)
fake_entry_h="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk\",\"destination\":\"$dest_dir\"}"
install_github_release_tool "$fake_entry_h" "false"

expected_bin="$dest_dir/rtk"
[[ "$current_key" == windows-* ]] && expected_bin="$dest_dir/rtk.exe"

if [[ -f "$expected_bin" ]]; then ok "CASE H: binary moved to destination"
else fail "CASE H: binary moved to destination" "file at $expected_bin" "not found"
fi

got_ready=false
for line in "${captured_info[@]}"; do
  if [[ "$line" == *"[READY]"*"rtk"* ]]; then got_ready=true; break; fi
done
if $got_ready; then ok "CASE H: [READY] log line emitted"
else fail "CASE H: [READY] log line emitted" "[READY] rtk in log" "not found"
fi

rm -rf "$dest_dir"
unset -f check_command curl log_info
```

- [ ] **Step 6.6: Complete `install_github_release_tool` with CASE H in `setup.sh`**

Replace the existing `# Subsequent CASE H added in the next task per the plan.` line + the `[TODO]` log line at the bottom with:

```bash
  # CASE H: success. Move binary to destination, add to PATH.
  local dest_dir="$destination"
  [[ "$dest_dir" == ~* ]] && dest_dir="${dest_dir/#~/$HOME}"
  mkdir -p "$dest_dir"
  local dest_path="$dest_dir/$bin_file_name"
  if ! mv "$found_bin" "$dest_path" 2>/dev/null; then
    log_action "$name install failed: couldn't move binary to $dest_path"
    add_user_action "Manually move $name binary" \
      "Setup extracted the binary but couldn't write to $dest_path. Check directory permissions." \
      "Copy $found_bin to a folder on your PATH (e.g. ~/.local/bin) manually."
    rm -rf "$tmp_dir"
    return 0
  fi
  chmod +x "$dest_path" 2>/dev/null
  export PATH="$dest_dir:$PATH"
  rm -rf "$tmp_dir"
  log_info "  [READY]  $name installed to $dest_path"
```

- [ ] **Step 6.7: Run all tests, verify pass**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -25
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
```

Expected: both exit 0 with all PASS lines, no FAIL.

- [ ] **Step 6.8: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh scripts/test-setup.ps1 scripts/test-setup.sh
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(setup): Install-GitHubReleaseTool complete (CASE H happy path)

After download+extract+locate succeed, move the binary to the
configured destination (default: ~/.local/bin), make it executable
on Unix, and add the destination directory to PATH (via
Add-WindowsUserPath on PS, export PATH on Bash).

Tests verify a happy-path install end-to-end: mocked
Invoke-WebRequest / curl produces a real zip on disk containing a
fake binary; setup extracts it, moves to a temp destination, and
emits [READY] log line.

With this commit Install-GitHubReleaseTool implements all 8 cases
from spec §Decision Flow (A through H). Wire-up to Install-Tools
follows in Task 7.
EOF
)"
```

---

## Task 7: Wire `github-release` source into `Install-Tools` / `install_tools`

**Files:**
- Modify: `setup.ps1` (`Install-Tools` — add `'github-release'` case)
- Modify: `setup.sh` (`install_tools` — same)

- [ ] **Step 7.1: Add the case to `Install-Tools` in `setup.ps1`**

Find the existing switch with `grep -n "switch (\\\$t.source)" setup.ps1`. The current cases are likely `'pypi'`, `'cargo'`, `'git-clone'`. Use the Edit tool to add the new case. Old_string is the existing switch, including its trailing `default` case:

```powershell
        switch ($t.source) {
            'pypi'      { Install-PyPiTool      -Name $t.name -Package $t.package -PostInstall $t.postInstall -Upgrade:$Upgrade }
            'cargo'     { Install-CargoTool     -Name $t.name -Git $t.git -Package $t.package -Upgrade:$Upgrade }
            'git-clone' { Install-GitCloneTool  -Name $t.name -Repo $t.repo -Destination $t.destination -PostInstall $t.postInstall }
            default     { Write-Warn "Unknown tool source '$($t.source)' for $($t.name); skipping." }
        }
```

new_string adds `'github-release'`:

```powershell
        switch ($t.source) {
            'pypi'           { Install-PyPiTool           -Name $t.name -Package $t.package -PostInstall $t.postInstall -Upgrade:$Upgrade }
            'cargo'          { Install-CargoTool          -Name $t.name -Git $t.git -Package $t.package -Upgrade:$Upgrade }
            'git-clone'      { Install-GitCloneTool       -Name $t.name -Repo $t.repo -Destination $t.destination -PostInstall $t.postInstall }
            'github-release' { Install-GitHubReleaseTool  -Entry $t -Upgrade:$Upgrade }
            default          { Write-Warn "Unknown tool source '$($t.source)' for $($t.name); skipping." }
        }
```

- [ ] **Step 7.2: Add the case to `install_tools` in `setup.sh`**

Find the bash switch with `grep -n 'case "\$source"' setup.sh` or similar. Likely structure:

```bash
case "$source" in
  pypi)      install_pypi_tool ... ;;
  cargo)     install_cargo_tool ... ;;
  git-clone) install_git_clone_tool ... ;;
  *)         log_warn "Unknown tool source '$source' for $name; skipping." ;;
esac
```

Use the Edit tool to add `github-release)` before the `*)` case. The new line:

```bash
  github-release) install_github_release_tool "$entry_json" "$upgrade_flag" ;;
```

Note: the existing pypi/cargo cases pass individual fields; the github-release one passes the entire entry JSON (since it has more fields). The `entry_json` variable should be available where the case statement runs. If it's not, this step also adds it: read the relevant `for entry in ...` loop and ensure each iteration captures the raw entry JSON to a local `entry_json` variable before the case statement. The existing JSON-parsing code in `install_tools` (via `node -e`) is the template.

- [ ] **Step 7.3: Manual integration check**

Add a small ad-hoc test by running setup against a `plugins.json` fake (don't commit this; it's a quick sanity check):

```bash
cd "E:/cjain/AI sherpa"
# Create a one-entry test plugins.json
cat > /tmp/test-plugins.json <<'JSON'
{
  "marketplaces": [],
  "global": [],
  "domains": { "test": [] },
  "skills": { "global": [] },
  "tools": {
    "global": [
      {
        "name": "definitely-not-installed-tool-xyz",
        "source": "github-release",
        "repo": "rtk-ai/rtk",
        "asset": { "linux-x64": "rtk-x86_64-unknown-linux-musl.tar.gz", "macos-x64": "rtk-x86_64-apple-darwin.tar.gz", "windows-x64": "rtk-x86_64-pc-windows-msvc.zip" },
        "binary": "rtk",
        "destination": "~/.local/bin"
      }
    ]
  }
}
JSON
# Run only the Install-Tools function with our fake config
pwsh -Command "& { . 'E:/cjain/AI sherpa/setup.ps1' ; \$ScriptDir = 'E:/cjain/AI sherpa' ; \$tmp = '/tmp/test-plugins.json' ; \$config = Get-Content \$tmp -Raw | ConvertFrom-Json ; \$entry = \$config.tools.global[0] ; Install-GitHubReleaseTool -Entry \$entry }"
```

Expected: the call attempts to download rtk's actual Windows binary into `~/.local/bin/rtk.exe`. Should succeed. Verify `rtk --version` after.

Don't commit `/tmp/test-plugins.json`; it's just for the integration check.

- [ ] **Step 7.4: Commit (just the two setup files)**

```bash
cd "E:/cjain/AI sherpa"
git add setup.ps1 setup.sh
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(setup): wire source: github-release into Install-Tools switch

Install-Tools (PS) and install_tools (Bash) now route plugins.json
tools entries with source: "github-release" to the new
Install-GitHubReleaseTool / install_github_release_tool functions.
Existing pypi / cargo / git-clone routings are unchanged.

This is the integration step that connects the schema (Task 8) to
the installer (Tasks 2-6). With this commit + Task 8's plugins.json
change, rtk install switches from cargo to github-release on the
next setup run.
EOF
)"
```

---

## Task 8: Switch rtk's `plugins.json` entry to `github-release`

**Files:**
- Modify: `plugins.json` (the rtk entry in `tools.global[]`)

- [ ] **Step 8.1: Inspect the current entry**

```bash
node -e "const j=JSON.parse(require('fs').readFileSync('E:/cjain/AI sherpa/plugins.json'));console.log(JSON.stringify(j.tools.global.find(t=>t.name==='rtk'),null,2))"
```

Expected output:
```json
{
  "name": "rtk",
  "source": "cargo",
  "git": "https://github.com/rtk-ai/rtk"
}
```

- [ ] **Step 8.2: Replace the rtk entry**

Use the Edit tool on `E:\cjain\AI sherpa\plugins.json` with this old_string (matches the current entry; verify with the inspection in Step 8.1 — if it doesn't match exactly, adapt):

```json
      {
        "name": "rtk",
        "source": "cargo",
        "git": "https://github.com/rtk-ai/rtk"
      },
```

new_string:

```json
      {
        "name": "rtk",
        "source": "github-release",
        "repo": "rtk-ai/rtk",
        "asset": {
          "windows-x64": "rtk-x86_64-pc-windows-msvc.zip",
          "linux-x64":   "rtk-x86_64-unknown-linux-musl.tar.gz",
          "macos-x64":   "rtk-x86_64-apple-darwin.tar.gz",
          "macos-arm64": "rtk-aarch64-apple-darwin.tar.gz"
        },
        "binary": "rtk",
        "destination": "~/.local/bin"
      },
```

(Note: if the current entry doesn't end with a trailing comma — e.g. it's the last in `tools.global[]` — adjust both strings to omit the comma.)

- [ ] **Step 8.3: Validate JSON syntax + lint**

```bash
cd "E:/cjain/AI sherpa"
node -e "JSON.parse(require('fs').readFileSync('plugins.json'))" && echo "plugins.json is valid JSON"
node scripts/lint-invocation-tables.js
echo "lint exit: $?"
```

Expected: "plugins.json is valid JSON" + lint exits 0 (no rtk-related issues; rtk isn't in any invocation contract since it's a tool, not a plugin).

- [ ] **Step 8.4: Run full test suite to confirm no regression**

```bash
bash "E:/cjain/AI sherpa/scripts/test-setup.sh" 2>&1 | tail -10
pwsh -File "E:/cjain/AI sherpa/scripts/test-setup.ps1"
bash "E:/cjain/AI sherpa/scripts/test-lint-invocation.sh"
```

Expected: all 3 test runs exit 0.

- [ ] **Step 8.5: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add plugins.json
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
feat(plugins): switch rtk install from cargo to github-release

rtk's plugins.json tools.global[] entry now uses
source: "github-release" with a platform-asset map pointing at
upstream's pre-built Windows / Linux / macOS binaries. Upstream
(rtk-ai/rtk) officially supports and recommends these binaries
in their README.

Eliminates the MSVC linker / VS Build Tools requirement for
Windows installs (the blocker CHJAIN hit). ~5 MB download +
~10s instead of compiling from source + 2-5 GB of build tools.

Windows-ARM64 users hit CASE B (no asset for platform) and
get an ACTION REQUIRED with a cargo-install fallback;
upstream doesn't currently ship an ARM64 Windows asset.
EOF
)"
```

---

## Task 9: Update `docs/admin-guide.md`

**Files:**
- Modify: `docs/admin-guide.md`

- [ ] **Step 9.1: Inspect the existing tools section**

```bash
grep -n -A 5 "tools" "E:/cjain/AI sherpa/docs/admin-guide.md" | head -50
```

Find the section that documents the existing tool source types (`pypi`, `cargo`, `git-clone`). If no such section exists yet, find a logical insertion point (probably near the bottom, or wherever plugin/skill schemas are documented).

- [ ] **Step 9.2: Append documentation for `github-release` source**

Use the Edit tool. The old_string depends on the existing structure of admin-guide.md. If there's an existing tools-source list, append the new entry to it. If not, add a new subsection. Suggested content:

```markdown
### `source: "github-release"`

Downloads a pre-built binary from a GitHub release. Use when upstream
ships binaries (avoids the compiler dependency of `source: "cargo"`).

Required fields:

| Field         | Type   | Description                                                        |
|---------------|--------|--------------------------------------------------------------------|
| `name`        | string | Binary name (no `.exe`; appended on Windows automatically)         |
| `repo`        | string | `<owner>/<name>` — used as `https://api.github.com/repos/<repo>/releases/latest` |
| `asset`       | object | Map of `<os>-<arch>` → asset filename in the GitHub release        |
| `binary`      | string | Binary name to look for inside the extracted archive               |
| `destination` | string | Install directory; `~` is expanded                                 |

Asset map keys use the format `<os>-<arch>` where `<os>` is one of
`windows` / `linux` / `macos` and `<arch>` is one of `x64` / `arm64`.

Example (rtk):

```json
{
  "name": "rtk",
  "source": "github-release",
  "repo": "rtk-ai/rtk",
  "asset": {
    "windows-x64": "rtk-x86_64-pc-windows-msvc.zip",
    "linux-x64":   "rtk-x86_64-unknown-linux-musl.tar.gz",
    "macos-x64":   "rtk-x86_64-apple-darwin.tar.gz",
    "macos-arm64": "rtk-aarch64-apple-darwin.tar.gz"
  },
  "binary": "rtk",
  "destination": "~/.local/bin"
}
```

Installer behavior:

- On re-runs where `<name>` is already on PATH, the installer logs
  `[SKIP]   <name> already installed at <path>` and returns. Use
  `setup.bat --update` to force a fresh download.
- If no asset is declared for the current platform-arch, surfaces
  `[ACTION REQUIRED]` with a `cargo install --git <repo>` fallback
  suggestion.
- If the declared asset name isn't in the latest release, surfaces
  `[ACTION REQUIRED]` listing the actual asset names so the admin
  knows what to update in `plugins.json`.
- If the binary isn't found inside the extracted archive, surfaces
  `[ACTION REQUIRED]` listing the archive contents.
- All other failures (network, extraction) fall through to
  `[ACTION REQUIRED]` with the direct asset URL for manual download.
```

- [ ] **Step 9.3: Commit**

```bash
cd "E:/cjain/AI sherpa"
git add docs/admin-guide.md
git diff --cached --name-only
git commit -m "$(cat <<'EOF'
docs(admin-guide): document plugins.json source: github-release

Document the new tool source type added by the rtk migration:
field schema, asset-map key format (<os>-<arch>), example using
rtk's real configuration, and the installer's behavior across the
8 cases from spec §Decision Flow (skip / platform missing / API
failure / asset rename / download failure / extract failure /
binary missing / success).
EOF
)"
```

---

## End-of-phase verification

After all 9 tasks, run:

```bash
cd "E:/cjain/AI sherpa"

# 1. PS test harness
pwsh -File scripts/test-setup.ps1

# 2. Bash test harness
bash scripts/test-setup.sh

# 3. Lint
node scripts/lint-invocation-tables.js
bash scripts/test-lint-invocation.sh

# 4. JSON validity
node -e "JSON.parse(require('fs').readFileSync('plugins.json'))" && echo "plugins.json valid"

# 5. Setup script syntax
pwsh -Command "[System.Management.Automation.Language.Parser]::ParseFile('setup.ps1', [ref]\$null, [ref]\$null) | Out-Null; 'setup.ps1 parses'"
bash -n setup.sh && echo "setup.sh parses"

# 6. Commit log review
git log master..HEAD --oneline
# Expected: ~9 commits, one per task
```

All checks should exit 0 / print success.

## Manual smoke test (on a real Windows machine without VS Build Tools)

Not a coding task — this verifies the change works end-to-end on a clean
machine like CHJAIN's:

1. On a fresh Windows machine that does NOT have Visual Studio Build Tools
   installed, run `setup.bat` (or `git pull && setup.bat` if AI Sherpa is
   already cloned).
2. Watch the install log. Expected:
   ```
   [AI Sherpa]   Installing rtk (github-release: rtk-ai/rtk)...
   [AI Sherpa]   [READY]  rtk installed to C:\Users\<name>\.local\bin\rtk.exe
   ```
   No `link.exe not found` error. No compilation. Total elapsed for rtk:
   ~10-30s.
3. Verify rtk launches: `rtk --version`. Expected: prints a version
   string. If it errors with `The program can't start because
   VCRUNTIME140.dll is missing`, the rtk binary requires the Microsoft
   Visual C++ Redistributable — file as a follow-up (per Risk #3 in the
   spec) to install it via `winget install
   Microsoft.VCRedist.2015+.x64`. ~25 MB, much smaller than Build Tools.
4. Re-run `setup.bat`. Expected:
   ```
   [AI Sherpa]   [SKIP]   rtk already installed at C:\Users\<name>\.local\bin\rtk.exe (run setup.bat --update to upgrade)
   ```
5. Run `setup.bat --update`. Expected: rtk install runs again (bypass
   skip), downloads + installs. Same `[READY]` line at the end.

Document any failures in this smoke test as new issues. None block the
plan's per-task acceptance; they go in as separate follow-up fixes.

---

## What's next

- **Claude Code skip-if-at-latest plan** (separate; spec `9352a41`). After
  this rtk plan ships, draft that plan and execute it the same way.
- **Generalize `github-release` to other tools** (deferred). If a second
  tool wants to use this source type, no schema change needed — admin just
  flips its plugins.json entry. The installer is already generic.
