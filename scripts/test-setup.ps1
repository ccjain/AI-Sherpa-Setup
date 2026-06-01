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
