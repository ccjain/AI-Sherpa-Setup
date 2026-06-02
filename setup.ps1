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

# Returns a platform-arch key like "windows-x64", "linux-arm64", "macos-arm64".
# Used by Install-GitHubReleaseTool to look up the right asset in plugins.json.
# Defaults to "x64" on unrecognized architectures (no current tool ships
# 32-bit or exotic-arch binaries, so misdetection just falls into the
# platform-missing error path in the installer). $IsWindows/$IsLinux/$IsMacOS
# are undefined on PS 5.1; the env-var/default chain handles that.
function Get-PlatformArchKey {
    $os = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'windows' }
          elseif ($IsLinux)   { 'linux' }
          elseif ($IsMacOS)   { 'macos' }
          else                { 'windows' }
    $archRaw = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $arch = switch -Regex ($archRaw) {
        'Arm64'   { 'arm64'; break }
        'Arm'     { 'arm64'; break }
        'X64'     { 'x64'; break }
        default   { 'x64' }
    }
    return "$os-$arch"
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
# or $null if not installed. Used by Install-Plugin to decide install-vs-update
# and by Invoke-DomainSwitch to decide what to uninstall. Reads claude's own
# installed_plugins.json — same source of truth that Test-Installation uses.
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

# Check whether a plugin is currently enabled.
#
# Truth source (in priority order):
#   1. ~/.claude/settings.json#enabledPlugins[<spec>] — the actual key
#      `claude plugin list` reads to decide ✓ enabled vs × disabled. Per
#      upstream issue https://github.com/anthropics/claude-code/issues/20661,
#      `claude plugin install` and `claude plugin enable` do NOT reliably
#      populate this key — setup has to write it itself via
#      Set-AllInstalledPluginsEnabled.
#   2. installed_plugins.json with an explicit enabled/disabled/status
#      marker. Kept as forward-compat for any future CLI schema; current
#      v2 schema has none of these fields, so this branch is dead today
#      but cheap to leave in.
#
# Returns $false on any uncertainty so Enable-Plugin falls through to
# either the CLI call (harmless no-op given the upstream bug) or the
# bulk-enable-via-settings.json pass at end of install/update.
function Test-PluginEnabled {
    param([string]$Spec)

    # 1. settings.json#enabledPlugins — authoritative for v2 CLI.
    $settingsFile = "$env:USERPROFILE\.claude\settings.json"
    if (Test-Path $settingsFile) {
        try {
            $s = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.enabledPlugins -and $null -ne $s.enabledPlugins.$Spec) {
                return [bool]$s.enabledPlugins.$Spec
            }
        } catch {}
    }

    # 2. installed_plugins.json explicit markers — forward-compat only.
    $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
    if (-not (Test-Path $installedFile)) { return $false }
    try {
        $j = Get-Content $installedFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $j.plugins) { return $false }
        $entry = $j.plugins.$Spec
        if (-not $entry) { return $false }
        if ($null -ne $entry.enabled)  { return [bool]$entry.enabled }
        if ($null -ne $entry.disabled) { return -not [bool]$entry.disabled }
        if ($null -ne $entry.status)   { return ($entry.status -eq 'enabled') }
        return $false
    } catch { return $false }
}

# Workaround for claude-code#20661 (claude plugin install/enable don't
# populate settings.json#enabledPlugins, so the UI shows everything as
# × disabled). Sweep installed_plugins.json -> set each spec to true,
# or false when its domain is in disabled_domains. MUST run AFTER
# Write-GlobalSettings — template overwrite would clobber otherwise.
function Set-AllInstalledPluginsEnabled {
    $settingsFile  = "$env:USERPROFILE\.claude\settings.json"
    $installedFile = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"

    if (-not (Test-Path $installedFile)) {
        Write-Warn "installed_plugins.json not found at $installedFile - skipping enable-in-settings pass."
        return
    }
    try {
        $installed = Get-Content $installedFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "Could not parse installed_plugins.json: $($_.Exception.Message)"
        return
    }
    if (-not $installed.plugins) {
        Write-Info "installed_plugins.json has no plugins block - nothing to enable."
        return
    }

    # Build the set of "<name>@<marketplace>" specs that should be DISABLED
    # because their domain is listed in plugins.json#disabled_domains. Setup
    # may have previously installed these plugins (before disabled_domains
    # was set, or during a prior run); we set them to false here so they
    # stop loading without uninstalling on disk.
    $disabledSpecs = @{}
    try {
        $cfg = Get-Content "$ScriptDir\plugins.json" -Raw | ConvertFrom-Json
        $disabledDomains = if ($cfg.disabled_domains) { @($cfg.disabled_domains) } else { @() }
        if ($cfg.domains -and $disabledDomains.Count -gt 0) {
            foreach ($d in $disabledDomains) {
                if ($cfg.domains.$d) {
                    foreach ($p in @($cfg.domains.$d)) {
                        if ($p.marketplace -and $p.name) {
                            $disabledSpecs["$($p.name)@$($p.marketplace)"] = $true
                        }
                    }
                }
            }
        }
    } catch {}

    $settings = if (Test-Path $settingsFile) {
        try { Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { [PSCustomObject]@{} }
    } else { [PSCustomObject]@{} }

    if (-not $settings.enabledPlugins) {
        $settings | Add-Member -NotePropertyName enabledPlugins `
                               -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    $enabledCount = 0
    $disabledCount = 0
    foreach ($spec in @($installed.plugins.PSObject.Properties.Name)) {
        $value = if ($disabledSpecs.ContainsKey($spec)) { $false } else { $true }
        $settings.enabledPlugins | Add-Member -NotePropertyName $spec `
                                              -NotePropertyValue $value -Force
        if ($value) { $enabledCount++ } else { $disabledCount++ }
    }

    # Depth 10 because settings.json#hooks contains nested arrays-of-objects-
    # of-arrays-of-objects (matcher -> hooks -> command). Default depth (2)
    # would truncate the hooks block to "System.Object[]" garbage on round-trip.
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
    if ($disabledCount -gt 0) {
        Write-Info "settings.json#enabledPlugins: $enabledCount enabled, $disabledCount disabled (per plugins.json#disabled_domains)."
    } else {
        Write-Info "Wrote enabledPlugins for $enabledCount plugins into settings.json (workaround for claude-code#20661)."
    }
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
        # Local $ErrorActionPreference = 'Continue' so that when claude.exe
        # writes "× Failed... already enabled" to stderr, PS 5.1's `2>file`
        # redirect doesn't escalate the line through NativeCommandError +
        # the script-level Stop into a terminating error — the existing
        # "already enabled" stderr pattern-match below needs to actually
        # run instead of the script crashing first.
        $oldEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = & claude plugin enable $Spec 2>$tmpErr
            $rc = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldEAP
        }
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

# Run `claude plugin install <spec>` or `claude plugin update <spec>` with
# EBUSY-aware retry. Claude CLI's plugin install/update path on Windows
# creates a `temp_git_<ts>_<rand>` directory, git-clones the new version
# into it, and tries to remove the temp dir after the swap. The rm
# regularly hits EBUSY because Windows Defender / Search Indexer / git.exe
# children still hold file handles on freshly-cloned files for ~100-500ms.
# It's a transient lock: a 2-second wait and retry almost always succeeds.
#
# We retry up to $MaxAttempts times but ONLY when stderr matches the EBUSY
# + temp_git_ pattern; any other failure mode (network, auth, real conflict)
# fails fast on the first attempt as before. Stdout passes through so the
# user sees claude's own "Checking for updates..." / "Already at latest"
# messages; stderr is captured for retry detection and re-emitted only if
# all attempts fail, so a successful retry isn't accompanied by a confusing
# wall of "× Failed..." text.
function Invoke-PluginCommand {
    param(
        [Parameter(Mandatory)][ValidateSet('install','update')][string]$Operation,
        [Parameter(Mandatory)][string]$Spec,
        [string]$Scope = 'user',
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 2
    )
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $finalRc = 0
    $finalStderr = ''
    try {
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            # PS 5.1 native-command call needs two safety belts to coexist with
            # the script-level $ErrorActionPreference = "Stop":
            #
            # 1. Local $ErrorActionPreference = 'Continue'. When claude.exe
            #    writes to stderr (the EBUSY message), PS 5.1's `2>file`
            #    redirect still routes the lines through PS's error stream
            #    and wraps them as NativeCommandError records. Under global
            #    Stop, that becomes a TERMINATING error and aborts the
            #    entire script — the retry loop never gets to iterate.
            #
            # 2. `| Out-Host` pipes stdout to the terminal but keeps it OUT
            #    of the function's pipeline output. Without it, every line
            #    claude.exe prints to stdout (the "Checking for updates..."
            #    progress text) becomes part of this function's return value
            #    alongside $finalRc, so callers do `$rc = Invoke-PluginCommand`
            #    and get [String[], Int32] not Int32 — and `if ($rc -ne 0)`
            #    evaluates against an array which is never -ne 0 the way
            #    we want it.
            $oldEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                & claude plugin $Operation $Spec --scope $Scope 2>$tmpErr | Out-Host
                $finalRc = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $oldEAP
            }
            $finalStderr = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
            if ($finalRc -eq 0) { break }
            $isEbusy = $finalStderr -and $finalStderr -match 'EBUSY.*temp_git_'
            if (-not $isEbusy) { break }
            if ($attempt -lt $MaxAttempts) {
                Write-Warn "  $Spec ${Operation}: Windows EBUSY on temp_git_* (AV/indexer holds file); retry $($attempt + 1)/$MaxAttempts in ${DelaySeconds}s..."
                Start-Sleep -Seconds $DelaySeconds
                Clear-Content $tmpErr -ErrorAction SilentlyContinue
            }
        }
    } finally {
        Remove-Item $tmpErr -ErrorAction SilentlyContinue
    }
    # On final failure, re-emit the captured stderr so the user sees the real
    # error. On retry-success the suppressed early stderr is intentionally
    # dropped (it was the transient EBUSY).
    if ($finalRc -ne 0 -and $finalStderr) {
        Write-Host $finalStderr.Trim() -ForegroundColor Red
    }
    $global:LASTEXITCODE = $finalRc
    return $finalRc
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
            $rc = Invoke-PluginCommand -Operation update -Spec $key
            if ($rc -ne 0) {
                Write-Warn "  $key update returned exit $rc (continuing)."
                $global:LASTEXITCODE = 0
            }
            Enable-Plugin $key
        } else {
            Write-Info "  [NEW]    $key installing..."
            $rc = Invoke-PluginCommand -Operation install -Spec $key
            if ($rc -ne 0) {
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
            $rc = Invoke-PluginCommand -Operation update -Spec $Entry.name
            if ($rc -ne 0) {
                Write-Warn "  $($Entry.name) update returned exit $rc (continuing)."
                $global:LASTEXITCODE = 0
            }
            Enable-Plugin $Entry.name
        } else {
            Write-Info "  [NEW]    $($Entry.name) installing from github: $($Entry.github)..."
            try { & claude plugin marketplace add "https://github.com/$($Entry.github)" 2>&1 | Out-Null } catch {}
            $global:LASTEXITCODE = 0
            $rc = Invoke-PluginCommand -Operation install -Spec $Entry.name
            if ($rc -ne 0) {
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
        # See Enable-Plugin / Invoke-PluginCommand for the rationale on the
        # local $ErrorActionPreference = 'Continue' belt: without it, any
        # stderr line from claude.exe (auth failure, network error, etc.)
        # gets wrapped as NativeCommandError and aborts the script under
        # the global Stop preference, bypassing the auth-pattern fallback
        # below that's supposed to convert "not logged in" into a clear
        # ACTION REQUIRED.
        $oldEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $null = & claude plugin marketplace update $Name 2>$tmpErr
            $rc = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldEAP
        }
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
    # As of the per-session-domain-selection design, setup registers EVERY
    # marketplace declared in plugins.json regardless of which domain (if any)
    # the user picked at install time. The SessionStart hook activates
    # per-session rules and may reference plugins from any domain — so every
    # marketplace must be available on every machine, not just the ones
    # referenced by the currently-selected domain.
    #
    # The $Domain parameter is kept for source-compatibility with existing
    # callers but is no longer consulted. Safe to drop in a future change.
    param([string]$Domain = "")
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) { return }
    try { $config = Get-Content $configFile -Raw | ConvertFrom-Json }
    catch { return }

    # Build name -> repo map of marketplaces declared in plugins.json.
    $declared = @{}
    if ($config.marketplaces) {
        foreach ($entry in @($config.marketplaces)) {
            $repo = if ($entry -is [string]) { $entry } else { $entry.repo }
            $name = if ($entry -is [string]) { $null } else { $entry.name }
            if ($repo -and $name) { $declared[$name] = $repo }
        }
    }

    # Sanity check: every marketplace referenced by global OR any domain plugin
    # must be declared. Surface undeclared references as user-action items
    # before attempting installs, so the gap is visible at install time rather
    # than as a confusing 'Marketplace not found' later.
    $referenced = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $config.global) {
        if ($p.marketplace) { $referenced.Add($p.marketplace) | Out-Null }
    }
    if ($config.domains) {
        foreach ($d in $config.domains.PSObject.Properties) {
            foreach ($p in $d.Value) {
                if ($p.marketplace) { $referenced.Add($p.marketplace) | Out-Null }
            }
        }
    }
    foreach ($name in $referenced) {
        if (-not $declared.ContainsKey($name)) {
            Write-Action "marketplace '$name' is referenced by plugins.json but not declared in marketplaces[]."
            Add-UserAction -Title "Declare marketplace '$name' in plugins.json" `
                           -Why "Plugins in plugins.json reference marketplace '$name' but the marketplaces[] array doesn't list it. Claude CLI requires every marketplace to be registered via 'claude plugin marketplace add <repo>' before any plugin from it can install. Setup can't `add` what it doesn't know the repo for, so plugins from '$name' will fail to install with 'Marketplace not found' until this is declared." `
                           -Command "Edit plugins.json and add a row like { ""repo"": ""<owner>/<repo>"", ""name"": ""$name"" } to the marketplaces[] array. Then re-run setup."
        }
    }

    # Register every declared marketplace. Skip the redundant `marketplace add`
    # on re-runs (it's a no-op for already-known marketplaces). Always refresh
    # the cache via update, otherwise `claude plugin update` sees stale data.
    foreach ($name in $declared.Keys) {
        $repo = $declared[$name]
        if (Test-MarketplaceRegistered $name) {
            Write-Info "  [REFRESH] marketplace $name (already registered, refreshing cache)"
        } else {
            Write-Info "  [NEW]     marketplace $name ($repo)"
            # Capture exit+stderr — silent fails (network, transient CLI, GitHub
            # rate-limit) now surface here, not 200 lines later as "not found".
            $tmpErr = [System.IO.Path]::GetTempFileName()
            $oldEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { $null = & claude plugin marketplace add $repo 2>$tmpErr; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $oldEAP }
            $stderr = (Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue); Remove-Item $tmpErr -ErrorAction SilentlyContinue; $global:LASTEXITCODE = 0
            if ($rc -ne 0 -and $stderr -notmatch '(?i)already (added|registered|exists)') {
                $errSummary = ($stderr -replace '\s+',' ').Trim()
                Write-Action "marketplace add failed: $name (exit $rc) - $errSummary"
                Add-UserAction -Title "Add marketplace $name manually" -Why "Add failed (exit $rc); plugins from $name cannot install until registered. stderr: $errSummary" -Command "claude plugin marketplace add $repo"
                continue
            }
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

# Installs Node-based UserPromptSubmit / SessionStart hook scripts shipped
# in the repo's hooks/ dir to ~/.claude/hooks/. Returns the install path
# with forward slashes so it can be embedded directly into JSON (no \ escaping).
function Install-Hooks {
    $hooksDir = "$env:USERPROFILE\.claude\hooks"
    if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null }
    $srcHooks = "$ScriptDir\hooks"
    if (Test-Path $srcHooks) {
        Copy-Item "$srcHooks\*.js" $hooksDir -Force -ErrorAction SilentlyContinue
        Write-Info "Hooks installed to $hooksDir"
    }
    return ($hooksDir -replace '\\', '/')
}

# Renders the settings template with __CLAUDE_HOOKS_DIR__ substituted to
# the actual hooks install path, then writes to $DestPath as UTF-8.
function Write-RenderedSettings {
    param([string]$DestPath)
    $hooksDir = Install-Hooks
    $template = Get-Content "$ScriptDir\settings\settings-template.json" -Raw
    $rendered = $template.Replace('__CLAUDE_HOOKS_DIR__', $hooksDir)
    [System.IO.File]::WriteAllText($DestPath, $rendered, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-GlobalSettings {
    $settingsDir  = "$env:USERPROFILE\.claude"
    $settingsFile = "$settingsDir\settings.json"
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
    if (Test-Path $settingsFile) {
        Copy-Item $settingsFile "$settingsFile.bak" -Force
        Write-Warn "Backed up existing global settings.json to settings.json.bak"
    }
    Write-RenderedSettings -DestPath $settingsFile
    Write-Info "Secrets protection + hooks written to $settingsFile"
}

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

function Copy-ClaudeMd {
    param([string]$Domain, [string]$ProjectType)
    $core   = "$ScriptDir\core\CLAUDE.md"
    $domain = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    if (-not (Test-Path $domain)) {
        Write-Err "Domain CLAUDE.md not found at: $domain"
        Write-Err "Is '$Domain' a valid domain? Valid: embedded, web, data, devops, marketing, sales, finance, service, procurement"
        exit 1
    }
    $target = "$(Get-Location)\CLAUDE.md"
    # -Encoding UTF8 on Get-Content is REQUIRED on PowerShell 5.1 (see comment
    # in Write-GlobalClaudeMd above).
    $coreContent   = (Get-Content $core -Raw -Encoding UTF8).TrimEnd()
    $domainContent = (Get-Content $domain -Raw -Encoding UTF8)
    $merged = $coreContent + "`r`n`r`n---`r`n`r`n" + $domainContent
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending AI Sherpa rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---" -Encoding UTF8
        Add-Content $target "<!-- AI Sherpa core + $Domain rules - do not edit below this line -->" -Encoding UTF8
        Add-Content $target $merged -Encoding UTF8
    } else {
        Set-Content -Path $target -Value $merged -Encoding UTF8
    }
    Write-Info "Merged core + $Domain CLAUDE.md installed at $target"
}

function Write-AiSherpaState {
    param([string]$Domain)
    $stateDir  = "$env:USERPROFILE\.claude"
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $stateFile = "$stateDir\.ai-sherpa-state.json"
    $state = @{
        domain    = $Domain
        installed = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        version   = "1"
    }
    $state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    Write-Info "Recorded domain '$Domain' in $stateFile (for future --update runs)."
}

function Get-AiSherpaDomain {
    $stateFile = "$env:USERPROFILE\.claude\.ai-sherpa-state.json"
    if (-not (Test-Path $stateFile)) { return $null }
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        return $state.domain
    } catch { return $null }
}

function Write-GlobalClaudeMd {
    param([string]$Domain)
    $core   = "$ScriptDir\core\CLAUDE.md"
    $domain = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    if (-not (Test-Path $domain)) {
        Write-Err "Domain CLAUDE.md not found at: $domain"
        exit 1
    }
    $claudeDir = "$env:USERPROFILE\.claude"
    $target    = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    # Merge: core rules first, then the chosen domain's rules. Universal guidance
    # reads first, domain refines on top. Separator makes the boundary obvious.
    # -Encoding UTF8 on Get-Content is REQUIRED on PowerShell 5.1: the default
    # codepage is system ANSI (Windows-1252 in en-US), which mangles UTF-8 chars
    # like em-dashes (— -> â€") at read time. Write-side -Encoding UTF8 alone
    # is not enough because the corruption happens before the write.
    $coreContent   = (Get-Content $core -Raw -Encoding UTF8).TrimEnd()
    $domainContent = (Get-Content $domain -Raw -Encoding UTF8)
    $merged = $coreContent + "`r`n`r`n---`r`n`r`n" + $domainContent
    Set-Content -Path $target -Value $merged -Encoding UTF8
    Write-Info "Merged core + $Domain rules written to $target (active for all projects)"
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
    # explicit update mode. Avoids the noisy install/upgrade churn on every
    # plain setup.bat re-run. `setup.bat --update` flips $Upgrade and
    # bypasses this skip.
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
                # already at latest, upgrades when a newer version exists.
                # We use it unconditionally instead of `uv tool upgrade`
                # because the latter errors with "not installed" when the
                # tool was previously installed via a different installer
                # (pip-user, pipx) and only the binary — not uv's tool
                # registry — knows about it.
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

    # Fast-path: skip if tool already on PATH and not explicitly updating.
    # `cargo install` without --force is a no-op when the tool is at latest,
    # but still pulls crates.io metadata. The skip avoids even that.
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

# Install a tool by downloading its pre-built binary from a GitHub release.
# Required Entry fields (from plugins.json):
#   - name        : binary name (without .exe; .exe is appended on Windows)
#   - repo        : "<owner>/<name>" - used to query /repos/<repo>/releases/latest
#   - asset       : hashtable of platform-arch -> asset filename in the release
#   - binary      : binary name to look for inside the extracted archive
#   - destination : install dir (~/.local/bin etc.; ~ is expanded)
# Optional:
#   - Upgrade switch: bypass the skip-if-installed gate
#
# Decision flow follows spec docs/superpowers/specs/2026-06-02-rtk-github-release-installer-design.md
# Cases A through H.
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
    param([string]$Domain, [switch]$Upgrade)
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
            'pypi'           { Install-PyPiTool           -Name $t.name -Package $t.package -PostInstall $t.postInstall -Upgrade:$Upgrade }
            'cargo'          { Install-CargoTool          -Name $t.name -Git $t.git -Package $t.package -Upgrade:$Upgrade }
            'git-clone'      { Install-GitCloneTool       -Name $t.name -Repo $t.repo -Destination $t.destination -PostInstall $t.postInstall }
            'github-release' { Install-GitHubReleaseTool  -Entry $t -Upgrade:$Upgrade }
            default          { Write-Warn "Unknown tool source '$($t.source)' for $($t.name); skipping." }
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

function Invoke-DomainSwitch {
    param([string]$OldDomain, [string]$NewDomain)
    if (-not $OldDomain -or $OldDomain -eq $NewDomain) { return }
    $oldPlugins = Read-PluginConfig -Section $OldDomain
    if (-not $oldPlugins -or @($oldPlugins).Count -eq 0) {
        Write-Info "Domain switch '$OldDomain' -> '$NewDomain': no $OldDomain-specific plugins to remove."
        return
    }
    Write-Info "Domain switch '$OldDomain' -> '$NewDomain': removing $OldDomain-specific plugins..."
    foreach ($p in $oldPlugins) {
        if (-not $p.marketplace) { continue }
        $key = "$($p.name)@$($p.marketplace)"
        $existingVersion = Test-PluginInstalled $key
        if ($existingVersion) {
            Write-Info "  [REMOVE] $key (v$existingVersion)"
            claude plugin uninstall $key --scope user 2>&1 | Out-Null
            $global:LASTEXITCODE = 0
        }
    }
    # Note: global plugins, raw skills, and CLI tools are intentionally NOT
    # removed — they're shared across domains and the new domain's install pass
    # will refresh them via the same install-or-update logic in Install-Plugin.
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa..."

    # Recall which domain the user picked at install time (state file written
    # by Write-AiSherpaState). If we can't find it, fall back to "global only":
    # only refresh global plugins/skills/tools, since we don't know which
    # domain the user is on.
    $savedDomain = Get-AiSherpaDomain
    if ($savedDomain) {
        Write-Info "Recalled domain '$savedDomain' from previous install."
    } else {
        Write-Warn "No saved domain found. Updating global plugins/skills/tools only."
        Write-Warn "Re-run setup.bat (not --update) once to pick a domain and record state."
    }

    # Refresh marketplace caches so `claude plugin update` sees latest versions.
    Register-Marketplaces

    # Update plugins: globals plus EVERY declared domain's plugins. Per the
    # per-session-domain-selection design every domain is installed; the
    # update path mirrors that. $savedDomain stays meaningful as the initial
    # default state but doesn't gate which plugins get refreshed.
    $plugins = Read-PluginConfig -Section "global"
    foreach ($entry in $plugins) {
        Write-Info "Updating $($entry.name)..."
        claude plugin update $entry.name
    }
    $pluginsCfg = $null
    try { $pluginsCfg = Get-Content "$ScriptDir\plugins.json" -Raw | ConvertFrom-Json } catch {}
    $disabledDomains = if ($pluginsCfg.disabled_domains) { @($pluginsCfg.disabled_domains) } else { @() }
    if ($pluginsCfg -and $pluginsCfg.domains) {
        foreach ($d in @($pluginsCfg.domains.PSObject.Properties.Name)) {
            if ($disabledDomains -contains $d) { Write-Info "  [SKIP] $d (disabled_domains)"; continue }
            $domainPlugins = Read-PluginConfig -Section $d
            foreach ($entry in $domainPlugins) {
                Write-Info "Updating $($entry.name) ($d)..."
                claude plugin update $entry.name
            }
            # Re-clone raw-skills repos for this domain (clone overwrites).
            Install-Skills -Domain $d
        }
    } elseif ($savedDomain) {
        $domainPlugins = Read-PluginConfig -Section $savedDomain
        foreach ($entry in $domainPlugins) {
            Write-Info "Updating $($entry.name) ($savedDomain)..."
            claude plugin update $entry.name
        }
        Install-Skills -Domain $savedDomain
    }

    # Upgrade tools: pip --upgrade / cargo --force / git pull.
    Install-Tools -Domain $savedDomain -Upgrade

    Write-GlobalSettings
    # Same ordering as the main install flow — must run AFTER
    # Write-GlobalSettings so the template overwrite doesn't clobber it.
    Set-AllInstalledPluginsEnabled
    Write-Info "Update complete. Plugins, skills, and tools refreshed to latest$(if ($savedDomain) { " for domain '$savedDomain'" })."
    Write-Info "Project CLAUDE.md was NOT modified."
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

    # 4. Remove AI Sherpa state file (.ai-sherpa-state.json — the saved-domain marker)
    $stateFile = "$env:USERPROFILE\.claude\.ai-sherpa-state.json"
    if (Test-Path $stateFile) {
        Write-Info "Removing AI Sherpa state file..."
        Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
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
# Skip the main flow when this script is dot-sourced as a library (e.g. by
# scripts/test-setup.ps1). The guard variable is set by the sourcing script
# before dot-sourcing.
if (-not $script:SourcedAsLibrary) {
Show-Logo

if ($Update) {
    Invoke-Update
    exit 0
}

if ($Uninstall) {
    Invoke-Uninstall
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

# Domain selection — DISABLED.
#
# Setup now registers every declared marketplace and installs every domain's
# plugins unconditionally (see Register-Marketplaces / Install-DomainSkills
# loop below). The SessionStart hook activates the active-domain rules per
# project, so asking the user to pick a single domain at install time would
# imply a choice that doesn't actually affect what gets installed.
#
# $domain is still used downstream for:
#   - embedded-toolchain detection (`if ($domain -eq "embedded") { ... }`)
#   - Write-GlobalClaudeMd $domain  (CLAUDE.md domain rules merge)
#   - Install-Tools -Domain $domain  (per-domain CLI tools)
#   - Write-AiSherpaState -Domain $domain  (state.json initial value)
#   - Test-Installation $domain  (verification + summary)
#
# Default policy:
#   - Re-run: keep the saved domain from .ai-sherpa-state.json (preserves
#     the user's prior choice, no destructive Invoke-DomainSwitch fires).
#   - Fresh install: default to "embedded" since that's the first domain
#     in the list. The actual install pass is domain-agnostic so any
#     value works for the downstream uses; we just need *something* set.
#
# TODO: when the per-session-domain hook fully obsoletes the install-time
# notion of "the" domain, drop $domain entirely and rewrite the call sites
# above to read per-project state instead.
$savedDomain = Get-AiSherpaDomain
if ($savedDomain) { $domain = $savedDomain } else { $domain = "embedded" }
$isReinstall = $null -ne $savedDomain

# Original interactive prompt — to restore, remove the surrounding block-
# comment markers from the next segment.
<#
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
#>
if ($isReinstall) {
    if ($savedDomain -eq $domain) {
        Write-Info "AI Sherpa already installed for domain '$domain'. Re-running:"
        Write-Info "  - existing plugins will be UPDATED to latest"
        Write-Info "  - any new entries in plugins.json will be installed fresh"
        Write-Info "  - CLI tools will be upgraded"
    } else {
        Write-Info "AI Sherpa already installed for domain '$savedDomain'. Switching to '$domain'."
        Invoke-DomainSwitch -OldDomain $savedDomain -NewDomain $domain
    }
} else {
    Write-Info "AI Sherpa not installed yet — running fresh install for domain '$domain'."
}

# Register every declared marketplace + install plugins & skills for EVERY
# declared domain. Per the per-session-domain-selection design setup is
# domain-agnostic at install time: every marketplace and every domain's
# plugins are made available so the SessionStart hook can activate any
# project's chosen domain(s) without a re-install. $domain (chosen above)
# is retained as the initial default in state.json and for embedded
# toolchain detection below, but no longer gates what gets installed.
Register-Marketplaces
Install-CoreSkills
$pluginsCfg = $null
try { $pluginsCfg = Get-Content "$ScriptDir\plugins.json" -Raw | ConvertFrom-Json } catch {}
$disabledDomains = if ($pluginsCfg.disabled_domains) { @($pluginsCfg.disabled_domains) } else { @() }
if ($pluginsCfg -and $pluginsCfg.domains) {
    foreach ($d in @($pluginsCfg.domains.PSObject.Properties.Name)) {
        if ($disabledDomains -contains $d) { Write-Info "  [SKIP]   $d (disabled_domains)"; continue }
        Install-DomainSkills $d
        Install-Skills -Domain $d
    }
} else {
    Install-DomainSkills $domain
    Install-Skills -Domain $domain
}
Write-GlobalSettings
# Must run AFTER Write-GlobalSettings (which overwrites settings.json from the
# template). See Set-AllInstalledPluginsEnabled docstring + claude-code#20661.
Set-AllInstalledPluginsEnabled

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
    Enable-WindowsLongPaths
    Install-Tools -Domain $domain -Upgrade:$isReinstall
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
    Enable-WindowsLongPaths
    Install-Tools -Domain $domain -Upgrade:$isReinstall
    Write-AiSherpaState -Domain $domain
    $missing = Test-Installation $domain
    if ($missing.Count -gt 0) {
        Show-VerificationReport $missing
        Show-SkippedStepsReport
        Show-UserActionsReport
        Print-Summary $domain
        exit 1
    }
    Write-Info "All expected plugins verified in installed_plugins.json."
    Show-SkippedStepsReport
    Show-UserActionsReport
    Print-Summary $domain
}
} # end: if (-not $script:SourcedAsLibrary)
