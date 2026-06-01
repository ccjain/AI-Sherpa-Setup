#Requires -Version 5.1
param(
    [switch]$Update,
    [switch]$Uninstall
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = "Stop"

# Force UTF-8 console I/O for the whole script. PS 5.1 + conhost default to the
# legacy OEM/ANSI codepage and turn box-drawing chars like █ (UTF-8 E2 96 88)
# into mojibake (â–ˆ). Belt-and-suspenders: setup.bat also runs `chcp 65001`,
# and the .ps1 file itself is saved with a UTF-8 BOM so PS 5.1 parses the
# string literals correctly at load time.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Write-Info   { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Green }
function Write-Warn   { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Yellow }
function Write-Err    { param([string]$msg) Write-Host "[AI Sherpa] $msg" -ForegroundColor Red }
# Visually-distinct level for "the user must do X themselves before this tool
# works." Plain Write-Warn is too easy to scroll past during a noisy install;
# user-action lines get magenta + an explicit prefix, AND get collected into
# Show-UserActionsReport so they're surfaced again at the end of the run.
function Write-Action { param([string]$msg) Write-Host "[ACTION REQUIRED] $msg" -ForegroundColor Magenta }

function Show-Logo {
    # PowerShell 5.1 console may default to a code page that mangles UTF-8 box-
    # drawing chars. Force UTF-8 output just for this banner.
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        Write-Host ""
        Write-Host "                                                                      /\"           -ForegroundColor Cyan
        Write-Host "   █████╗ ██╗    ███████╗██╗  ██╗███████╗██████╗ ██████╗  █████╗     /  \"           -ForegroundColor Cyan
        Write-Host "  ██╔══██╗██║    ██╔════╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗   / /\ \"          -ForegroundColor Cyan
        Write-Host "  ███████║██║    ███████╗███████║█████╗  ██████╔╝██████╔╝███████║  /_/  \_\"         -ForegroundColor Cyan
        Write-Host "  ██╔══██║██║    ╚════██║██╔══██║██╔══╝  ██╔══██╗██╔═══╝ ██╔══██║"                    -ForegroundColor Cyan
        Write-Host "  ██║  ██║██║    ███████║██║  ██║███████╗██║  ██║██║     ██║  ██║"                    -ForegroundColor Cyan
        Write-Host "  ╚═╝  ╚═╝╚═╝    ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝"                    -ForegroundColor Cyan
        Write-Host ""
        Write-Host "            Guiding your team's Claude Code expedition." -ForegroundColor DarkGray
        Write-Host ""
    } finally {
        [Console]::OutputEncoding = $prev
    }
}

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

# Things the user MUST do themselves before the tool works (close terminal,
# install a prereq, enable a Windows feature, run a manual command). These get
# surfaced TWICE: inline via Write-Action when discovered, and again in a
# prominent end-of-run report (Show-UserActionsReport) so a noisy install can't
# bury them.
$script:UserActions = @()
function Add-UserAction {
    param([string]$Title, [string]$Why, [string]$Command)
    $script:UserActions += [pscustomobject]@{ Title = $Title; Why = $Why; Command = $Command }
}
function Show-UserActionsReport {
    if ($script:UserActions.Count -eq 0) { return }
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Magenta
    Write-Host "  ACTION REQUIRED ($($script:UserActions.Count))" -ForegroundColor Magenta
    Write-Host "  Setup is done, but these need YOU before the tool works:" -ForegroundColor Magenta
    Write-Host "==========================================================" -ForegroundColor Magenta
    $i = 1
    foreach ($a in $script:UserActions) {
        Write-Host ""
        Write-Host "  $i. $($a.Title)" -ForegroundColor Magenta
        if ($a.Why)     { Write-Host "     Why: $($a.Why)" }
        if ($a.Command) { Write-Host "     Run: $($a.Command)" -ForegroundColor White }
        $i++
    }
    Write-Host ""
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

# Minimum versions required by AI Sherpa. Bumping these here is the single
# source of truth — Install-NodeJS / Install-Git / Install-ClaudeCode all
# read from this table and enforce it.
#   node   18.0.0  -> Claude Code requirement (per Anthropic docs)
#   git    2.30.0  -> safe modern baseline; covers `git clone --depth`, partial-clone, etc.
#   claude 2.0.0   -> introduces the plugin system + `--scope` flag used by Install-Plugin
$script:MinVersions = @{
    node   = [version]'18.0.0'
    git    = [version]'2.30.0'
    claude = [version]'2.0.0'
}

function Get-VersionFromString {
    param([string]$Text)
    if (-not $Text) { return $null }
    if ($Text -match '(\d+)\.(\d+)\.(\d+)') {
        return [version]("{0}.{1}.{2}" -f $matches[1], $matches[2], $matches[3])
    }
    return $null
}

function Get-ToolVersion {
    param([string]$Cmd, [string]$Arg = '--version')
    if (-not (Test-CommandExists $Cmd)) { return $null }
    try {
        $out = & $Cmd $Arg 2>&1 | Out-String
        return (Get-VersionFromString $out)
    } catch { return $null }
}

function Update-PathFromRegistry {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
}

# Returns $true if the named marketplace is already registered in
# ~/.claude/plugins/known_marketplaces.json. Used by Register-Marketplaces to
# log [NEW] vs [REFRESH] honestly and skip the redundant `marketplace add`
# call on re-runs (it's a no-op for already-known marketplaces).
function Test-MarketplaceRegistered {
    param([string]$Name)
    if (-not $Name) { return $false }
    $f = "$env:USERPROFILE\.claude\plugins\known_marketplaces.json"
    if (-not (Test-Path $f)) { return $false }
    try {
        $j = Get-Content $f -Raw | ConvertFrom-Json
        return ($null -ne $j.PSObject.Properties[$Name])
    } catch { return $false }
}

# Returns the installed version string for a "<name>@<marketplace>" plugin key,
# or $null if not installed. Used by Install-Plugin to decide install-vs-update.
# Reads claude's own installed_plugins.json — same source of truth that
# Test-Installation uses.
function Test-PluginInstalled {
    param([string]$Key)
    $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
    if (-not (Test-Path $installedFile)) { return $null }
    try {
        $installed = Get-Content $installedFile -Raw | ConvertFrom-Json
    } catch { return $null }
    if (-not $installed.plugins) { return $null }
    if (-not $installed.plugins.PSObject.Properties[$Key]) { return $null }
    $entries = $installed.plugins.$Key
    if (-not $entries) { return $null }
    # Prefer the user-scope entry's version (that's what setup.bat installs at).
    $userEntry = $entries | Where-Object { $_.scope -eq 'user' } | Select-Object -First 1
    if ($userEntry) { return $userEntry.version }
    return $entries[0].version
}

function Install-Winget {
    # Bootstrap winget when it's missing. Install-NodeJS / Install-Git /
    # Install-Python / Install-Rust all shell out to `winget install`; on older
    # Win10 builds, debloated images, and some Server SKUs winget isn't there
    # and those calls fail with a misleading "winget failed to install X" because
    # cmd-not-found surfaces as a non-zero $LASTEXITCODE downstream.
    #
    # Cascade:
    #   1. Microsoft.WinGet.Client PowerShell module -> Repair-WinGetPackageManager
    #      (Microsoft's official path; pulls VCLibs + UI.Xaml deps automatically).
    #   2. Direct App Installer msixbundle from aka.ms/getwinget -> Add-AppxPackage.
    #   3. Surface as Add-UserAction with Microsoft Store + manual-download hints.
    if (Test-CommandExists 'winget') {
        $wingetVersion = ''
        try { $wingetVersion = (winget --version 2>$null | Out-String).Trim() } catch {}
        if ($wingetVersion) { Write-Info "winget $wingetVersion found." }
        else                { Write-Info "winget found." }
        return
    }

    Write-Info "winget not found. Attempting auto-install..."

    # Path 1: Microsoft.WinGet.Client module + Repair-WinGetPackageManager.
    try {
        # PowerShell 5.1 defaults to TLS 1.0/1.1; PSGallery rejects both.
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
            -Force -Scope CurrentUser -ErrorAction Stop | Out-Null

        $gallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }

        Write-Info "  Trying Microsoft.WinGet.Client / Repair-WinGetPackageManager..."
        Install-Module -Name Microsoft.WinGet.Client -Force -Scope CurrentUser `
            -AllowClobber -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        Repair-WinGetPackageManager -ErrorAction Stop
        Update-PathFromRegistry
        if (Test-CommandExists 'winget') {
            Write-Info "winget installed via Microsoft.WinGet.Client."
            return
        }
    } catch {
        Write-Warn "  Microsoft.WinGet.Client path failed: $($_.Exception.Message)"
    }

    # Path 2: App Installer msixbundle direct download.
    try {
        Write-Info "  Falling back to direct App Installer msixbundle..."
        $bundlePath = Join-Path $env:TEMP 'Microsoft.DesktopAppInstaller.msixbundle'
        Invoke-WebRequest -Uri 'https://aka.ms/getwinget' `
            -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $bundlePath -ErrorAction Stop
        Remove-Item $bundlePath -ErrorAction SilentlyContinue
        Update-PathFromRegistry
        if (Test-CommandExists 'winget') {
            Write-Info "winget installed via msixbundle."
            return
        }
    } catch {
        Write-Warn "  msixbundle install failed: $($_.Exception.Message)"
    }

    # Path 3: both auto-paths failed — surface as user action and exit.
    Write-Action "winget could not be installed automatically."
    Add-UserAction -Title "Install winget (App Installer) manually" `
                   -Why "AI Sherpa uses winget to install Node.js, Git, Python, and Rust. Both auto-install paths failed on this machine — usually a corporate proxy blocking PSGallery / GitHub, missing Appx dependencies (VCLibs, UI.Xaml), or an unsupported Windows SKU." `
                   -Command "Open Microsoft Store, install 'App Installer', then re-run setup.bat. Or download from https://aka.ms/getwinget and install manually."
    Show-UserActionsReport
    exit 1
}

function Install-NodeJS {
    $min = $script:MinVersions.node
    $current = Get-ToolVersion 'node'
    if (-not $current) {
        Write-Info "Node.js not found. Installing via winget (minimum required: $min)..."
        winget install OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Err "winget failed to install Node.js (exit $LASTEXITCODE)."
            Write-Err "Minimum required: Node.js $min. Install manually from https://nodejs.org and re-run."
            exit 1
        }
        Update-PathFromRegistry
        $current = Get-ToolVersion 'node'
        if (-not $current) {
            Write-Action "Node.js installed but 'node' isn't on PATH in this shell."
            Add-UserAction -Title "Make Node.js visible to this shell" `
                           -Why "winget installed Node, but this PowerShell session's PATH was captured before that — `node` won't resolve until you start a fresh shell. Minimum required: Node.js $min." `
                           -Command "Close this terminal, open a new one, then re-run: setup.bat"
            Show-UserActionsReport
            exit 1
        }
    }
    if ($current -lt $min) {
        Write-Warn "Node.js $current is below minimum $min. Attempting winget upgrade..."
        winget upgrade OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
        # Tolerate non-zero exit: "no upgrade available" / "package not installed by winget"
        # are both reported as failures but aren't fatal — re-check the version instead.
        $global:LASTEXITCODE = 0
        Update-PathFromRegistry
        $current = Get-ToolVersion 'node'
        if (-not $current -or $current -lt $min) {
            Write-Err "Node.js is $current (below minimum $min) and auto-upgrade did not bump it."
            Write-Err "Upgrade manually from https://nodejs.org/en/download and re-run setup."
            exit 1
        }
    }
    Write-Info "Node.js $current OK (>= $min)."
}

function Install-Git {
    $min = $script:MinVersions.git
    $current = Get-ToolVersion 'git'
    if (-not $current) {
        Write-Info "Git not found. Installing via winget (minimum required: $min)..."
        winget install Git.Git --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Err "winget failed to install Git (exit $LASTEXITCODE)."
            Write-Err "Minimum required: Git $min. Install manually from https://git-scm.com and re-run."
            exit 1
        }
        Update-PathFromRegistry
        $current = Get-ToolVersion 'git'
        if (-not $current) {
            Write-Action "Git installed but 'git' isn't on PATH in this shell."
            Add-UserAction -Title "Make Git visible to this shell" `
                           -Why "winget installed Git, but this PowerShell session's PATH was captured before that — `git` won't resolve until you start a fresh shell. Minimum required: Git $min." `
                           -Command "Close this terminal, open a new one, then re-run: setup.bat"
            Show-UserActionsReport
            exit 1
        }
    }
    if ($current -lt $min) {
        Write-Warn "Git $current is below minimum $min. Attempting winget upgrade..."
        winget upgrade Git.Git --silent --accept-package-agreements --accept-source-agreements
        $global:LASTEXITCODE = 0
        Update-PathFromRegistry
        $current = Get-ToolVersion 'git'
        if (-not $current -or $current -lt $min) {
            Write-Err "Git is $current (below minimum $min) and auto-upgrade did not bump it."
            Write-Err "Upgrade manually from https://git-scm.com/downloads and re-run setup."
            exit 1
        }
    }
    Write-Info "Git $current OK (>= $min)."
}

function Install-ClaudeCode {
    $min = $script:MinVersions.claude
    $current = Get-ToolVersion 'claude'
    if (-not $current) {
        Write-Info "Claude Code not found. Installing latest (minimum required: $min)..."
        npm install -g @anthropic-ai/claude-code@latest
        if ($LASTEXITCODE -ne 0) {
            Write-Err "npm failed to install Claude Code (exit $LASTEXITCODE)."
            Write-Err "Minimum required: Claude Code $min. Install manually: npm install -g @anthropic-ai/claude-code@latest"
            exit 1
        }
    } else {
        # Always try to bump to latest so newly-added CLI flags (e.g. `claude plugin install --scope`)
        # are available. npm install -g is idempotent and a no-op if already at latest.
        Write-Info "Claude Code $current found. Upgrading to latest..."
        npm install -g @anthropic-ai/claude-code@latest
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to upgrade Claude Code (exit $LASTEXITCODE). Will validate current version against minimum."
            $global:LASTEXITCODE = 0
        }
    }
    $current = Get-ToolVersion 'claude'
    if (-not $current -or $current -lt $min) {
        Write-Err "Claude Code is $current (below minimum $min)."
        Write-Err "Upgrade manually and re-run: npm install -g @anthropic-ai/claude-code@latest"
        exit 1
    }
    Write-Info "Claude Code $current OK (>= $min)."
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

# Check installed_plugins.json to see if a plugin is currently enabled.
# Returns $true if an entry exists for the spec AND it is not explicitly
# disabled. We read state instead of blindly calling `claude plugin enable`
# because that command errors with "Plugin is already enabled" when the
# plugin is already on — and PS 5.1's native command stderr handling
# displays that error as a scary stack-trace even when our code handles it
# gracefully. The pre-check eliminates the wasted call entirely.
function Test-PluginEnabled {
    param([string]$Spec)
    $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
    if (-not (Test-Path $installedFile)) { return $false }
    try {
        $j = Get-Content $installedFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j.plugins) { return $false }
        $entry = $j.plugins.$Spec
        if (-not $entry) { return $false }
        # Schema across CLI versions varies. Check explicit markers first;
        # fall back to "entry exists -> enabled" since `claude plugin install`
        # enables by default and `claude plugin disable` writes a marker.
        if ($null -ne $entry.enabled)  { return [bool]$entry.enabled }
        if ($null -ne $entry.disabled) { return -not [bool]$entry.disabled }
        if ($null -ne $entry.status)   { return ($entry.status -eq 'enabled') }
        return $true
    } catch { return $false }
}

# Ensure a plugin is enabled after install / update. The common case is
# that it already is (`claude plugin install` enables by default; `claude
# plugin update` doesn't change enable state). Pre-check via
# Test-PluginEnabled so we don't waste a CLI call that would error with
# "already enabled" and trigger PS 5.1's NativeCommandError display.
#
# When the pre-check says the plugin is NOT enabled (rare: user previously
# ran `claude plugin disable`, or installed_plugins.json is missing/stale)
# we still call enable, with stderr captured to a temp file and three
# outcomes distinguished:
#  1. exit 0           -> freshly activated. Log [ENABLE] ... activated.
#  2. exit non-0 with  -> state mismatch (we thought disabled, CLI says
#     "already enabled"   enabled). Treat as no-op success.
#  3. any other exit   -> real failure. Surface as ACTION REQUIRED.
function Enable-Plugin {
    param([string]$Spec)
    if (Test-PluginEnabled -Spec $Spec) {
        Write-Info "  [ENABLE] $Spec already active"
        return
    }
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $null = & claude plugin enable $Spec 2>$tmpErr
        $rc = $LASTEXITCODE
        $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $tmpErr -ErrorAction SilentlyContinue
    }
    $global:LASTEXITCODE = 0

    if ($rc -eq 0) {
        Write-Info "  [ENABLE] $Spec activated"
    } elseif ($stderr -and $stderr -match 'already enabled') {
        Write-Info "  [ENABLE] $Spec already active"
    } else {
        $stderrSummary = if ($stderr) { ($stderr -replace '\s+', ' ').Trim() } else { '(no stderr)' }
        Write-Action "$Spec installed but 'claude plugin enable' returned exit $rc - the plugin may load disabled."
        Add-UserAction -Title "Activate plugin $Spec" `
                       -Why "Setup installed the plugin but the explicit 'claude plugin enable' call exited non-zero and the output didn't match the benign 'already enabled' case. stderr: $stderrSummary" `
                       -Command "claude plugin enable $Spec"
    }
}

function Install-Plugin {
    param($Entry)
    if ($Entry.marketplace) {
        $key = "$($Entry.name)@$($Entry.marketplace)"
        $existingVersion = Test-PluginInstalled $key
        if ($existingVersion) {
            # Already installed -> take the update path so user sees actual
            # version movement ("already at latest" vs "Updated X -> Y"),
            # instead of `claude plugin install` silently re-touching the entry.
            Write-Info "  [UPDATE] $key (currently v$existingVersion)"
            claude plugin update $key --scope user
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "  $key update returned exit $LASTEXITCODE (continuing)."
                $global:LASTEXITCODE = 0
            }
            Enable-Plugin $key
        } else {
            Write-Info "  [NEW]    $key installing..."
            claude plugin install $key --scope user
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "  $($Entry.name) install failed - see error above."
                Add-InstallFailure $key
            } else {
                Enable-Plugin $key
            }
        }
    } elseif ($Entry.github) {
        # github source: marketplace name isn't known up-front (claude derives it
        # from the repo), so look up by "<name>@*" prefix in installed_plugins.json.
        $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
        $alreadyInstalled = $false
        if (Test-Path $installedFile) {
            try {
                $j = Get-Content $installedFile -Raw | ConvertFrom-Json
                if ($j.plugins) {
                    $alreadyInstalled = @($j.plugins.PSObject.Properties.Name | Where-Object { $_ -like "$($Entry.name)@*" }).Count -gt 0
                }
            } catch {}
        }
        if ($alreadyInstalled) {
            Write-Info "  [UPDATE] $($Entry.name) (github: $($Entry.github))"
            claude plugin update $Entry.name --scope user
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "  $($Entry.name) update returned exit $LASTEXITCODE (continuing)."
                $global:LASTEXITCODE = 0
            }
            Enable-Plugin $Entry.name
        } else {
            Write-Info "  [NEW]    $($Entry.name) installing from github: $($Entry.github)..."
            try { & claude plugin marketplace add "https://github.com/$($Entry.github)" 2>&1 | Out-Null } catch {}
            $global:LASTEXITCODE = 0
            claude plugin install $Entry.name --scope user
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "  $($Entry.name) install failed - see error above."
                Add-InstallFailure "$($Entry.name)"
            } else {
                Enable-Plugin $Entry.name
            }
        }
    }
}

# Run `claude plugin marketplace update <name>` with proper stderr capture
# (no `2>&1` NativeCommandError trap on PS 5.1) and pattern-match common
# failure modes so the user gets a clear diagnosis instead of a generic
# "Could not update marketplace" warning.
#
# Most-common cause on fresh Windows installs: Claude Code isn't logged in
# yet, so marketplace operations that hit Anthropic's catalog endpoint fail
# with an auth error. We catch that case and surface a precise ACTION
# REQUIRED telling the user to run `claude` interactively to complete OAuth.
function Invoke-MarketplaceUpdate {
    param(
        [string]$Name,
        [string]$FailContext = 'plugins may fail'  # used in "$Name $FailContext" warning text
    )
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $null = & claude plugin marketplace update $Name 2>$tmpErr
        $rc = $LASTEXITCODE
        $stderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
    } finally {
        Remove-Item $tmpErr -ErrorAction SilentlyContinue
    }
    $global:LASTEXITCODE = 0
    if ($rc -eq 0) { return $true }

    $stderrSummary = if ($stderr) { ($stderr -replace '\s+', ' ').Trim() } else { '(no stderr captured)' }
    # Match auth-failure patterns liberally — CLI versions vary the exact wording.
    if ($stderrSummary -match '(?i)not (logged in|authenticated|authoriz)|please (login|log in|sign in)|authentication required|unauthorized|\b401\b') {
        Write-Action "marketplace $Name update failed - Claude Code is not logged in yet."
        Add-UserAction -Title "Log in to Claude Code, then re-run setup" `
                       -Why "Marketplace catalog updates hit Anthropic's API and require auth. On a fresh Claude Code install the OAuth flow hasn't run yet, so the marketplace cache can't be populated - until that's done, $Name $FailContext. stderr: $stderrSummary" `
                       -Command "claude   # press Enter, complete the browser OAuth, exit, then re-run setup.bat"
    } else {
        Write-Warn "  Could not update marketplace $Name - $Name $FailContext."
        Write-Warn "  stderr: $stderrSummary"
    }
    return $false
}

function Register-Marketplaces {
    # Register every marketplace referenced by global + ALL domains. The old
    # signature took a single $Domain because setup picked one at install
    # time; per-session-domain-selection moved that choice out of install
    # and into the conversation, so install-time must cover every domain.
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    catch { return }

    # Collect marketplace names referenced by global + every domain.
    $needed = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $config.global) {
        if ($p.marketplace) { $needed.Add($p.marketplace) | Out-Null }
    }
    if ($config.domains) {
        foreach ($domName in $config.domains.PSObject.Properties.Name) {
            foreach ($p in $config.domains.$domName) {
                if ($p.marketplace) { $needed.Add($p.marketplace) | Out-Null }
            }
        }
    }

    # Build a name -> repo map of marketplaces explicitly declared in
    # plugins.json. Every marketplace referenced by global/domain plugins
    # MUST be declared here; Claude CLI requires explicit `marketplace add
    # <repo>` before any plugin from that marketplace can install. The old
    # code assumed unmatched names were "builtin marketplaces shipped with
    # claude" — that's wrong; Claude Code doesn't ship builtin marketplaces.
    # An unmatched name surfaces as ACTION REQUIRED below.
    $declared = @{}
    if ($config.marketplaces) {
        foreach ($entry in @($config.marketplaces)) {
            $repo = if ($entry -is [string]) { $entry } else { $entry.repo }
            $name = if ($entry -is [string]) { $null } else { $entry.name }
            if ($repo -and $name) { $declared[$name] = $repo }
        }
    }

    foreach ($name in $needed) {
        if (-not $name) { continue }
        if (-not $declared.ContainsKey($name)) {
            Write-Action "marketplace '$name' is referenced by plugins.json but not declared in marketplaces[]."
            Add-UserAction -Title "Declare marketplace '$name' in plugins.json" `
                           -Why "Plugins in plugins.json reference marketplace '$name' but the marketplaces[] array doesn't list it. Claude CLI requires every marketplace to be registered via 'claude plugin marketplace add <repo>' before any plugin from it can install. Setup can't `add` what it doesn't know the repo for, so plugins from '$name' will fail to install with 'Marketplace not found' until this is declared." `
                           -Command "Edit plugins.json and add a row like { ""repo"": ""<owner>/<repo>"", ""name"": ""$name"" } to the marketplaces[] array. Then re-run setup."
            continue
        }
        $repo = $declared[$name]
        # Skip the redundant `marketplace add` on re-runs (it's a no-op for
        # already-known marketplaces). Always refresh the cache via update,
        # otherwise `claude plugin update` later sees stale catalog data.
        if (Test-MarketplaceRegistered $name) {
            Write-Info "  [REFRESH] marketplace $name (already registered, refreshing cache)"
        } else {
            Write-Info "  [NEW]     marketplace $name ($repo)"
            try { & claude plugin marketplace add $repo 2>&1 | Out-Null } catch {}
            $global:LASTEXITCODE = 0
        }
        [void](Invoke-MarketplaceUpdate -Name $name -FailContext 'plugin versions may be stale')
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
    # Per-session-domain-selection: install globals + every per-domain skills
    # section in one pass. The old $Domain parameter is gone — setup installs
    # all of them. (Skill repos can be large to clone; doing this once avoids
    # the N-times-redundant clone the per-domain loop would otherwise cause.)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { return }
    if (-not $config.skills) { return }

    $entries = @()
    if ($config.skills.global) { $entries += @($config.skills.global) }
    foreach ($k in $config.skills.PSObject.Properties.Name) {
        if ($k -eq 'global') { continue }
        if ($config.skills.$k) { $entries += @($config.skills.$k) }
    }
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

function Copy-CoreOnlyClaudeMd-ToProject {
    param([string]$ProjectType)
    # Per-session domain selection moves the domain layer out of CLAUDE.md and
    # into the SessionStart hook (which loads rules from the per-project
    # selection file). The project-level CLAUDE.md now contains ONLY core
    # rules; domain rules are injected at session start.
    $core = "$ScriptDir\core\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    $target = "$(Get-Location)\CLAUDE.md"
    $coreContent = (Get-Content $core -Raw -Encoding UTF8)
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending AI Sherpa core rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---" -Encoding UTF8
        Add-Content $target "<!-- AI Sherpa core rules - do not edit below this line -->" -Encoding UTF8
        Add-Content $target $coreContent -Encoding UTF8
    } else {
        Set-Content -Path $target -Value $coreContent -Encoding UTF8
    }
    Write-Info "Wrote core CLAUDE.md to $target (domain rules load per-session via SessionStart hook)."
}

function Write-AiSherpaState {
    # New schema (per docs/superpowers/specs/2026-06-01-per-session-domain-selection-design.md
    # Section 2). The legacy top-level `domain` field is gone; per-project
    # selection lives in <project>/.claude/ai-sherpa-domains.json instead.
    param([string]$HookPath = "")
    $stateDir  = "$env:USERPROFILE\.claude\ai-sherpa"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $stateFile = "$stateDir\state.json"

    # Collect marketplaces actually referenced by global + every domain.
    $configFile = "$ScriptDir\plugins.json"
    $marketplaces = @()
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            $set = New-Object System.Collections.Generic.HashSet[string]
            foreach ($p in $cfg.global) { if ($p.marketplace) { $set.Add($p.marketplace) | Out-Null } }
            if ($cfg.domains) {
                foreach ($d in $cfg.domains.PSObject.Properties.Name) {
                    foreach ($p in $cfg.domains.$d) {
                        if ($p.marketplace) { $set.Add($p.marketplace) | Out-Null }
                    }
                }
            }
            $marketplaces = @($set)
        } catch {}
    }

    $state = [ordered]@{
        version            = 1
        installed_at       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        ai_sherpa_version  = (Get-AiSherpaSpecVersion)
        domains_installed  = @(Get-DomainNames)
        plugin_marketplaces = $marketplaces
        hook_path          = $HookPath
    }
    ($state | ConvertTo-Json -Depth 5) | Set-Content -Path $stateFile -Encoding UTF8
    Write-Info "Wrote install manifest to $stateFile"
}

function Write-CoreOnlyClaudeMd {
    # User-level: write ONLY core/CLAUDE.md to ~/.claude/CLAUDE.md. Domain
    # rules are loaded per-session by the SessionStart hook; no domain merge
    # at install time.
    $core = "$ScriptDir\core\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    $claudeDir = "$env:USERPROFILE\.claude"
    $target    = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    # -Encoding UTF8 on Get-Content is REQUIRED on PowerShell 5.1: the default
    # codepage is system ANSI (Windows-1252 in en-US), which mangles UTF-8 chars
    # like em-dashes (— -> â€") at read time. Write-side -Encoding UTF8 alone
    # is not enough because the corruption happens before the write.
    $coreContent = (Get-Content $core -Raw -Encoding UTF8)
    Set-Content -Path $target -Value $coreContent -Encoding UTF8
    Write-Info "Wrote core CLAUDE.md to $target (domain rules load per-session via SessionStart hook)."
}

function Resolve-PipCommand {
    if (Test-CommandExists "pip3") { return "pip3" }
    if (Test-CommandExists "pip")  { return "pip"  }
    return $null
}

# Windows ships with a legacy 260-char MAX_PATH limit that breaks modern dev
# tooling. uv unpacks wheels into deeply-nested cache dirs (e.g.
# %USERPROFILE%\AppData\Local\uv\cache\...\jsonschema\referencing\...) which
# routinely blow past 260 chars and fail with ERROR_OPEN_FAILED (-2147024786).
# Enabling LongPathsEnabled is a one-time machine-wide registry flip that makes
# Win32 path APIs accept paths up to ~32k chars. We try to set it ourselves
# when running elevated; if not, we tell the user the exact elevated command
# rather than silently letting their next install fail.
function Test-WindowsLongPathsEnabled {
    try {
        $val = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
                                     -Name 'LongPathsEnabled' -ErrorAction Stop
        return ($val -eq 1)
    } catch { return $false }
}

function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Enable-WindowsLongPaths {
    if (Test-WindowsLongPathsEnabled) {
        Write-Info "Windows long-path support already enabled."
        return
    }
    if (Test-IsAdmin) {
        try {
            New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
                             -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force | Out-Null
            Write-Info "Enabled Windows long-path support (LongPathsEnabled = 1)."
        } catch {
            Write-Action "Could not enable Windows long-path support automatically: $($_.Exception.Message)"
            Add-UserAction -Title "Enable Windows long-path support" `
                           -Why "Without this, uv / pip can fail mid-install with 'cannot open file' on deeply-nested wheels (jsonschema, email_validator, etc)." `
                           -Command "Open an ADMIN PowerShell and run: New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force"
        }
        return
    }
    # Not elevated — surface as an explicit action.
    Write-Action "Windows long-path support is NOT enabled, and this shell isn't elevated so setup can't flip it."
    Write-Action "uv / pip installs may fail later with 'cannot open file' (ERROR_OPEN_FAILED) on deeply-nested wheels."
    Add-UserAction -Title "Enable Windows long-path support" `
                   -Why "Without this, uv / pip can fail mid-install with 'cannot open file' on deeply-nested wheels (jsonschema, email_validator, etc). The setup will still try alternate installers, but enabling this once fixes the root cause." `
                   -Command "Open an ADMIN PowerShell and run: New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force"
}

function Add-WindowsUserPath {
    param([string]$Dir)
    if (-not $Dir) { return }
    if (-not (Test-Path $Dir)) { return }
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $pathParts = if ($userPath) { $userPath -split ';' } else { @() }
    if ($pathParts -contains $Dir) { return }
    Write-Info "Adding '$Dir' to Windows User PATH..."
    $userPath = ($userPath -replace ';+$','') + ';' + $Dir
    [Environment]::SetEnvironmentVariable('PATH', $userPath, 'User')
    $env:Path = $env:Path + ';' + $Dir
}

# Locate a working Python interpreter to invoke for sysconfig queries. Windows
# Python distributions (python.org installer, winget) ship 'python.exe' but
# typically NOT 'python3.exe' — assuming the latter exists silently produces
# empty output and breaks user-Scripts dir discovery. The Windows 'py' launcher
# is a separate third candidate.
function Resolve-PythonInterpreter {
    foreach ($cand in @('python3', 'python', 'py')) {
        if (Test-CommandExists $cand) { return $cand }
    }
    return $null
}

# Surface every plausible location where pip --user might have dropped the
# console-script .exe into the current process's PATH. We try the canonical
# sysconfig query first; if that interpreter doesn't ship sysconfig results we
# trust, we also glob %APPDATA%\Python\Python*\Scripts as a belt-and-suspenders
# backstop. Idempotent — Add-WindowsUserPath skips dirs already on PATH.
function Add-PythonUserScriptsToPath {
    $pyExe = Resolve-PythonInterpreter
    if ($pyExe) {
        $pyArgs = if ($pyExe -eq 'py') {
            @('-3', '-c', "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))")
        } else {
            @('-c', "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))")
        }
        try {
            $userScripts = & $pyExe @pyArgs 2>$null
            if ($userScripts) { Add-WindowsUserPath $userScripts.Trim() }
        } catch {}
    }
    if (Test-Path "$env:APPDATA\Python") {
        Get-ChildItem "$env:APPDATA\Python" -Directory -Filter "Python*" -ErrorAction SilentlyContinue | ForEach-Object {
            $scriptsDir = Join-Path $_.FullName "Scripts"
            if (Test-Path $scriptsDir) { Add-WindowsUserPath $scriptsDir }
        }
    }
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
    param([string]$Name, [string]$Package, [string]$PostInstall, [switch]$Upgrade)

    # Fast-path: skip if the tool's binary is already on PATH AND we're not in
    # explicit update mode. Avoids the noisy install/upgrade churn (and the
    # `uv tool upgrade` "not installed" error when the tool came from a
    # different installer originally) on every setup re-run. `setup.bat
    # --update` flips $Upgrade and bypasses this skip.
    if (-not $Upgrade -and (Test-CommandExists $Name)) {
        $loc = try { (Get-Command $Name -ErrorAction SilentlyContinue).Source } catch { $null }
        $locSuffix = if ($loc) { " at $loc" } else { '' }
        Write-Info "  [SKIP]   $Name already installed$locSuffix (run setup.bat --update to upgrade)"
        return
    }

    # Build the ordered list of installers to attempt. uv tool first (isolated,
    # fast), pipx second (isolated, mature), pip --user last (shares the user's
    # global Python env so dep conflicts are possible — warned about below).
    # The cascade lets us recover when an earlier installer fails mid-install
    # (e.g. uv hitting Windows ERROR_OPEN_FAILED on a deeply-nested wheel).
    $attempts = @()
    if (Test-CommandExists "uv")   { $attempts += 'uv'   }
    if (Test-CommandExists "pipx") { $attempts += 'pipx' }

    $pipCmd = Resolve-PipCommand
    if (-not $pipCmd -and $attempts.Count -eq 0) {
        if (-not (Install-Python)) { return }
        $pipCmd = Resolve-PipCommand
        if (-not $pipCmd) {
            Write-Warn "Python installed but pip is not yet on PATH."
            Add-SkippedStep -Name "$Name (PyPI tool)" `
                            -Reason "Python installed but no pip/pipx/uv on PATH in this shell" `
                            -ManualInstall "Close and reopen the terminal, then re-run setup.bat"
            return
        }
    }
    if ($pipCmd) { $attempts += 'pip-user' }

    if ($attempts.Count -eq 0) {
        Add-SkippedStep -Name "$Name (PyPI tool)" `
                        -Reason "No PyPI installer available (uv / pipx / pip all missing)" `
                        -ManualInstall "Install 'uv' from https://docs.astral.sh/uv/, then re-run setup.bat"
        return
    }

    $reasons = @()
    for ($i = 0; $i -lt $attempts.Count; $i++) {
        $installer = $attempts[$i]
        $ok = $false
        switch ($installer) {
            'uv' {
                # `uv tool install` is idempotent: installs fresh, no-ops if
                # already at latest, upgrades when a newer version exists. We
                # use it unconditionally instead of `uv tool upgrade` because
                # the latter errors with "not installed" when the tool was
                # previously installed via a different installer (pip-user,
                # pipx) and only the binary — not uv's tool registry — knows
                # about it.
                Write-Info "Installing $Name (uv tool install)..."
                & uv tool install $Package
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) { Add-WindowsUserPath "$env:USERPROFILE\.local\bin" }
            }
            'pipx' {
                Write-Info "Installing $Name (pipx$(if ($Upgrade) { ' upgrade' } else { ' install' }))..."
                if ($Upgrade) { & pipx upgrade $Package } else { & pipx install $Package }
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) { Add-WindowsUserPath "$env:USERPROFILE\.local\bin" }
            }
            'pip-user' {
                Write-Warn "$Name will install into the global Python env ($pipCmd --user). For isolation, install 'uv' (https://docs.astral.sh/uv/) or 'pipx' and re-run."
                Write-Info "Installing $Name (pip --user$(if ($Upgrade) { ' --upgrade' }))..."
                $pipArgs = @('install', '--quiet', '--user')
                if ($Upgrade) { $pipArgs += '--upgrade' }
                $pipArgs += $Package
                & $pipCmd @pipArgs
                $ok = ($LASTEXITCODE -eq 0)
                if ($ok) { Add-PythonUserScriptsToPath }
            }
        }

        if ($ok) {
            if ($PostInstall) {
                # Before invoking the post-install command, verify its leading
                # token (the binary the package just installed) is resolvable
                # on PATH. On Windows the user-Scripts dir may not have made
                # it into $env:Path despite our best efforts (multiple Python
                # installs, non-standard sysconfig schemes, sandboxed shells).
                # In that case, defer the post-install with a clear remediation
                # instead of crashing with CommandNotFoundException.
                $postFirstWord = ($PostInstall.Trim() -split '\s+', 2)[0]
                $postFindable = -not [string]::IsNullOrEmpty($postFirstWord) `
                                -and ($null -ne (Get-Command $postFirstWord -ErrorAction SilentlyContinue))
                if (-not $postFindable) {
                    Write-Action "$Name installed but '$postFirstWord' isn't on PATH in this shell yet — deferring post-install."
                    Add-UserAction -Title "Finish $Name setup" `
                                   -Why "$Name was installed via $installer but the binary's directory wasn't on PATH in this shell — the post-install step couldn't run. After a fresh shell opens with the updated PATH, this one command finishes wiring it up." `
                                   -Command "Close and reopen the terminal, then run: $PostInstall"
                    Write-Info "$Name installed (post-install deferred — see ACTION REQUIRED at end of setup)."
                    return
                }
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
            return
        }

        $reasons += "$installer (exit $LASTEXITCODE)"
        $global:LASTEXITCODE = 0
        if ($i -lt $attempts.Count - 1) {
            Write-Warn "$Name $installer install failed - retrying with next installer ($($attempts[$i + 1]))..."
        }
    }

    Add-SkippedStep -Name "$Name (PyPI tool)" `
                    -Reason "All installers failed: $($reasons -join ', ')" `
                    -ManualInstall "Try one of: uv tool install $Package  /  pipx install $Package  /  $pipCmd install --user $Package$(if ($PostInstall) { '; ' + $PostInstall })"
}

function Test-RustInstalled {
    if (Test-CommandExists "cargo") { return $true }
    # cargo may exist on disk but the current shell's PATH hasn't picked it up
    # yet — common right after a fresh rustup install, or in any shell opened
    # before rustup ran. Reinstalling in that state triggers rustup-init's
    # "existing settings.toml" warning and a redundant winget round-trip.
    # Surface ~/.cargo/bin to this process and treat Rust as installed.
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    $cargoExe = Join-Path $cargoBin 'cargo.exe'
    if (Test-Path $cargoExe) {
        Write-Info "Found cargo at $cargoExe; adding $cargoBin to PATH for this run."
        $env:Path = $env:Path + ';' + $cargoBin
        return $true
    }
    return $false
}

function Install-Rust {
    if (Test-RustInstalled) {
        # cargo is present but may be from an outdated toolchain. Several crates
        # we install (rtk uses str.floor_char_boundary, stabilized in Rust 1.80)
        # fail to compile on old stable channels with "unstable library feature"
        # errors. If rustup is available, refresh the stable channel.
        if (Test-CommandExists "rustup") {
            Write-Info "Updating Rust toolchain (rustup update stable)..."
            try { & rustup update stable 2>&1 | Out-Null } catch {}
            $global:LASTEXITCODE = 0
        } else {
            Write-Warn "cargo found but rustup not on PATH; cannot auto-update Rust. If a cargo install later fails with 'unstable library feature', install rustup from https://rustup.rs and re-run."
        }
        return $true
    }
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
    param([string]$Name, [string]$Git, [string]$Package, [switch]$Upgrade)

    # Fast-path: skip if already on PATH and not explicitly updating.
    # `cargo install` without --force is itself a no-op when the tool is at
    # the latest version, but it still pulls metadata from crates.io — the
    # skip avoids even that.
    if (-not $Upgrade -and (Test-CommandExists $Name)) {
        $loc = try { (Get-Command $Name -ErrorAction SilentlyContinue).Source } catch { $null }
        $locSuffix = if ($loc) { " at $loc" } else { '' }
        Write-Info "  [SKIP]   $Name already installed$locSuffix (run setup.bat --update to upgrade)"
        return
    }

    if (-not (Test-CommandExists "cargo")) {
        if (-not (Install-Rust)) {
            Add-SkippedStep -Name "$Name (Rust / cargo tool)" `
                            -Reason "Rust toolchain not installed" `
                            -ManualInstall "Install Rust from https://rustup.rs, then: cargo install$(if ($Git) { ' --git ' + $Git } else { ' ' + $Package })"
            return
        }
    }
    Write-Info "Installing $Name (cargo$(if ($Upgrade) { ' --force' }))..."
    $cargoArgs = @('install')
    if ($Upgrade) { $cargoArgs += '--force' }
    if ($Git) { $cargoArgs += @('--git', $Git) } else { $cargoArgs += $Package }
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "$Name cargo install failed (exit $LASTEXITCODE)."
        Add-SkippedStep -Name "$Name (Rust / cargo tool)" `
                        -Reason "cargo install failed" `
                        -ManualInstall "cargo install$(if ($Upgrade) { ' --force' })$(if ($Git) { ' --git ' + $Git } else { ' ' + $Package })"
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
    # Per-session domain selection installs every domain, so this function
    # installs globals + every per-domain tools section in one pass. (Today
    # only `tools.global` exists in plugins.json; the per-domain loop is
    # future-proofing for when a domain wants its own CLI tools.)
    param([switch]$Upgrade)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { return }
    if (-not $config.tools) { return }

    $entries = @()
    if ($config.tools.global) { $entries += @($config.tools.global) }
    foreach ($d in $config.tools.PSObject.Properties.Name) {
        if ($d -eq 'global') { continue }
        if ($config.tools.$d) { $entries += @($config.tools.$d) }
    }
    if ($entries.Count -eq 0) { return }

    foreach ($t in $entries) {
        switch ($t.source) {
            'pypi'      { Install-PyPiTool      -Name $t.name -Package $t.package -PostInstall $t.postInstall -Upgrade:$Upgrade }
            'cargo'     { Install-CargoTool     -Name $t.name -Git $t.git -Package $t.package -Upgrade:$Upgrade }
            'git-clone' { Install-GitCloneTool  -Name $t.name -Repo $t.repo -Destination $t.destination -PostInstall $t.postInstall }
            default     { Write-Warn "Unknown tool source '$($t.source)' for $($t.name); skipping." }
        }
    }
}

function Test-Installation {
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
    # Build expected: globals + EVERY domain's plugins (the per-session-domain
    # design installs all of them at setup, so verification covers all of them).
    $expected = @()
    $globals = Read-PluginConfig -Section "global"
    if ($globals) { $expected += @($globals) }
    foreach ($dom in (Get-DomainNames)) {
        $domainPlugins = Read-PluginConfig -Section $dom
        if ($domainPlugins) { $expected += @($domainPlugins) }
    }

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

# Invoke-DomainSwitch removed: per-session domain selection means no machine-
# wide "current domain" exists at install time. Domains are not uninstalled
# during reinstall because every domain's plugins are always installed.

function Invoke-Update {
    Write-Info "Updating AI Sherpa (all domains)..."

    # No more saved domain to recall — every install covers every domain.

    Register-Marketplaces

    # Update plugins: globals + every domain's.
    $plugins = Read-PluginConfig -Section "global"
    foreach ($entry in $plugins) {
        Write-Info "Updating $($entry.name) (global)..."
        claude plugin update $entry.name
    }
    foreach ($dom in (Get-DomainNames)) {
        $domainPlugins = Read-PluginConfig -Section $dom
        foreach ($entry in $domainPlugins) {
            Write-Info "Updating $($entry.name) ($dom)..."
            claude plugin update $entry.name
        }
    }

    # Re-clone raw-skills repos (globals + every domain, single pass — clone overwrites).
    Install-Skills

    # Upgrade tools (pip --upgrade / cargo --force / git pull).
    Install-Tools -Upgrade

    # Refresh AI Sherpa runtime artifacts (rune cache, hook script, slash-
    # command skill) — these MAY have changed even when plugins didn't.
    Copy-DomainRuneCache
    $hookPath = Write-SessionStartHook
    Register-SessionStartHook-Settings -HookPath $hookPath
    Install-AiSherpaSkill

    Write-GlobalSettings
    Write-AiSherpaState -HookPath $hookPath
    Write-Info "Update complete. Plugins, skills, tools, and AI Sherpa runtime refreshed."
    Write-Info "CLAUDE.md was NOT modified."
}

function Invoke-Uninstall {
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host "  AI Sherpa -- UNINSTALL" -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This will remove from $env:USERPROFILE\.claude\:"
    Write-Host "  - All Claude plugins listed in plugins.json (global + every domain)"
    Write-Host "  - All raw skills cloned from plugins.json skills.* repos"
    Write-Host "  - All CLI tools listed in plugins.json tools.* (rtk, claude-usage, code-review-graph, ...)"
    Write-Host "  - The marketplaces registered by setup"
    Write-Host "  - settings.json and CLAUDE.md (restored from .bak if present, else deleted)"
    Write-Host ""
    Write-Host "  NOT touched: Node.js / Python / Rust / Git toolchains, your projects,"
    Write-Host "  manually-installed plugins, ~/.claude/projects/ session logs."
    Write-Host ""
    $confirm = Read-Host "Type 'uninstall' to confirm"
    if ($confirm -ne 'uninstall') {
        Write-Info "Aborted (confirmation not received)."
        return
    }

    $configFile = "$ScriptDir\plugins.json"
    $config = $null
    if (Test-Path $configFile) {
        try { $config = Get-Content $configFile -Raw | ConvertFrom-Json } catch { Write-Warn "Could not parse plugins.json: $_" }
    }

    # 1. Uninstall Claude plugins (global + every domain)
    Write-Info "Removing Claude plugins..."
    if ($config) {
        $pluginEntries = @()
        if ($config.global) { $pluginEntries += @($config.global) }
        if ($config.domains) {
            foreach ($d in $config.domains.PSObject.Properties.Name) {
                if ($config.domains.$d) { $pluginEntries += @($config.domains.$d) }
            }
        }
        foreach ($p in $pluginEntries) {
            if ($p.marketplace) {
                Write-Info "  - $($p.name)@$($p.marketplace)"
                claude plugin uninstall "$($p.name)@$($p.marketplace)" --scope user 2>$null
            }
        }
    }

    # 2. Uninstall CLI tools (PyPI / cargo / git-clone)
    Write-Info "Removing CLI tools..."
    if ($config -and $config.tools) {
        $toolEntries = @()
        if ($config.tools.global) { $toolEntries += @($config.tools.global) }
        foreach ($d in $config.tools.PSObject.Properties.Name) {
            if ($d -eq 'global') { continue }
            if ($config.tools.$d) { $toolEntries += @($config.tools.$d) }
        }
        foreach ($t in $toolEntries) {
            switch ($t.source) {
                'pypi' {
                    Write-Info "  - $($t.name) (pip uninstall)"
                    $pipCmd = Resolve-PipCommand
                    if ($pipCmd -and $t.package) { & $pipCmd uninstall -y $t.package 2>$null }
                }
                'cargo' {
                    $pkg = if ($t.package) { $t.package } else { $t.name }
                    Write-Info "  - $($t.name) (cargo uninstall $pkg)"
                    if (Test-CommandExists "cargo") { & cargo uninstall $pkg 2>$null }
                }
                'git-clone' {
                    if ($t.destination) {
                        $dest = $t.destination -replace '^~', $env:USERPROFILE
                        if (Test-Path $dest) {
                            Write-Info "  - $($t.name) (rm $dest)"
                            Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
    }

    # 3. Remove raw skills - clone each source to figure out which skill folders we added
    Write-Info "Removing raw skills from ~/.claude/skills/..."
    if ($config -and $config.skills) {
        $skillsDir = "$env:USERPROFILE\.claude\skills"
        $skillEntries = @()
        if ($config.skills.global) { $skillEntries += @($config.skills.global) }
        foreach ($d in $config.skills.PSObject.Properties.Name) {
            if ($d -eq 'global') { continue }
            if ($config.skills.$d) { $skillEntries += @($config.skills.$d) }
        }
        foreach ($entry in $skillEntries) {
            $repo = $entry.repo
            $subpath = if ($entry.subpath) { $entry.subpath } else { "skills" }
            if (-not $repo) { continue }
            $tmp = Join-Path $env:TEMP "ai-sherpa-uninstall-$($repo -replace '/', '-')"
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
            & git clone --depth 1 --quiet "https://github.com/$repo" $tmp
            if ($LASTEXITCODE -eq 0) {
                $src = Join-Path $tmp $subpath
                if (Test-Path $src) {
                    foreach ($n in (Get-ChildItem $src -Directory | Select-Object -ExpandProperty Name)) {
                        $target = Join-Path $skillsDir $n
                        if (Test-Path $target) {
                            Write-Info "  - $n"
                            Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        }
    }

    # 4. Remove AI Sherpa runtime directory (~/.claude/ai-sherpa/) which holds
    # state.json, the SessionStart hook script, and the runtime domain rule
    # cache. Also remove the legacy state file from older versions, plus the
    # /ai-sherpa-domains slash-command skill. Per-project ai-sherpa-domains.json
    # files in user projects are NOT touched — those are user artifacts.
    $aishRuntime = "$env:USERPROFILE\.claude\ai-sherpa"
    if (Test-Path $aishRuntime) {
        Write-Info "Removing AI Sherpa runtime directory ($aishRuntime)..."
        Remove-Item $aishRuntime -Recurse -Force -ErrorAction SilentlyContinue
    }
    $legacyState = "$env:USERPROFILE\.claude\.ai-sherpa-state.json"
    foreach ($f in @($legacyState, "$legacyState.legacy")) {
        if (Test-Path $f) {
            Write-Info "Removing legacy state file ($f)..."
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    $aishSkill = "$env:USERPROFILE\.claude\skills\ai-sherpa-domains"
    if (Test-Path $aishSkill) {
        Write-Info "Removing /ai-sherpa-domains slash-command skill..."
        Remove-Item $aishSkill -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 5. Restore (or remove) settings.json and CLAUDE.md
    Write-Info "Restoring settings + rules..."
    $settingsFile = "$env:USERPROFILE\.claude\settings.json"
    $claudeMd     = "$env:USERPROFILE\.claude\CLAUDE.md"
    if (Test-Path "$settingsFile.bak") {
        Move-Item "$settingsFile.bak" $settingsFile -Force
        Write-Info "  Restored $settingsFile from .bak"
    } elseif (Test-Path $settingsFile) {
        Remove-Item $settingsFile -Force
        Write-Info "  Removed $settingsFile (no .bak)"
    }
    if (Test-Path "$claudeMd.bak") {
        Move-Item "$claudeMd.bak" $claudeMd -Force
        Write-Info "  Restored $claudeMd from .bak"
    } elseif (Test-Path $claudeMd) {
        Remove-Item $claudeMd -Force
        Write-Info "  Removed $claudeMd (no .bak)"
    }

    # 5. Remove marketplaces
    Write-Info "Removing registered marketplaces..."
    if ($config -and $config.marketplaces) {
        foreach ($m in $config.marketplaces) {
            if ($m.name) {
                Write-Info "  - $($m.name)"
                claude plugin marketplace remove $m.name 2>$null
            }
        }
    }

    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Green
    Write-Host "  AI Sherpa Uninstall Complete" -ForegroundColor Green
    Write-Host "======================================================" -ForegroundColor Green
    Write-Host "  Toolchains (Node / Python / Rust / Git) were NOT removed."
    Write-Host "  Re-run setup.bat to start fresh."
    Write-Host "======================================================" -ForegroundColor Green
    Write-Host ""
}

function Print-Summary {
    param([switch]$UserLevel)
    $domainCount = @(Get-DomainNames).Count
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  AI Sherpa Setup Complete" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Domains installed: $domainCount (all)"
    Write-Host "  Settings:          $env:USERPROFILE\.claude\settings.json"
    Write-Host "  Runtime cache:     $env:USERPROFILE\.claude\ai-sherpa\"
    if ($UserLevel) {
        Write-Host "  Core rules:        $env:USERPROFILE\.claude\CLAUDE.md  (all projects)"
    } else {
        $here = Get-Location
        Write-Host "  Project settings:  $here\.claude\settings.json"
        Write-Host "  Core rules:        $here\CLAUDE.md  (this project)"
    }
    Write-Host ""
    Write-Host "  How domain selection works now:"
    Write-Host "  - Open Claude Code in any project."
    Write-Host "  - The SessionStart hook auto-detects domains from the project's"
    Write-Host "    files (package.json, west.yml, Dockerfile, ...) and activates"
    Write-Host "    the matching rule sets."
    Write-Host "  - If detection finds nothing, Claude asks you to pick."
    Write-Host "  - Change anytime with: /ai-sherpa-domains"
    Write-Host ""
    Write-Host "  Update later: `"$ScriptDir\setup.bat`" --update"
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ----- per-session domain selection: runtime install helpers -----

# Enumerate all domain names declared under plugins.json/domains. Returns an
# array of strings (e.g. "embedded","web",...) suitable for foreach loops.
function Get-DomainNames {
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return @() }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    catch { return @() }
    if (-not $config.domains) { return @() }
    return @($config.domains.PSObject.Properties.Name)
}

# Resolve an identifier for the AI Sherpa checkout at install time. Prefers
# `git rev-parse HEAD` inside the script dir; falls back to the literal
# string "unknown". Used as the `ai_sherpa_version` field in state.json.
function Get-AiSherpaSpecVersion {
    if (-not (Test-CommandExists 'git')) { return 'unknown' }
    try {
        Push-Location $ScriptDir
        $sha = (& git rev-parse --short HEAD 2>$null | Out-String).Trim()
        Pop-Location
        if ($sha) { return $sha }
    } catch {}
    return 'unknown'
}

# Read the legacy ~/.claude/.ai-sherpa-state.json (old schema, has a top-level
# `domain` field) and return that field's value, or $null. Used only during
# migration to surface a one-time advisory to the user — the value is not
# auto-applied anywhere in the new design.
function Get-LegacyDomain {
    $f = "$env:USERPROFILE\.claude\.ai-sherpa-state.json"
    if (-not (Test-Path $f)) { return $null }
    try {
        $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.domain) { return $j.domain }
    } catch {}
    return $null
}

# Copy every domains/<X>/CLAUDE.md (in the AI Sherpa repo) to the runtime
# cache at ~/.claude/ai-sherpa/domains/<X>/CLAUDE.md. The SessionStart hook
# reads these. Overwrites unconditionally so `setup --update` always lands a
# fresh copy. Reads with -Encoding UTF8 on PS 5.1 to preserve em-dashes.
function Copy-DomainRuneCache {
    $src = "$ScriptDir\domains"
    if (-not (Test-Path $src)) {
        Write-Warn "domains/ not found at $src - skipping runtime cache copy."
        return
    }
    $dst = "$env:USERPROFILE\.claude\ai-sherpa\domains"
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    foreach ($dir in (Get-ChildItem -Path $src -Directory)) {
        $srcFile = Join-Path $dir.FullName 'CLAUDE.md'
        if (-not (Test-Path $srcFile)) { continue }
        $dstDir = Join-Path $dst $dir.Name
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        $content = Get-Content $srcFile -Raw -Encoding UTF8
        Set-Content -Path (Join-Path $dstDir 'CLAUDE.md') -Value $content -Encoding UTF8
    }
    Write-Info "Copied domain rule cache to $dst (1 per declared domain)."
}

# Copy the repo's hooks/sessionstart.js into the user's runtime directory and
# return the absolute destination path. The path is recorded in state.json
# and used by Register-SessionStartHook-Settings so settings.json embeds an
# unambiguous absolute path (no ~ expansion ambiguity at hook invocation).
function Write-SessionStartHook {
    $src = "$ScriptDir\hooks\sessionstart.js"
    if (-not (Test-Path $src)) {
        Write-Err "Hook source not found at $src - cannot install the SessionStart hook."
        return $null
    }
    $dstDir = "$env:USERPROFILE\.claude\ai-sherpa\hooks"
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    $dst = Join-Path $dstDir 'sessionstart.js'
    Copy-Item -Path $src -Destination $dst -Force
    Write-Info "Installed SessionStart hook at $dst"
    return $dst
}

# Merge a SessionStart hook entry into ~/.claude/settings.json. Idempotent:
# checks for an existing entry whose `command` already invokes our hook
# script and skips append if found. Preserves any other hook entries
# (notably the code-review-graph one shipped by settings-template.json).
function Register-SessionStartHook-Settings {
    param([string]$HookPath)
    if (-not $HookPath) { return }
    $settingsFile = "$env:USERPROFILE\.claude\settings.json"
    if (-not (Test-Path $settingsFile)) {
        Write-Warn "settings.json not found at $settingsFile - hook entry not registered. Re-run setup."
        return
    }
    $raw = Get-Content $settingsFile -Raw -Encoding UTF8
    try { $json = $raw | ConvertFrom-Json }
    catch {
        Write-Warn "Could not parse $settingsFile - hook entry not registered. Edit the file manually."
        return
    }

    if (-not $json.hooks) {
        $json | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if (-not $json.hooks.SessionStart) {
        $json.hooks | Add-Member -NotePropertyName 'SessionStart' -NotePropertyValue @() -Force
    }
    $existing = @($json.hooks.SessionStart)

    # Idempotency check: an entry already routes to our hook iff any of its
    # inner `hooks[].command` strings reference 'ai-sherpa\\hooks\\sessionstart.js'
    # (or the POSIX equivalent for cross-platform safety).
    $needle1 = 'ai-sherpa\hooks\sessionstart.js'
    $needle2 = 'ai-sherpa/hooks/sessionstart.js'
    $already = $false
    foreach ($entry in $existing) {
        if (-not $entry.hooks) { continue }
        foreach ($inner in @($entry.hooks)) {
            $cmd = "$($inner.command)"
            if ($cmd -and ($cmd.Contains($needle1) -or $cmd.Contains($needle2))) {
                $already = $true; break
            }
        }
        if ($already) { break }
    }
    if ($already) {
        Write-Info "SessionStart hook entry already present in settings.json - skipping."
        return
    }

    # Append a new entry. Quote the path because Windows paths may contain
    # spaces; ConvertTo-Json's default depth (2) loses nested objects, so
    # we use -Depth 10.
    $commandStr = 'node "{0}"' -f $HookPath
    $newEntry = [pscustomobject]@{
        matcher = 'startup|resume|clear|compact'
        hooks   = @(
            [pscustomobject]@{
                type    = 'command'
                command = $commandStr
                timeout = 10000
            }
        )
    }
    $json.hooks.SessionStart = @($existing + $newEntry)
    $out = ($json | ConvertTo-Json -Depth 10)
    Set-Content -Path $settingsFile -Value $out -Encoding UTF8
    Write-Info "Registered SessionStart hook in $settingsFile"
}

# Copy the repo's skills/ai-sherpa-domains/ into ~/.claude/skills/ so users
# can invoke /ai-sherpa-domains. Overwrites unconditionally on every install
# and --update so the SKILL.md stays current.
function Install-AiSherpaSkill {
    $src = "$ScriptDir\skills\ai-sherpa-domains"
    if (-not (Test-Path $src)) {
        Write-Warn "Slash-command skill source not found at $src - skipping."
        return
    }
    $dstParent = "$env:USERPROFILE\.claude\skills"
    if (-not (Test-Path $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
    $dst = Join-Path $dstParent 'ai-sherpa-domains'
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
    Write-Info "Installed /ai-sherpa-domains skill at $dst"
}

# Write a project-local selection file for the AI Sherpa repo itself, so
# working ON AI Sherpa always loads a known stable domain set without
# triggering the auto-detect banner on every conversation. Idempotent:
# only writes if the file doesn't exist (respects user edits).
function Install-AiSherpaProjectFile {
    $projectClaude = "$ScriptDir\.claude"
    $target = Join-Path $projectClaude 'ai-sherpa-domains.json'
    if (Test-Path $target) {
        Write-Info "$target already exists - leaving it as the user configured."
        return
    }
    if (-not (Test-Path $projectClaude)) { New-Item -ItemType Directory -Path $projectClaude -Force | Out-Null }
    $obj = [ordered]@{
        version        = 1
        domains        = @('devops')
        detected       = $false
        user_confirmed = $true
        updated_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    ($obj | ConvertTo-Json) | Set-Content -Path $target -Encoding UTF8
    Write-Info "Seeded $target with default domains for AI Sherpa repo work."
}

# --- Main ---
Show-Logo

if ($Update) {
    Invoke-Update
    exit 0
}

if ($Uninstall) {
    Invoke-Uninstall
    exit 0
}


# Detect whether this is a user-level (double-click) or project-level run.
$currentPath = (Get-Location).Path
$isUserLevelRun = ((Test-Path "$currentPath\core\CLAUDE.md") -and ($currentPath -eq $ScriptDir))

# Prerequisites (both paths)
Write-Info "Checking prerequisites..."
# winget is the foundation: Install-NodeJS / Install-Git / Install-Python /
# Install-Rust all use it. Bootstrap it if missing before anything else tries
# to call it. Skip on uninstall — we're tearing down, not building up.
if (-not $Uninstall) { Install-Winget }
Install-NodeJS
Install-Git
Install-ClaudeCode

# Per-session domain selection: NO install-time prompt anymore. Setup installs
# every domain's plugins and the SessionStart hook picks the active set per
# project at conversation start. See
# docs/superpowers/specs/2026-06-01-per-session-domain-selection-design.md.

# Migration: if a legacy ~/.claude/.ai-sherpa-state.json exists (with a top-
# level `domain` field), surface a one-time advisory and rename the file as a
# paper trail so it doesn't shadow the new state.json schema.
$legacyDomain = Get-LegacyDomain
$legacyStateFile = "$env:USERPROFILE\.claude\.ai-sherpa-state.json"
if ($legacyDomain) {
    Write-Info "Detected legacy install with domain='$legacyDomain'."
    Write-Info "Migrating to per-conversation domain selection..."
    Add-UserAction -Title "Heads up: domain selection moved to per-project" `
                   -Why "Your previous AI Sherpa install used domain='$legacyDomain' system-wide. Going forward, each project picks its own domain(s). The first conversation you open in any project will auto-detect (or ask if detection finds nothing). Use /ai-sherpa-domains inside Claude Code to override." `
                   -Command "(no immediate action required — heads-up only)"
}

# Plugins / skills / tools — install global + ALL domains.
Register-Marketplaces
Install-CoreSkills
foreach ($dom in (Get-DomainNames)) {
    Install-DomainSkills $dom
}
Install-Skills
Write-GlobalSettings

# Embedded toolchain probing is now UNCONDITIONAL (every domain is installed,
# so embedded tools are always potentially relevant).
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

# AI Sherpa runtime artifacts.
Copy-DomainRuneCache
$hookPath = Write-SessionStartHook

if ($isUserLevelRun) {
    # User-level: write core CLAUDE.md to ~/.claude/ (no domain merge).
    Write-CoreOnlyClaudeMd
    Register-SessionStartHook-Settings -HookPath $hookPath
    Install-AiSherpaSkill
    Enable-WindowsLongPaths
    # No auto-Upgrade on plain re-runs. Install-PyPiTool / Install-CargoTool
    # skip tools that are already on PATH; explicit upgrades go through
    # `setup.bat --update` (Invoke-Update at line ~1230 sets -Upgrade).
    Install-Tools
    Write-AiSherpaState -HookPath $hookPath
    Install-AiSherpaProjectFile

    # Migration paper-trail: rename legacy state file AFTER the new one is in
    # place so a failed install doesn't lose the user's old marker.
    if ($legacyDomain -and (Test-Path $legacyStateFile)) {
        Move-Item $legacyStateFile "$legacyStateFile.legacy" -Force -ErrorAction SilentlyContinue
        Write-Info "Renamed legacy state file to $legacyStateFile.legacy"
    }

    $missing = Test-Installation
    if ($missing.Count -gt 0) {
        Show-VerificationReport $missing
        Show-SkippedStepsReport
        Show-UserActionsReport
        Print-Summary -UserLevel
        exit 1
    }
    Write-Info "All expected plugins verified in installed_plugins.json."
    Show-SkippedStepsReport
    Show-UserActionsReport
    Print-Summary -UserLevel
} else {
    # Project-level: write core CLAUDE.md + settings into current project dir.
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
    Copy-CoreOnlyClaudeMd-ToProject $projectType
    # The hook is global by nature (~/.claude/settings.json). Register it
    # here too so a project-level run is sufficient to wire everything up.
    Register-SessionStartHook-Settings -HookPath $hookPath
    Install-AiSherpaSkill
    Enable-WindowsLongPaths
    # No auto-Upgrade on plain re-runs. Install-PyPiTool / Install-CargoTool
    # skip tools that are already on PATH; explicit upgrades go through
    # `setup.bat --update` (Invoke-Update at line ~1230 sets -Upgrade).
    Install-Tools
    Write-AiSherpaState -HookPath $hookPath

    if ($legacyDomain -and (Test-Path $legacyStateFile)) {
        Move-Item $legacyStateFile "$legacyStateFile.legacy" -Force -ErrorAction SilentlyContinue
        Write-Info "Renamed legacy state file to $legacyStateFile.legacy"
    }

    $missing = Test-Installation
    if ($missing.Count -gt 0) {
        Show-VerificationReport $missing
        Show-SkippedStepsReport
        Show-UserActionsReport
        Print-Summary
        exit 1
    }
    Write-Info "All expected plugins verified in installed_plugins.json."
    Show-SkippedStepsReport
    Show-UserActionsReport
    Print-Summary
}
