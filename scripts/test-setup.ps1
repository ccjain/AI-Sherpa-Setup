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

# ----- Test: Install-GitHubReleaseTool surfaces API failure as ACTION REQUIRED -----
Write-Host "=== Test: Install-GitHubReleaseTool API failure (CASE C) ==="

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

Assert-True "CASE C: API failure -> Write-Action emitted" ($script:CapturedAction.Count -gt 0)
Assert-True "CASE C: API failure -> Add-UserAction collected" ($script:CapturedUserActions.Count -gt 0)
if ($script:CapturedUserActions.Count -gt 0) {
    Assert-Match "CASE C: UserAction Command mentions releases page" 'releases' $script:CapturedUserActions[0].Command
}

# ----- Test: Install-GitHubReleaseTool ACTION REQUIRED on missing platform asset -----
Write-Host "=== Test: Install-GitHubReleaseTool platform missing (CASE B) ==="

function Test-CommandExists { return $false }

# Return a successful manifest with one asset (but for a different platform)
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

# ----- Test: Install-GitHubReleaseTool CASE E (HTTP download fails) -----
Write-Host "=== Test: Install-GitHubReleaseTool download failure (CASE E) ==="

function Test-CommandExists { return $false }

$assetUrl = 'https://example.invalid/rtk.zip'
function Invoke-RestMethod {
    return [pscustomobject]@{
        assets = @([pscustomobject]@{ name = 'rtk-test.zip'; browser_download_url = $assetUrl })
    }
}

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
    Assert-Match "CASE E: UserAction Command contains asset URL" 'example\.invalid' $script:CapturedUserActions[0].Command
}


# ----- Test: Install-GitHubReleaseTool CASE G (binary missing from archive) -----
Write-Host "=== Test: Install-GitHubReleaseTool binary missing (CASE G) ==="

function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
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

# ----- Test: Install-GitHubReleaseTool happy path (CASE H) -----
Write-Host "=== Test: Install-GitHubReleaseTool happy path (CASE H) ==="

function Test-CommandExists { return $false }

$assetUrlH = 'https://example.invalid/rtk.zip'
function Invoke-RestMethod {
    return [pscustomobject]@{
        assets = @([pscustomobject]@{ name = 'rtk-test.zip'; browser_download_url = $assetUrlH })
    }
}

function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    $tmpDir = Split-Path -Parent $OutFile
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $stagingDir = Join-Path $tmpDir 'staging'
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    $binName = if ((Get-PlatformArchKey) -like 'windows-*') { 'rtk.exe' } else { 'rtk' }
    'fake-binary-contents' | Set-Content (Join-Path $stagingDir $binName)
    Compress-Archive -Path "$stagingDir\*" -DestinationPath $OutFile -Force
    Remove-Item $stagingDir -Recurse -Force
}

$script:CapturedInfo = @()
function Write-Info { param([string]$msg) $script:CapturedInfo += $msg }

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

try { Remove-Item $destDir -Recurse -Force } catch {}

# ----- Summary -----
Write-Host ""
Write-Host "Total: $($script:PASS) PASS / $($script:FAIL) FAIL"
exit $(if ($script:FAIL -gt 0) { 1 } else { 0 })
