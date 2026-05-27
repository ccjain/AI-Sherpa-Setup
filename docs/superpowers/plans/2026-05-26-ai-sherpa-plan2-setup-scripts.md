# AI Sherpa — Plan 2: Setup Scripts

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `setup.sh` (Linux/macOS) and `setup.bat` + `setup.ps1` (Windows) that install prerequisites, skills, secrets settings, and domain CLAUDE.md in under 5 minutes per developer, from a clean machine.

**Architecture:** `setup.bat` is a thin launcher that calls `setup.ps1`. `setup.sh` is a self-contained Bash script. Both share the same logical flow: prerequisites → domain selection → core skills → domain skills → global settings.json → project settings.json → CLAUDE.md → summary. Helper functions are unit-tested before the main flow is wired up.

**Tech Stack:** Bash (Linux/macOS), PowerShell 5.1+ (Windows), winget (Windows package manager), nvm (Node version manager, Linux/macOS), `npx skillsadd` (skills.sh CLI).

**Plans in this series:**
- Plan 1: Repository structure + all configuration files ✅ DONE (tag v0.1.0)
- **Plan 2 (this plan):** Setup scripts ← START HERE
- Plan 3: User documentation

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `setup.sh` | Create | Linux/macOS full setup script (< 300 lines) |
| `setup.ps1` | Create | Windows PowerShell full setup script (< 300 lines) |
| `setup.bat` | Create | Windows thin launcher — calls setup.ps1 (< 10 lines) |
| `scripts/test-setup.sh` | Create | Unit tests for setup.sh helper functions |

**No sub-scripts needed** — all five domains fit inline with shared helper functions. The line limit is met without splitting.

---

## Design Notes (Read Before Implementing)

**SCRIPT_DIR vs PWD:** `SCRIPT_DIR` is always the ai-sherpa repo root (where setup.sh lives). `PWD` is the developer's project directory (where CLAUDE.md and `.claude/settings.json` should be written). These are different directories.

**Run location guard:** setup.sh/setup.ps1 must detect if the developer is running from inside the ai-sherpa repo and warn them to cd to their project first.

**Two settings.json targets:**
1. `~/.claude/settings.json` — global, protects all projects on the machine
2. `$PWD/.claude/settings.json` — project-level, belt-and-suspenders

Both get the same deny rules from `settings/settings-template.json`.

**graphify is a Claude Code slash command** — it cannot be invoked from a shell script. The setup script installs the skill and prints instructions to run `/graphify` inside Claude Code.

**`--update` skips CLAUDE.md** — updates skills and settings.json only, never touches project CLAUDE.md customisations.

**skillsadd is idempotent** — running `npx skillsadd obra/superpowers` twice is safe. The update path re-runs all installs.

---

## Task 1: setup.sh Helper Functions + Unit Tests

**Files:**
- Create: `setup.sh` (functions only — no `main()` yet)
- Create: `scripts/test-setup.sh`

The source guard `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` at the bottom of setup.sh prevents `main` from running when the test script sources it.

- [ ] **Step 1: Create `scripts/test-setup.sh` (will fail — functions not yet defined)**

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; echo "        Expected: $2"; echo "        Got: $3"; ((FAIL++)); }

assert_file_exists() {
  [[ -f "$2" ]] && ok "$1" || fail "$1" "file at $2" "not found"
}
assert_file_contains() {
  grep -q "$3" "$2" 2>/dev/null && ok "$1" || fail "$1" "pattern '$3' in $2" "not found"
}
assert_no_file() {
  [[ ! -f "$2" ]] && ok "$1" || fail "$1" "no file at $2" "file exists"
}
assert_true() {
  [[ "$2" == "0" ]] && ok "$1" || fail "$1" "exit 0" "exit $2"
}
assert_false() {
  [[ "$2" != "0" ]] && ok "$1" || fail "$1" "exit non-zero" "exit 0"
}

# Source helper functions from setup.sh (main() is guarded so it won't run)
source "$REPO_DIR/setup.sh"

# --- Test check_command ---
echo "=== Test: check_command ==="
check_command "bash"; assert_true "check_command true for bash" "$?"
check_command "nonexistent_cmd_xyz_999" 2>/dev/null; assert_false "check_command false for missing cmd" "$?"

# --- Test write_settings ---
echo "=== Test: write_settings ==="
TMP=$(mktemp -d)
HOME_BAK="$HOME"; HOME="$TMP"

write_settings
assert_file_exists "global settings.json created" "$TMP/.claude/settings.json"
assert_file_contains "global settings has Read .env rule" "$TMP/.claude/settings.json" '"Read'
assert_file_contains "global settings has Write .env rule" "$TMP/.claude/settings.json" '"Write'

# Second call creates backup
write_settings
assert_file_exists "settings.json.bak created on second run" "$TMP/.claude/settings.json.bak"

HOME="$HOME_BAK"; rm -rf "$TMP"

# --- Test write_project_settings ---
echo "=== Test: write_project_settings ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

write_project_settings
assert_file_exists "project .claude/settings.json created" "$TMP/.claude/settings.json"
assert_file_contains "project settings has Read .env rule" "$TMP/.claude/settings.json" '"Read'

popd > /dev/null; rm -rf "$TMP"

# --- Test copy_claude_md — new project ---
echo "=== Test: copy_claude_md (new project) ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

copy_claude_md "web" "new"
assert_file_exists "CLAUDE.md created" "$TMP/CLAUDE.md"
assert_file_contains "CLAUDE.md has web rules" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"

# --- Test copy_claude_md — existing project (append) ---
echo "=== Test: copy_claude_md (existing project — appends) ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

echo "# My existing project rules" > CLAUDE.md
copy_claude_md "web" "existing"
assert_file_contains "original content preserved" "$TMP/CLAUDE.md" "My existing project rules"
assert_file_contains "domain rules appended" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Create scripts/ directory and run tests to confirm failure**

```bash
mkdir -p "E:/cjain/AI sherpa/scripts"
cd "E:/cjain/AI sherpa"
bash scripts/test-setup.sh
```

Expected: error like `bash: write_settings: command not found` — functions not defined yet.

- [ ] **Step 3: Create `setup.sh` with helper functions (no main yet)**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[AI Sherpa]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[AI Sherpa]${NC} $1"; }
log_error() { echo -e "${RED}[AI Sherpa]${NC} $1"; }

check_command() { command -v "$1" &>/dev/null; }

write_settings() {
  local settings_dir="$HOME/.claude"
  local settings_file="$settings_dir/settings.json"
  mkdir -p "$settings_dir"
  if [[ -f "$settings_file" ]]; then
    cp "$settings_file" "${settings_file}.bak"
    log_warn "Backed up existing settings.json to ${settings_file}.bak"
  fi
  cp "$SCRIPT_DIR/settings/settings-template.json" "$settings_file"
  log_info "Secrets protection written to $settings_file"
}

write_project_settings() {
  local project_settings_dir="$PWD/.claude"
  local project_settings_file="$project_settings_dir/settings.json"
  mkdir -p "$project_settings_dir"
  if [[ -f "$project_settings_file" ]]; then
    cp "$project_settings_file" "${project_settings_file}.bak"
    log_warn "Backed up existing project settings.json"
  fi
  cp "$SCRIPT_DIR/settings/settings-template.json" "$project_settings_file"
  log_info "Project-level secrets protection written to $project_settings_file"
}

copy_claude_md() {
  local domain="$1" project_type="$2"
  local source="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending domain rules to existing CLAUDE.md (original preserved)"
    printf '\n---\n<!-- AI Sherpa domain rules — do not edit below this line -->\n' >> "$target"
    cat "$source" >> "$target"
  else
    cp "$source" "$target"
  fi
  log_info "Domain CLAUDE.md installed at $target"
}

install_core_skills() {
  log_info "Installing core skills (this may take 1-2 minutes)..."
  npx skillsadd obra/superpowers
  npx skillsadd safishamsi/graphify
  npx skillsadd mattpocock/skills
  npx skillsadd pbakaus/impeccable
  npx skillsadd sentry/dev
  log_info "Core skills installed."
}

install_domain_skills() {
  local domain="$1"
  case "$domain" in
    web)
      log_info "Installing web/frontend skills..."
      npx skillsadd anthropics/skills
      npx skillsadd vercel-labs/agent-skills
      npx skillsadd vercel-labs/next-skills
      npx skillsadd vercel-labs/agent-browser
      npx skillsadd shadcn/ui
      ;;
    devops)
      log_info "Installing DevOps skills..."
      npx skillsadd microsoft/azure-skills
      ;;
    embedded|backend|data)
      log_info "No additional skills for $domain — core skills + CLAUDE.md rules apply."
      ;;
  esac
}

print_summary() {
  local domain="$1"
  echo -e "\n${CYAN}======================================================${NC}"
  echo -e "${CYAN}  AI Sherpa Setup Complete${NC}"
  echo -e "${CYAN}======================================================${NC}"
  echo "  Domain:   $domain"
  echo "  Settings: $HOME/.claude/settings.json  (secrets protection active)"
  echo "  Settings: $PWD/.claude/settings.json   (project-level)"
  echo "  Rules:    CLAUDE.md installed in $PWD"
  echo ""
  echo "  Next steps:"
  echo "  1. Start Claude Code:   claude"
  echo "  2. Index your codebase: /graphify   (run inside Claude Code)"
  echo "  3. Start coding — AI Sherpa rules are active automatically"
  echo ""
  echo "  Update later: ./setup.sh --update"
  echo -e "${CYAN}======================================================${NC}\n"
}

# Source guard — prevents main() running when sourced by test script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run unit tests — verify all pass**

```bash
cd "E:/cjain/AI sherpa"
bash scripts/test-setup.sh
```

Expected output:
```
=== Test: check_command ===
  PASS: check_command true for bash
  PASS: check_command false for missing cmd
=== Test: write_settings ===
  PASS: global settings.json created
  PASS: global settings has Read .env rule
  PASS: global settings has Write .env rule
  PASS: settings.json.bak created on second run
=== Test: write_project_settings ===
  PASS: project .claude/settings.json created
  PASS: project settings has Read .env rule
=== Test: copy_claude_md (new project) ===
  PASS: CLAUDE.md created
  PASS: CLAUDE.md has web rules
=== Test: copy_claude_md (existing project — appends) ===
  PASS: original content preserved
  PASS: domain rules appended

Results: 12 passed, 0 failed
```

If any test fails: read the failure message, fix the function in setup.sh, re-run.

- [ ] **Step 5: Commit**

```bash
git add setup.sh scripts/test-setup.sh
git commit -m "feat: add setup.sh helper functions with unit tests"
```

---

## Task 2: setup.sh — Main Flow

**Files:**
- Modify: `setup.sh` (add `run_update()` and `main()` before the source guard)

- [ ] **Step 1: Add `run_update()` to setup.sh**

Insert this block between `print_summary()` and the source guard line:

```bash
run_update() {
  log_info "Updating AI Sherpa skills..."
  npx skillsadd obra/superpowers
  npx skillsadd safishamsi/graphify
  npx skillsadd mattpocock/skills
  npx skillsadd pbakaus/impeccable
  npx skillsadd sentry/dev
  write_settings
  log_info "Update complete. Your project CLAUDE.md was NOT modified."
}
```

- [ ] **Step 2: Add `main()` to setup.sh**

Insert this block immediately after `run_update()` and before the source guard:

```bash
main() {
  local UPDATE_MODE=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --update) UPDATE_MODE=true; shift ;;
      *) log_error "Unknown argument: $1  (valid: --update)"; exit 1 ;;
    esac
  done

  echo -e "${CYAN}"
  echo "  AI Sherpa — Company-wide Claude Code Setup"
  echo -e "${NC}"

  if [[ "$UPDATE_MODE" == true ]]; then
    run_update
    exit 0
  fi

  # Guard: warn if run from inside the ai-sherpa repo itself
  if [[ -f "$PWD/core/CLAUDE.md" && "$PWD" == "$SCRIPT_DIR" ]]; then
    log_warn "You are running setup from inside the AI Sherpa repo."
    log_warn "Please cd to your project directory first, then run:"
    log_warn "  bash $SCRIPT_DIR/setup.sh"
    exit 1
  fi

  # --- Prerequisites ---
  log_info "Checking prerequisites..."

  if ! check_command node; then
    log_info "Node.js not found. Installing via nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
    log_info "Node.js $(node --version) installed via nvm."
  else
    log_info "Node.js $(node --version) found."
  fi

  if ! check_command git; then
    log_error "Git not found. Install from https://git-scm.com/ then re-run this script."
    exit 1
  fi
  log_info "Git found."

  if ! check_command claude; then
    log_info "Claude Code not found. Installing..."
    npm install -g @anthropic-ai/claude-code
    log_info "Claude Code installed."
  else
    log_info "Claude Code found."
  fi

  # --- Domain selection ---
  echo ""
  echo "Which domain are you working in?"
  echo "  [1] Embedded Software (C/C++, firmware, RTOS)"
  echo "  [2] Web / Frontend (React, Vue, Angular, HTML/CSS)"
  echo "  [3] Backend (Node.js, Python)"
  echo "  [4] Data Science / ML"
  echo "  [5] DevOps / Platform"
  echo ""
  read -rp "Enter number [1-5]: " domain_choice

  local domain
  case "$domain_choice" in
    1) domain="embedded" ;;
    2) domain="web" ;;
    3) domain="backend" ;;
    4) domain="data" ;;
    5) domain="devops" ;;
    *) log_error "Invalid choice: $domain_choice. Run the script again."; exit 1 ;;
  esac

  # --- New or existing project ---
  echo ""
  echo "New project or existing project?"
  echo "  [1] New project"
  echo "  [2] Existing project (CLAUDE.md will be appended, not replaced)"
  echo ""
  read -rp "Enter number [1-2]: " project_choice

  local project_type
  case "$project_choice" in
    1) project_type="new" ;;
    2) project_type="existing" ;;
    *) log_error "Invalid choice: $project_choice. Run the script again."; exit 1 ;;
  esac

  # --- Install ---
  install_core_skills
  install_domain_skills "$domain"
  write_settings
  write_project_settings
  copy_claude_md "$domain" "$project_type"
  print_summary "$domain"
}
```

- [ ] **Step 3: Verify unit tests still pass**

```bash
cd "E:/cjain/AI sherpa"
bash scripts/test-setup.sh
```

Expected: 12 passed, 0 failed (adding main/run_update must not break existing tests)

- [ ] **Step 4: Syntax check**

```bash
bash -n setup.sh
```

Expected: no output (no syntax errors)

- [ ] **Step 5: Count lines**

```bash
wc -l setup.sh
```

Expected: under 300

- [ ] **Step 6: Commit**

```bash
git add setup.sh
git commit -m "feat: add setup.sh main flow — prerequisites, domain selection, skills, settings"
```

---

## Task 3: setup.ps1 — Windows PowerShell Script

**Files:**
- Create: `setup.ps1`

- [ ] **Step 1: Create `setup.ps1`**

```powershell
#Requires -Version 5.1
param(
    [switch]$Update
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Red }

function Test-CommandExists {
    param([string]$Name)
    return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Install-NodeJS {
    if (-not (Test-CommandExists "node")) {
        Write-Info "Node.js not found. Installing via winget..."
        winget install OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Info "Node.js installed. If 'node' is still not found, close and reopen this terminal."
    } else {
        Write-Info "Node.js $(node --version) found."
    }
}

function Install-Git {
    if (-not (Test-CommandExists "git")) {
        Write-Info "Git not found. Installing via winget..."
        winget install Git.Git --silent --accept-package-agreements --accept-source-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Info "Git installed."
    } else {
        Write-Info "Git $(git --version) found."
    }
}

function Install-ClaudeCode {
    if (-not (Test-CommandExists "claude")) {
        Write-Info "Claude Code not found. Installing..."
        npm install -g @anthropic-ai/claude-code
        Write-Info "Claude Code installed."
    } else {
        Write-Info "Claude Code found."
    }
}

function Install-CoreSkills {
    Write-Info "Installing core skills (this may take 1-2 minutes)..."
    npx skillsadd obra/superpowers
    npx skillsadd safishamsi/graphify
    npx skillsadd mattpocock/skills
    npx skillsadd pbakaus/impeccable
    npx skillsadd sentry/dev
    Write-Info "Core skills installed."
}

function Install-DomainSkills {
    param([string]$Domain)
    switch ($Domain) {
        "web" {
            Write-Info "Installing web/frontend skills..."
            npx skillsadd anthropics/skills
            npx skillsadd vercel-labs/agent-skills
            npx skillsadd vercel-labs/next-skills
            npx skillsadd vercel-labs/agent-browser
            npx skillsadd shadcn/ui
        }
        "devops" {
            Write-Info "Installing DevOps skills..."
            npx skillsadd microsoft/azure-skills
        }
        default {
            Write-Info "No additional skills for $Domain — core skills + CLAUDE.md rules apply."
        }
    }
}

function Write-GlobalSettings {
    $settingsDir  = "$env:USERPROFILE\.claude"
    $settingsFile = "$settingsDir\settings.json"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    if (Test-Path $settingsFile) {
        Copy-Item $settingsFile "$settingsFile.bak" -Force
        Write-Warn "Backed up existing global settings.json to settings.json.bak"
    }
    Copy-Item "$ScriptDir\settings\settings-template.json" $settingsFile -Force
    Write-Info "Secrets protection written to $settingsFile"
}

function Write-ProjectSettings {
    $projectSettingsDir  = "$(Get-Location)\.claude"
    $projectSettingsFile = "$projectSettingsDir\settings.json"
    if (-not (Test-Path $projectSettingsDir)) { New-Item -ItemType Directory -Path $projectSettingsDir -Force | Out-Null }
    if (Test-Path $projectSettingsFile) {
        Copy-Item $projectSettingsFile "$projectSettingsFile.bak" -Force
        Write-Warn "Backed up existing project settings.json"
    }
    Copy-Item "$ScriptDir\settings\settings-template.json" $projectSettingsFile -Force
    Write-Info "Project-level secrets protection written to $projectSettingsFile"
}

function Copy-ClaudeMd {
    param([string]$Domain, [string]$ProjectType)
    $source = "$ScriptDir\domains\$Domain\CLAUDE.md"
    $target = "$(Get-Location)\CLAUDE.md"
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending domain rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---"
        Add-Content $target "<!-- AI Sherpa domain rules — do not edit below this line -->"
        Get-Content $source | Add-Content $target
    } else {
        Copy-Item $source $target -Force
    }
    Write-Info "Domain CLAUDE.md installed at $target"
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa skills..."
    npx skillsadd obra/superpowers
    npx skillsadd safishamsi/graphify
    npx skillsadd mattpocock/skills
    npx skillsadd pbakaus/impeccable
    npx skillsadd sentry/dev
    Write-GlobalSettings
    Write-Info "Update complete. Your project CLAUDE.md was NOT modified."
}

function Print-Summary {
    param([string]$Domain)
    $here = Get-Location
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  AI Sherpa Setup Complete" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Domain:   $Domain"
    Write-Host "  Settings: $env:USERPROFILE\.claude\settings.json  (global, secrets protection active)"
    Write-Host "  Settings: $here\.claude\settings.json  (project-level)"
    Write-Host "  Rules:    CLAUDE.md installed in $here"
    Write-Host ""
    Write-Host "  Next steps:"
    Write-Host "  1. Start Claude Code:   claude"
    Write-Host "  2. Index your codebase: /graphify   (run inside Claude Code)"
    Write-Host "  3. Start coding -- AI Sherpa rules are active automatically"
    Write-Host ""
    Write-Host "  Update later: setup.bat --update"
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
}

# --- Main ---
Write-Host ""
Write-Host "  AI Sherpa -- Company-wide Claude Code Setup" -ForegroundColor Cyan
Write-Host ""

if ($Update) {
    Invoke-Update
    exit 0
}

# Guard: warn if run from inside the ai-sherpa repo itself
if ((Test-Path "$((Get-Location).Path)\core\CLAUDE.md") -and
    ("$(Get-Location)" -eq $ScriptDir)) {
    Write-Err "You are running setup from inside the AI Sherpa repo."
    Write-Err "Please cd to your project directory first, then run:"
    Write-Err "  setup.bat"
    exit 1
}

# Prerequisites
Write-Info "Checking prerequisites..."
Install-NodeJS
Install-Git
Install-ClaudeCode

# Domain selection
Write-Host ""
Write-Host "Which domain are you working in?"
Write-Host "  [1] Embedded Software (C/C++, firmware, RTOS)"
Write-Host "  [2] Web / Frontend (React, Vue, Angular, HTML/CSS)"
Write-Host "  [3] Backend (Node.js, Python)"
Write-Host "  [4] Data Science / ML"
Write-Host "  [5] DevOps / Platform"
Write-Host ""
$domainChoice = Read-Host "Enter number [1-5]"

$domainMap = @{ "1"="embedded"; "2"="web"; "3"="backend"; "4"="data"; "5"="devops" }
if (-not $domainMap.ContainsKey($domainChoice)) {
    Write-Err "Invalid choice: $domainChoice. Run setup.bat again."
    exit 1
}
$domain = $domainMap[$domainChoice]

# New or existing project
Write-Host ""
Write-Host "New project or existing project?"
Write-Host "  [1] New project"
Write-Host "  [2] Existing project (CLAUDE.md will be appended, not replaced)"
Write-Host ""
$projectChoice = Read-Host "Enter number [1-2]"

$ptMap = @{ "1"="new"; "2"="existing" }
if (-not $ptMap.ContainsKey($projectChoice)) {
    Write-Err "Invalid choice: $projectChoice. Run setup.bat again."
    exit 1
}
$projectType = $ptMap[$projectChoice]

# Install
Install-CoreSkills
Install-DomainSkills $domain
Write-GlobalSettings
Write-ProjectSettings
Copy-ClaudeMd $domain $projectType
Print-Summary $domain
```

- [ ] **Step 2: Syntax check setup.ps1**

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    "E:\cjain\AI sherpa\setup.ps1", [ref]$null, [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
} else {
    Write-Host "Syntax OK" -ForegroundColor Green
}
```

Expected: `Syntax OK`

If errors: fix each one, re-run the syntax check.

- [ ] **Step 3: Count lines**

```powershell
(Get-Content "E:\cjain\AI sherpa\setup.ps1").Count
```

Expected: under 300

- [ ] **Step 4: Commit**

```powershell
git add setup.ps1
git commit -m "feat: add setup.ps1 Windows PowerShell implementation"
```

---

## Task 4: setup.bat — Windows Thin Launcher

**Files:**
- Create: `setup.bat`

`setup.bat` does one thing: invoke setup.ps1 via PowerShell with the user's arguments passed through. All real logic is in setup.ps1.

- [ ] **Step 1: Create `setup.bat`**

```batch
@echo off
:: AI Sherpa — Windows setup launcher
:: Requires PowerShell 5.1+ (pre-installed on Windows 10/11)
:: Usage:
::   setup.bat              — first-time setup
::   setup.bat --update     — update skills and settings only

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo [AI Sherpa] Setup failed. See error above.
    exit /b %ERRORLEVEL%
)
```

- [ ] **Step 2: Test setup.bat passes arguments to setup.ps1**

Open Command Prompt in `E:\cjain\AI sherpa` and run:

```
setup.bat --bogus-flag
```

Expected: PowerShell launches and setup.ps1 prints an error about the unknown argument (not a crash, not a missing-script error). This confirms .bat → .ps1 argument passthrough works.

- [ ] **Step 3: Commit**

```
git add setup.bat
git commit -m "feat: add setup.bat Windows thin launcher"
```

---

## Task 5: Verification Pass

Run all checks before tagging Plan 2 complete.

- [ ] **Step 1: Run unit tests**

```bash
cd "E:/cjain/AI sherpa"
bash scripts/test-setup.sh
```

Expected: 12 passed, 0 failed

- [ ] **Step 2: Syntax check setup.sh**

```bash
bash -n setup.sh
```

Expected: no output

- [ ] **Step 3: Syntax check setup.ps1**

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    "E:\cjain\AI sherpa\setup.ps1", [ref]$null, [ref]$errors
)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red } }
else { Write-Host "Syntax OK" -ForegroundColor Green }
```

Expected: `Syntax OK`

- [ ] **Step 4: Line count check**

```bash
wc -l setup.sh
```

```powershell
(Get-Content "E:\cjain\AI sherpa\setup.ps1").Count
(Get-Content "E:\cjain\AI sherpa\setup.bat").Count
```

Expected limits:
- `setup.sh` → under 300
- `setup.ps1` → under 300
- `setup.bat` → under 15 (it's a thin launcher)

If either main script exceeds 300: trim verbose echo strings and comments without losing logic.

- [ ] **Step 5: Verify --update skips CLAUDE.md**

Grep to confirm `copy_claude_md` is NOT called from `run_update`:

```bash
grep -A 8 "run_update()" setup.sh | grep "copy_claude_md"
```

Expected: no output (copy_claude_md absent from run_update block)

```powershell
(Get-Content "E:\cjain\AI sherpa\setup.ps1" |
  Select-String "Invoke-Update" -Context 0,10).Context.PostContext |
  Select-String "Copy-ClaudeMd"
```

Expected: no output

- [ ] **Step 6: Verify both scripts write to correct settings paths**

```bash
grep -n "settings.json" setup.sh
```

Expected: lines showing `$HOME/.claude/settings.json` (global) and `$PWD/.claude/settings.json` (project)

```powershell
Select-String "settings.json" "E:\cjain\AI sherpa\setup.ps1" | Select-Object LineNumber, Line
```

Expected: lines showing `$env:USERPROFILE\.claude\settings.json` and `$(Get-Location)\.claude\settings.json`

- [ ] **Step 7: Verify the ai-sherpa-repo guard exists in both scripts**

```bash
grep -n "SCRIPT_DIR" setup.sh | grep -i "warn\|error\|guard\|core"
```

```powershell
Select-String "core.CLAUDE.md" "E:\cjain\AI sherpa\setup.ps1" | Select-Object LineNumber, Line
```

Expected: both scripts have the run-location guard.

- [ ] **Step 8: Final commit and tag**

```bash
git add .
git commit -m "chore: plan 2 verification pass — syntax, line counts, logic checks"
git tag v0.2.0
```

---

## Self-Review: Spec Coverage Check

| Requirement (from §) | Covered by Task |
|---|---|
| setup.sh check/install Node.js (§5.1, §5.2 step 1) | Task 2 — nvm install path |
| setup.sh check/install Git (§5.1, §5.2 step 1) | Task 2 — error if not found |
| setup.sh install Claude Code CLI (§5.1, §5.2 step 1) | Task 2 |
| Windows: winget for Node.js + Git (§5.1) | Task 3 (setup.ps1) |
| Domain prompt (§5.2 step 2) | Tasks 2 + 3 |
| New/existing project prompt (§5.2 step 3) | Tasks 2 + 3 |
| Install core skills (§5.2 step 4, §6.1) | Tasks 1 + 2 |
| Install domain skills (§5.2 step 5, §6.2) | Tasks 1 + 2 |
| Write global settings.json (§5.2 step 6, §7.1A) | Tasks 1 + 2 |
| Write project-level settings.json (§5.2 step 7) | Tasks 1 + 2 |
| graphify instructions printed (§5.2 step 8) | Tasks 2 + 3 (print_summary) |
| Copy domain CLAUDE.md (§5.2 step 9) | Tasks 1 + 2 |
| Print quick-start summary (§5.2 step 10) | Tasks 2 + 3 |
| Error handling — fail fast (§5.2 step 11) | `set -euo pipefail` / `$ErrorActionPreference = "Stop"` |
| --update flag (§5.3) | Tasks 2 + 3 |
| --update does NOT overwrite CLAUDE.md (§5.3) | Verified in Task 5 step 5 |
| setup.sh < 300 lines (§5.6) | Verified in Task 5 step 4 |
| setup.ps1 < 300 lines (§5.6) | Verified in Task 5 step 4 |
| Approved skills only (§6A) | install_core_skills and install_domain_skills only use approved list |

**Not covered in Plan 2 (deferred):**
- `--version v1.2` tag pinning (§5.3) → complex, deferred to v1.1
- `--update` diff-before-apply (§5.3 "shows diff") → deferred to v1.1
- GitHub Actions workflow for graphify re-indexing (§8) → Plan 3
- User documentation (§10) → Plan 3
