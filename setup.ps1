#Requires -Version 5.1
param(
    [switch]$Update
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Red }

$script:SkippedSteps = @()
function Add-SkippedStep {
    param([string]$Name, [string]$Reason, [string]$ManualInstall)
    $script:SkippedSteps += [pscustomobject]@{ Name = $Name; Reason = $Reason; ManualInstall = $ManualInstall }
}

$script:InstallFailures = @()
function Add-InstallFailure {
    param([string]$Key)
    $script:InstallFailures += $Key
}
function Show-SkippedStepsReport {
    if ($script:SkippedSteps.Count -eq 0) { return }
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host "  OPTIONAL STEPS SKIPPED ($($script:SkippedSteps.Count))" -ForegroundColor Yellow
    Write-Host "  Setup continued, but these features are unavailable:" -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Yellow
    foreach ($s in $script:SkippedSteps) {
        Write-Host ""
        Write-Host "  > $($s.Name)" -ForegroundColor Yellow
        Write-Host "    Reason: $($s.Reason)"
        Write-Host "    Install manually: $($s.ManualInstall)"
    }
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host ""
}

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
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$($Entry.name) install failed - see error above."
            Add-InstallFailure "$($Entry.name)@$($Entry.marketplace)"
        }
    } elseif ($Entry.github) {
        try { & claude plugin marketplace add "https://github.com/$($Entry.github)" 2>&1 | Out-Null } catch {}
        $global:LASTEXITCODE = 0
        claude plugin install $Entry.name --scope user
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$($Entry.name) install failed - see error above."
            Add-InstallFailure "$($Entry.name)"
        }
    }
}

function Register-Marketplaces {
    param([string]$Domain = "")
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    catch { return }

    # Collect marketplace names actually referenced by global + selected domain plugins
    $needed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $config.global) {
        if ($p.marketplace) { $needed.Add($p.marketplace) | Out-Null }
    }
    if ($Domain -and $config.domains.$Domain) {
        foreach ($p in $config.domains.$Domain) {
            if ($p.marketplace) { $needed.Add($p.marketplace) | Out-Null }
        }
    }

    $marketplaces = $config.marketplaces
    if (-not $marketplaces -or @($marketplaces).Count -eq 0) { return }
    foreach ($entry in @($marketplaces)) {
        $repo = if ($entry -is [string]) { $entry } else { $entry.repo }
        $name = if ($entry -is [string]) { $null } else { $entry.name }
        if (-not $repo) { continue }
        if (-not $needed.Contains($name)) { continue }
        Write-Info "Registering marketplace: $repo"
        try { & claude plugin marketplace add $repo 2>&1 | Out-Null } catch {}
        $global:LASTEXITCODE = 0
        if ($name) {
            try { & claude plugin marketplace update $name 2>&1 | Out-Null } catch {}
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Could not update marketplace $name - domain plugins may fail."
                $global:LASTEXITCODE = 0
            }
        }
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

function Install-Skills {
    param([string]$Domain)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { return }
    if (-not $config.skills) { return }

    $entries = @()
    if ($config.skills.global)            { $entries += @($config.skills.global) }
    if ($Domain -and $config.skills.$Domain) { $entries += @($config.skills.$Domain) }
    if ($entries.Count -eq 0) { return }

    if (-not (Test-CommandExists "git")) {
        Write-Warn "git not on PATH - cannot install raw skills (plugins.json 'skills' section)."
        return
    }

    $skillsDir = "$env:USERPROFILE\.claude\skills"
    if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }

    foreach ($entry in $entries) {
        $repo    = $entry.repo
        $subpath = if ($entry.subpath) { $entry.subpath } else { "skills" }
        if (-not $repo) { continue }
        $repoSlug = ($repo -replace '/', '-')
        $tmp = Join-Path $env:TEMP "ai-sherpa-skill-$repoSlug"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Write-Info "Cloning skills from $repo..."
        git clone --depth 1 --quiet "https://github.com/$repo" $tmp | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to clone $repo - skipping its skills."
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            Add-InstallFailure "skills:$repo"
            continue
        }
        $src = Join-Path $tmp $subpath
        if (-not (Test-Path $src)) {
            Write-Warn "Subpath '$subpath' not found in $repo - skipping."
            Remove-Item $tmp -Recurse -Force
            Add-InstallFailure "skills:$repo (missing subpath: $subpath)"
            continue
        }
        Copy-Item "$src\*" $skillsDir -Recurse -Force
        Remove-Item $tmp -Recurse -Force
        Write-Info "Installed skills from $repo into $skillsDir"
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
        Write-Err "Is '$Domain' a valid domain? Valid: embedded, web, data, devops, marketing, sales, finance, service, procurement"
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

function Resolve-PipCommand {
    if (Test-CommandExists "pip3") { return "pip3" }
    if (Test-CommandExists "pip")  { return "pip"  }
    return $null
}

function Install-Python {
    Write-Info "Python pip not found. Installing Python 3.12 via winget..."
    winget install Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget failed to install Python (exit $LASTEXITCODE)."
        Add-SkippedStep -Name "code-review-graph (auto-mode code review indexing)" `
                        -Reason "Python install failed (winget exit $LASTEXITCODE)" `
                        -ManualInstall "Download Python 3 from https://python.org, then re-run setup.bat"
        return $false
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Info "Python installed."
    return $true
}

function Install-PyPiTool {
    param([string]$Name, [string]$Package, [string]$PostInstall)
    $pipCmd = Resolve-PipCommand
    if (-not $pipCmd) {
        if (-not (Install-Python)) { return }
        $pipCmd = Resolve-PipCommand
        if (-not $pipCmd) {
            Write-Warn "Python installed but pip is not yet on PATH."
            Add-SkippedStep -Name "$Name (PyPI tool)" `
                            -Reason "Python installed but pip not yet on PATH in this shell" `
                            -ManualInstall "Close and reopen the terminal, then re-run setup.bat"
            return
        }
    }
    Write-Info "Installing $Name (pip)..."
    & $pipCmd install --quiet $Package
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$Name pip install failed (exit $LASTEXITCODE)."
        Add-SkippedStep -Name "$Name (PyPI tool)" `
                        -Reason "pip install $Package failed (exit $LASTEXITCODE)" `
                        -ManualInstall "$pipCmd install $Package$(if ($PostInstall) { '; ' + $PostInstall })"
        return
    }
    if ($PostInstall) {
        Invoke-Expression $PostInstall
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$Name post-install command failed."
            Add-SkippedStep -Name "$Name (PyPI tool)" `
                            -Reason "Post-install command failed: $PostInstall" `
                            -ManualInstall $PostInstall
            return
        }
    }
    Write-Info "$Name ready."
}

function Install-Rust {
    if (Test-CommandExists "cargo") { return $true }
    Write-Info "Rust toolchain not found. Installing via winget (Rustlang.Rustup)..."
    winget install Rustlang.Rustup --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget failed to install Rust (exit $LASTEXITCODE)."
        return $false
    }
    # Refresh PATH so cargo is visible without a terminal restart
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User") + ";" +
                "$env:USERPROFILE\.cargo\bin"
    if (Test-CommandExists "cargo") {
        Write-Info "Rust installed. cargo $(cargo --version)."
        return $true
    }
    Write-Warn "Rust installed but cargo still not on PATH. Close and reopen your terminal, then re-run setup.bat."
    return $false
}

function Install-CargoTool {
    param([string]$Name, [string]$Git, [string]$Package)
    if (-not (Test-CommandExists "cargo")) {
        if (-not (Install-Rust)) {
            Add-SkippedStep -Name "$Name (Rust / cargo tool)" `
                            -Reason "Rust toolchain not installed" `
                            -ManualInstall "Install Rust from https://rustup.rs, then: cargo install$(if ($Git) { ' --git ' + $Git } else { ' ' + $Package })"
            return
        }
    }
    Write-Info "Installing $Name (cargo)..."
    if ($Git) {
        & cargo install --git $Git
    } else {
        & cargo install $Package
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$Name cargo install failed (exit $LASTEXITCODE)."
        Add-SkippedStep -Name "$Name (Rust / cargo tool)" `
                        -Reason "cargo install failed" `
                        -ManualInstall "cargo install$(if ($Git) { ' --git ' + $Git } else { ' ' + $Package })"
        return
    }
    Write-Info "$Name ready."
}

function Install-GitCloneTool {
    param([string]$Name, [string]$Repo, [string]$Destination, [string]$PostInstall)
    if (-not (Test-CommandExists "git")) {
        Write-Warn "git not on PATH - cannot install $Name."
        Add-SkippedStep -Name "$Name (git-clone tool)" -Reason "git not installed" `
                        -ManualInstall "Install git, then re-run setup."
        return
    }
    $dest = $Destination -replace '^~', $env:USERPROFILE
    $parent = Split-Path -Parent $dest
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path $dest) {
        Write-Info "$Name already at $dest - pulling latest..."
        Push-Location $dest
        & git pull --quiet
        Pop-Location
    } else {
        Write-Info "Cloning $Name from $Repo to $dest..."
        & git clone --quiet "https://github.com/$Repo" $dest
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$Name git clone failed."
            Add-SkippedStep -Name "$Name (git-clone tool)" -Reason "git clone https://github.com/$Repo failed" `
                            -ManualInstall "git clone https://github.com/$Repo $dest"
            return
        }
    }
    if ($PostInstall) {
        Push-Location $dest
        Invoke-Expression $PostInstall
        Pop-Location
    }
    Write-Info "$Name ready at $dest."
}

function Install-Tools {
    param([string]$Domain)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { return }
    if (-not $config.tools) { return }

    $entries = @()
    if ($config.tools.global)            { $entries += @($config.tools.global) }
    if ($Domain -and $config.tools.$Domain) { $entries += @($config.tools.$Domain) }
    if ($entries.Count -eq 0) { return }

    foreach ($t in $entries) {
        switch ($t.source) {
            'pypi'      { Install-PyPiTool      -Name $t.name -Package $t.package -PostInstall $t.postInstall }
            'cargo'     { Install-CargoTool     -Name $t.name -Git $t.git -Package $t.package }
            'git-clone' { Install-GitCloneTool  -Name $t.name -Repo $t.repo -Destination $t.destination -PostInstall $t.postInstall }
            default     { Write-Warn "Unknown tool source '$($t.source)' for $($t.name); skipping." }
        }
    }
}

function Test-Installation {
    param([string]$Domain)
    # Primary signal: failures captured from claude plugin install exit codes
    if ($script:InstallFailures.Count -gt 0) {
        return ,@($script:InstallFailures)
    }
    # Optional cross-check: if installed_plugins.json exists at the standard
    # path, verify expected entries are present. If missing (e.g. WSL+Windows
    # hybrid where claude reads /mnt/c/.../.claude/), trust install exit codes.
    $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
    if (-not (Test-Path $installedFile)) {
        return ,@()
    }
    try {
        $installed = Get-Content $installedFile -Raw | ConvertFrom-Json
    } catch {
        return ,@()
    }
    $expected = @()
    $globals = Read-PluginConfig -Section "global"
    if ($globals) { $expected += @($globals) }
    $domainPlugins = Read-PluginConfig -Section $Domain
    if ($domainPlugins) { $expected += @($domainPlugins) }

    $missing = @()
    foreach ($entry in $expected) {
        if (-not $entry.marketplace) { continue }
        $key = "$($entry.name)@$($entry.marketplace)"
        if (-not $installed.plugins.PSObject.Properties[$key]) {
            $missing += $key
        }
    }
    return ,$missing
}

function Show-VerificationReport {
    param([string[]]$Missing)
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Red
    Write-Host "  SETUP INCOMPLETE" -ForegroundColor Red
    Write-Host "  $($Missing.Count) plugin(s) did not register in" -ForegroundColor Red
    Write-Host "  ~/.claude/plugins/installed_plugins.json:" -ForegroundColor Red
    Write-Host "======================================================" -ForegroundColor Red
    foreach ($m in $Missing) { Write-Host "  [FAIL] $m" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Fix: re-run setup, or install manually:" -ForegroundColor Yellow
    Write-Host "    claude plugin install <name>@<marketplace> --scope user" -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Red
    Write-Host ""
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa core skills..."
    Register-Marketplaces
    $plugins = Read-PluginConfig -Section "global"
    foreach ($entry in $plugins) {
        claude plugin update $entry.name
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($entry.name) update may have failed - re-run --update to retry." }
    }
    Install-Skills
    Write-GlobalSettings
    Install-Tools
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
    Write-Host "  2. Code-review graph runs in auto-mode via SessionStart hook (no manual step)."
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
    "1"="embedded"; "2"="web"; "3"="data"; "4"="devops";
    "5"="marketing"; "6"="sales"; "7"="finance"; "8"="service"; "9"="procurement";
    "10"="ai"; "11"="frontend"
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
Write-Host "  [2] Web (full-stack: frontend + backend + UI/UX)"
Write-Host "  [3] Data Science / ML"
Write-Host "  [4] DevOps / Platform"
Write-Host "  --- Business ---"
Write-Host "  [5] Marketing"
Write-Host "  [6] Sales"
Write-Host "  [7] Finance / Accounting"
Write-Host "  [8] Customer Service / Support"
Write-Host "  [9] Procurement / Operations"
Write-Host "  --- AI & UI/UX ---"
Write-Host "  [10] AI / ML Agents (RAG, evals, prompt engineering)"
Write-Host "  [11] Frontend + UI/UX"
Write-Host ""
$domainChoice = Read-Host "Enter number [1-11]"
if (-not $domainMap.ContainsKey($domainChoice)) {
    Write-Err "Invalid choice: $domainChoice. Run setup.bat again."
    exit 1
}
$domain = $domainMap[$domainChoice]

# Register extra marketplaces + install skills (both paths)
Register-Marketplaces -Domain $domain
Install-CoreSkills
Install-DomainSkills $domain
Install-Skills -Domain $domain
Write-GlobalSettings

# Embedded-specific: probe for toolchains, flashers, debuggers and record them
# so Claude can issue concrete build/flash/debug commands instead of generic prose.
if ($domain -eq "embedded") {
    $detectScript = "$ScriptDir\scripts\detect-embedded-toolchain.ps1"
    if (Test-Path $detectScript) {
        Write-Info "Detecting embedded toolchain and flashing tools..."
        & $detectScript -TargetHome $env:USERPROFILE
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Toolchain detection script exited non-zero. embedded-toolchain.json may be incomplete."
        }
    } else {
        Write-Warn "Toolchain detection script not found at $detectScript"
    }
}

if ($isUserLevelRun) {
    # User-level: write CLAUDE.md to ~/.claude/ — active for all projects
    Write-GlobalClaudeMd $domain
    Install-Tools -Domain $domain
    $missing = Test-Installation $domain
    if ($missing.Count -gt 0) {
        Show-VerificationReport $missing
        Show-SkippedStepsReport
        Print-Summary $domain -UserLevel
        exit 1
    }
    Write-Info "All expected plugins verified in installed_plugins.json."
    Show-SkippedStepsReport
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
    Install-Tools -Domain $domain
    $missing = Test-Installation $domain
    if ($missing.Count -gt 0) {
        Show-VerificationReport $missing
        Show-SkippedStepsReport
        Print-Summary $domain
        exit 1
    }
    Write-Info "All expected plugins verified in installed_plugins.json."
    Show-SkippedStepsReport
    Print-Summary $domain
}
