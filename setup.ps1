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

function Read-PluginConfig {
    param([string]$Section)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) {
        Write-Err "plugins.json not found at $configFile"
        exit 1
    }
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Failed to parse plugins.json: $_"
        exit 1
    }
    if ($Section -eq "global") {
        return $config.global
    }
    if ($config.domains.PSObject.Properties[$Section]) {
        return $config.domains.$Section
    }
    return @()
}

function Install-Plugin {
    param($Entry)
    if ($Entry.marketplace) {
        claude plugin install "$($Entry.name)@$($Entry.marketplace)" --scope user
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($Entry.name) install may have failed - re-run setup to retry." }
    } elseif ($Entry.github) {
        claude plugin marketplace add "https://github.com/$($Entry.github)" --scope user 2>$null
        claude plugin install $Entry.name --scope user
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($Entry.name) install may have failed - re-run setup to retry." }
    }
}

function Register-Marketplaces {
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    catch { return }
    $marketplaces = $config.marketplaces
    if (-not $marketplaces -or @($marketplaces).Count -eq 0) { return }
    foreach ($marketplace in @($marketplaces)) {
        Write-Info "Registering marketplace: $marketplace"
        claude plugin marketplace add $marketplace --scope user 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Warn "Could not register $marketplace - domain plugins may fail." }
    }
}

function Install-CoreSkills {
    Write-Info "Installing core skills (this may take 1-2 minutes)..."
    $plugins = Read-PluginConfig -Section "global"
    if (-not $plugins -or @($plugins).Count -eq 0) {
        Write-Warn "No global plugins defined in plugins.json"
        return
    }
    foreach ($entry in $plugins) { Install-Plugin $entry }
    Write-Info "Core skills installed."
}

function Install-DomainSkills {
    param([string]$Domain)
    $plugins = Read-PluginConfig -Section $Domain
    if (-not $plugins -or @($plugins).Count -eq 0) {
        Write-Info "No additional skills for $Domain - core skills + CLAUDE.md rules apply."
        return
    }
    Write-Info "Installing $Domain skills..."
    foreach ($entry in $plugins) { Install-Plugin $entry }
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

function Write-GlobalClaudeMd {
    param([string]$Domain)
    $source = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $source)) {
        Write-Err "Domain CLAUDE.md not found at: $source"
        exit 1
    }
    $claudeDir  = "$env:USERPROFILE\.claude"
    $target     = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    Copy-Item $source $target -Force
    Write-Info "Domain rules written to $target (active for all projects)"
}

function Install-Graphify {
    $pipCmd = $null
    if (Test-CommandExists "pip3") { $pipCmd = "pip3" }
    elseif (Test-CommandExists "pip") { $pipCmd = "pip" }
    if (-not $pipCmd) {
        Write-Warn "Python pip not found - Graphify skipped. Install Python 3 and re-run setup to enable /graphify."
        return
    }
    Write-Info "Installing Graphify knowledge graph skill..."
    & $pipCmd install --quiet graphifyy
    if ($LASTEXITCODE -ne 0) { Write-Warn "graphifyy install failed - re-run setup after verifying pip."; return }
    graphify install
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "graphify install failed - /graphify command may not be available."
    } else {
        Write-Info "Graphify ready. Run /graphify inside Claude Code to index your codebase."
    }
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa core skills..."
    Register-Marketplaces
    $plugins = Read-PluginConfig -Section "global"
    foreach ($entry in $plugins) {
        claude plugin update $entry.name
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($entry.name) update may have failed - re-run --update to retry." }
    }
    Write-GlobalSettings
    Install-Graphify
    Write-Info "Core skills and settings updated. Project CLAUDE.md was NOT modified."
}

function Print-Summary {
    param([string]$Domain, [switch]$UserLevel)
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  AI Sherpa Setup Complete" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Domain:   $Domain"
    Write-Host "  Settings: $env:USERPROFILE\.claude\settings.json"
    if ($UserLevel) {
        Write-Host "  Rules:    $env:USERPROFILE\.claude\CLAUDE.md  (all projects)"
    } else {
        $here = Get-Location
        Write-Host "  Settings: $here\.claude\settings.json  (project)"
        Write-Host "  Rules:    $here\CLAUDE.md  (this project)"
    }
    Write-Host ""
    Write-Host "  Next steps:"
    Write-Host "  1. Start Claude Code:   claude"
    Write-Host "  2. Index your codebase: /graphify   (run inside Claude Code)"
    Write-Host "  3. Start coding -- AI Sherpa rules are active automatically"
    Write-Host ""
    Write-Host "  Update later: `"$ScriptDir\setup.bat`" --update"
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

# Detect whether this is a user-level (double-click) or project-level run
$currentPath = (Get-Location).Path
$isUserLevelRun = ((Test-Path "$currentPath\core\CLAUDE.md") -and ($currentPath -eq $ScriptDir))

$domainMap = @{
    "1"="embedded"; "2"="web"; "3"="backend"; "4"="data"; "5"="devops";
    "6"="marketing"; "7"="sales"; "8"="finance"; "9"="service"; "10"="procurement";
    "11"="uiux"
}

# Prerequisites (both paths)
Write-Info "Checking prerequisites..."
Install-NodeJS
Install-Git
Install-ClaudeCode

# Domain selection (both paths)
Write-Host ""
Write-Host "Which domain are you working in?"
Write-Host "  --- Engineering ---"
Write-Host "  [1] Embedded Software (C/C++, firmware, RTOS)"
Write-Host "  [2] Web / Frontend (React, Vue, Angular, HTML/CSS)"
Write-Host "  [3] Backend (Node.js, Python)"
Write-Host "  [4] Data Science / ML"
Write-Host "  [5] DevOps / Platform"
Write-Host "  --- Business ---"
Write-Host "  [6] Marketing"
Write-Host "  [7] Sales"
Write-Host "  [8] Finance / Accounting"
Write-Host "  [9] Customer Service / Support"
Write-Host "  [10] Procurement / Operations"
Write-Host "  [11] UI/UX Design"
Write-Host ""
$domainChoice = Read-Host "Enter number [1-11]"
if (-not $domainMap.ContainsKey($domainChoice)) {
    Write-Err "Invalid choice: $domainChoice. Run setup.bat again."
    exit 1
}
$domain = $domainMap[$domainChoice]

# Register extra marketplaces + install skills (both paths)
Register-Marketplaces
Install-CoreSkills
Install-DomainSkills $domain
Write-GlobalSettings

if ($isUserLevelRun) {
    # User-level: write CLAUDE.md to ~/.claude/ — active for all projects
    Write-GlobalClaudeMd $domain
    Install-Graphify
    Print-Summary $domain -UserLevel
} else {
    # Project-level: write CLAUDE.md and settings into current project directory
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
    Write-ProjectSettings
    Copy-ClaudeMd $domain $projectType
    Install-Graphify
    Print-Summary $domain
}
