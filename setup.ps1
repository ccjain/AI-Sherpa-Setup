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
        if ($LASTEXITCODE -ne 0) { Write-Err "winget failed to install Node.js (exit $LASTEXITCODE). Install manually from https://nodejs.org then re-run."; exit 1 }
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
        if ($LASTEXITCODE -ne 0) { Write-Err "winget failed to install Git (exit $LASTEXITCODE). Install manually from https://git-scm.com then re-run."; exit 1 }
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
        if ($LASTEXITCODE -ne 0) { Write-Err "npm failed to install Claude Code (exit $LASTEXITCODE). Check your Node.js installation."; exit 1 }
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
    if ($LASTEXITCODE -ne 0) { Write-Warn "One or more core skill installs may have failed. Check output above and re-run if needed." }
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
            if ($LASTEXITCODE -ne 0) { Write-Warn "One or more domain skill installs may have failed. Check output above and re-run if needed." }
        }
        "devops" {
            Write-Info "Installing DevOps skills..."
            npx skillsadd microsoft/azure-skills
            if ($LASTEXITCODE -ne 0) { Write-Warn "DevOps skill install may have failed. Check output above and re-run if needed." }
        }
        default {
            Write-Info "No additional skills for $Domain - core skills + CLAUDE.md rules apply."
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
    if (-not (Test-Path $source)) {
        Write-Err "Domain CLAUDE.md not found at: $source"
        Write-Err "Is '$Domain' a valid domain? Valid: embedded, web, backend, data, devops"
        exit 1
    }
    $target = "$(Get-Location)\CLAUDE.md"
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending domain rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---"
        Add-Content $target "<!-- AI Sherpa domain rules - do not edit below this line -->"
        Get-Content $source | Add-Content $target
    } else {
        Copy-Item $source $target -Force
    }
    Write-Info "Domain CLAUDE.md installed at $target"
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa core skills..."
    npx skillsadd obra/superpowers
    npx skillsadd safishamsi/graphify
    npx skillsadd mattpocock/skills
    npx skillsadd pbakaus/impeccable
    npx skillsadd sentry/dev
    if ($LASTEXITCODE -ne 0) { Write-Warn "One or more core skill installs may have failed. Check output above and re-run if needed." }
    Write-GlobalSettings
    Write-Info "Core skills and settings updated. Project CLAUDE.md was NOT modified."
}

function Print-Summary {
    param([string]$Domain)
    $here = Get-Location
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  AI Sherpa Setup Complete" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Domain:   $Domain"
    Write-Host "  Settings: $env:USERPROFILE\.claude\settings.json  (global)"
    Write-Host "  Settings: $here\.claude\settings.json  (project-level)"
    Write-Host "  Rules:    CLAUDE.md installed in $here"
    Write-Host ""
    Write-Host "  Next steps:"
    Write-Host "  1. Start Claude Code:   claude"
    Write-Host "  2. Index your codebase: /graphify   (run inside Claude Code)"
    Write-Host "  3. Start coding -- AI Sherpa rules are active automatically"
    Write-Host ""
    Write-Host "  Update later: powershell -File `"$ScriptDir\setup.ps1`" -Update"
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

# Guard: if launched from inside the AI Sherpa repo (e.g. double-click), show folder picker
$currentPath = (Get-Location).Path
if ((Test-Path "$currentPath\core\CLAUDE.md") -and ($currentPath -eq $ScriptDir)) {
    Write-Warn "Select your project folder in the dialog that opens..."
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the project folder to configure AI Sherpa in"
    $dialog.ShowNewFolderButton = $true
    $dialogResult = $dialog.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        Write-Err "No folder selected. Run setup.bat again and select a project folder."
        exit 1
    }
    Set-Location $dialog.SelectedPath
    Write-Info "Project folder: $($dialog.SelectedPath)"
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
    Write-Err "Invalid choice: $domainChoice. Run setup.bat (or setup.ps1) again."
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
    Write-Err "Invalid choice: $projectChoice. Run setup.bat (or setup.ps1) again."
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
