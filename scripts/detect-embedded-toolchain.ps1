#Requires -Version 5.1
# Detects embedded toolchains, flashers, debuggers on Windows.
# Writes findings to <target>\.claude\embedded-toolchain.json
# Prompts user for any missing critical tool (toolchain + default flasher).
#
# Usage:
#   detect-embedded-toolchain.ps1 -TargetHome "C:\Users\Admin"
#
# In hybrid mode the WSL setup.sh calls this with TargetHome pointing at the
# Windows user's home (the same dir the rest of setup writes config into).

param(
    [Parameter(Mandatory=$true)][string]$TargetHome
)
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$m) Write-Host "[detect-toolchain] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[detect-toolchain] $m" -ForegroundColor Yellow }

# --- detection helpers ---

function Find-PathOnPath {
    param([string]$Exe)
    $c = Get-Command $Exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source } else { return $null }
}

function Find-FirstDir {
    param([string]$Parent, [string]$Filter)
    if (-not (Test-Path $Parent)) { return $null }
    return Get-ChildItem $Parent -Directory -Filter $Filter -ErrorAction SilentlyContinue |
           Sort-Object Name -Descending | Select-Object -First 1
}

# --- detection: toolchains ---

function Detect-ArmGcc {
    # Standalone installer
    $d = Find-FirstDir "C:\Program Files (x86)\GNU Arm Embedded Toolchain" "*"
    if ($d) {
        $bin = Join-Path $d.FullName "bin"
        if (Test-Path "$bin\arm-none-eabi-gcc.exe") { return $bin }
    }
    # PATH fallback
    $gcc = Find-PathOnPath "arm-none-eabi-gcc"
    if ($gcc) { return (Split-Path $gcc -Parent) }
    return $null
}

function Detect-ZephyrSdk {
    foreach ($base in @("C:\", $env:USERPROFILE)) {
        $d = Find-FirstDir $base "zephyr-sdk-*"
        if ($d) { return $d.FullName }
    }
    if ($env:ZEPHYR_SDK_INSTALL_DIR -and (Test-Path $env:ZEPHYR_SDK_INSTALL_DIR)) {
        return $env:ZEPHYR_SDK_INSTALL_DIR
    }
    return $null
}

function Detect-Iar {
    $d = Find-FirstDir "C:\Program Files\IAR Systems" "Embedded Workbench*"
    if ($d) { return $d.FullName }
    $d = Find-FirstDir "C:\Program Files (x86)\IAR Systems" "Embedded Workbench*"
    if ($d) { return $d.FullName }
    return $null
}

function Detect-Keil {
    if (Test-Path "C:\Keil_v5") { return "C:\Keil_v5" }
    if (Test-Path "C:\Keil")    { return "C:\Keil" }
    return $null
}

function Detect-Mplab {
    $d = Find-FirstDir "C:\Program Files\Microchip\MPLABX" "*"
    if ($d) { return $d.FullName }
    $d = Find-FirstDir "C:\Program Files (x86)\Microchip\MPLABX" "*"
    if ($d) { return $d.FullName }
    return $null
}

function Detect-Xc {
    param([string]$Variant)  # xc8, xc16, xc32
    $d = Find-FirstDir "C:\Program Files\Microchip\$Variant" "v*"
    if ($d) { return $d.FullName }
    return $null
}

# --- detection: flashers ---

function Detect-Jlink {
    $d = Find-FirstDir "C:\Program Files\SEGGER" "JLink_V*"
    if ($d) {
        $exe = Join-Path $d.FullName "JLink.exe"
        if (Test-Path $exe) { return @{ exe = $exe; dir = $d.FullName } }
        $exe = Join-Path $d.FullName "JLinkExe.exe"
        if (Test-Path $exe) { return @{ exe = $exe; dir = $d.FullName } }
    }
    return $null
}

function Detect-Stm32CubeProg {
    $p = "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    if (Test-Path $p) { return $p }
    $p = "C:\Program Files\STMicroelectronics\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe"
    if (Test-Path $p) { return $p }
    return $null
}

function Detect-Nrfjprog {
    $p = "C:\Program Files\Nordic Semiconductor\nrf-command-line-tools\bin\nrfjprog.exe"
    if (Test-Path $p) { return $p }
    return Find-PathOnPath "nrfjprog"
}

function Detect-Pyocd {
    return Find-PathOnPath "pyocd"
}

function Detect-OpenOCD {
    param([string]$ZephyrSdk)
    if ($ZephyrSdk) {
        $cand = Join-Path $ZephyrSdk "openocd\bin\openocd.exe"
        if (Test-Path $cand) { return $cand }
    }
    return Find-PathOnPath "openocd"
}

# --- main ---

Write-Info "Probing Windows for embedded toolchains, flashers, debuggers..."

$result = [ordered]@{
    toolchains = [ordered]@{}
    flashers   = [ordered]@{}
    debuggers  = [ordered]@{}
    detected_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    platform   = "windows"
}

# Toolchains
$armGcc = Detect-ArmGcc
$result.toolchains["arm-gcc"]    = $armGcc
$result.toolchains["zephyr-sdk"] = Detect-ZephyrSdk
$result.toolchains["iar"]        = Detect-Iar
$result.toolchains["keil-mdk"]   = Detect-Keil
$result.toolchains["mplab-x"]    = Detect-Mplab
$result.toolchains["xc8"]        = Detect-Xc "xc8"
$result.toolchains["xc16"]       = Detect-Xc "xc16"
$result.toolchains["xc32"]       = Detect-Xc "xc32"

# Debuggers (gdb usually ships with ARM GCC)
if ($armGcc) {
    $gdb = Join-Path $armGcc "arm-none-eabi-gdb.exe"
    if (Test-Path $gdb) { $result.debuggers["arm-gdb"] = $gdb }
}

# Flashers
$jlink = Detect-Jlink
if ($jlink) {
    $result.flashers["jlink"] = $jlink.exe
    $gdbsrv = Join-Path $jlink.dir "JLinkGDBServerCL.exe"
    if (Test-Path $gdbsrv) { $result.debuggers["jlink-gdbserver"] = $gdbsrv }
}
$result.flashers["stm32cubeprog"] = Detect-Stm32CubeProg
$result.flashers["nrfjprog"]      = Detect-Nrfjprog
$result.flashers["pyocd"]         = Detect-Pyocd
$result.flashers["openocd"]       = Detect-OpenOCD $result.toolchains["zephyr-sdk"]

# Report findings
Write-Host ""
Write-Info "Detection results:"
foreach ($cat in @("toolchains","flashers","debuggers")) {
    Write-Host ""
    Write-Host "  $cat" -ForegroundColor Cyan
    foreach ($k in $result[$cat].Keys) {
        $v = $result[$cat][$k]
        if ($v) {
            Write-Host "    [OK]   $k -> $v" -ForegroundColor Green
        } else {
            Write-Host "    [miss] $k" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# --- prompt for critical missing tools ---
# Critical = at least one usable toolchain + at least one flasher.

function Test-AnyValueSet {
    param([System.Collections.Specialized.OrderedDictionary]$Map)
    foreach ($k in $Map.Keys) { if ($Map[$k]) { return $true } }
    return $false
}

function Test-Interactive {
    # Returns $false when stdin is piped/redirected (CI, scripted) so we skip
    # Read-Host calls that would otherwise throw "NonInteractive mode" errors.
    try { return -not [Console]::IsInputRedirected } catch { return $false }
}

function Read-MissingToolPath {
    param([string]$Label, [string]$Prompt)
    if (-not (Test-Interactive)) {
        Write-Warn "$Label not detected and shell is non-interactive — skipping prompt."
        Write-Warn "  Add the path manually to ~/.claude/embedded-toolchain.json once installed."
        return $null
    }
    $p = Read-Host $Prompt
    if (-not $p -or $p -eq "skip") { return $null }
    if (-not (Test-Path $p)) {
        Write-Warn "Path not found: $p — skipping."
        return $null
    }
    return $p
}

$haveToolchain = Test-AnyValueSet $result.toolchains
$haveFlasher   = Test-AnyValueSet $result.flashers

if (-not $haveToolchain) {
    Write-Warn "No build toolchain detected (ARM GCC, Zephyr SDK, IAR, Keil, MPLAB, XC)."
    $p = Read-MissingToolPath "build toolchain" "Enter path to your build toolchain's bin/ directory (or 'skip')"
    if ($p) {
        $result.toolchains["custom"] = $p
        Write-Info "Recorded custom toolchain at $p"
    } else {
        Write-Warn "No toolchain recorded. Claude will ask you per-session when needed."
    }
}

if (-not $haveFlasher) {
    Write-Warn "No flasher detected (J-Link, STM32CubeProg, nrfjprog, pyOCD, OpenOCD)."
    $p = Read-MissingToolPath "flasher" "Enter path to your default flasher executable (or 'skip')"
    if ($p) {
        $result.flashers["custom"] = $p
        Write-Info "Recorded custom flasher at $p"
    } else {
        Write-Warn "No flasher recorded. Claude will ask you per-session when needed."
    }
}

# --- write JSON ---

$outDir  = Join-Path $TargetHome ".claude"
$outFile = Join-Path $outDir "embedded-toolchain.json"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding utf8
Write-Info "Wrote $outFile"
