#Requires -Version 5.1
<#
.SYNOPSIS
Generate docs/skills-inventory.md — a browsable list of every plugin and
skill that AI Sherpa would install per domain.

.DESCRIPTION
Walks plugins.json. For each entry under `skills.*`, shallow-clones the
source repo, opens every SKILL.md, and extracts the `name:` and
`description:` from frontmatter. For plugin entries, lists name +
marketplace (no introspection into plugin contents).

Re-run this script whenever plugins.json changes. Output is committed
to the repo so teammates can browse it on GitHub without cloning anything.

.PARAMETER OutputPath
Where to write the generated markdown. Defaults to docs/skills-inventory.md
under the repo root.

.EXAMPLE
.\scripts\generate-skills-inventory.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $RepoRoot "plugins.json"
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot "docs\skills-inventory.md" }

function Write-Info { param([string]$m) Write-Host "[inventory] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[inventory] $m" -ForegroundColor Yellow }

if (-not (Test-Path $ConfigFile)) {
    Write-Error "plugins.json not found at $ConfigFile"
    exit 1
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

# Parse a SKILL.md and return [pscustomobject]@{ Name; Description } or $null
function Read-SkillMd {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $content = Get-Content $Path -Raw -Encoding UTF8
    # Frontmatter is between the first two '---' lines
    $match = [regex]::Match($content, '(?s)^---\s*\r?\n(.*?)\r?\n---')
    if (-not $match.Success) { return $null }
    $front = $match.Groups[1].Value

    $name = $null; $desc = $null
    $current = $null
    foreach ($line in ($front -split "`r?`n")) {
        if ($line -match '^name:\s*(.+?)\s*$') {
            $name = $matches[1].Trim('"').Trim("'")
            $current = 'name'
        } elseif ($line -match '^description:\s*(.+?)\s*$') {
            $desc = $matches[1].Trim('"').Trim("'")
            $current = 'desc'
        } elseif ($line -match '^[a-zA-Z_-]+:') {
            $current = $null
        } elseif ($current -eq 'desc' -and $line -match '^\s+\S') {
            # Continuation of multi-line description (YAML folded/literal)
            $desc += ' ' + $line.Trim()
        }
    }
    if (-not $name) { return $null }
    if ($null -eq $desc) { $desc = '' }
    return [pscustomobject]@{ Name = $name; Description = $desc }
}

# Clone a repo at depth 1 and return the temp path. Caller must clean up.
function Get-RepoClone {
    param([string]$Repo)
    $slug = $Repo -replace '/', '-'
    $tmp = Join-Path $env:TEMP "ai-sherpa-inv-$slug"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    # Don't redirect stderr to PowerShell pipeline — in PS 5.1 it wraps each
    # line in NativeCommandError and trips $ErrorActionPreference="Stop".
    & git clone --depth 1 --quiet "https://github.com/$Repo" $tmp
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        return $null
    }
    return $tmp
}

# Resolve skill entries (skills.<key>) into a list of [Name; Description; SourceRepo; SourceSubpath]
function Resolve-SkillEntries {
    param($Entries)
    $results = @()
    foreach ($entry in @($Entries)) {
        $repo    = $entry.repo
        $subpath = if ($entry.subpath) { $entry.subpath } else { "skills" }
        if (-not $repo) { continue }
        Write-Info "  Cloning $repo..."
        $tmp = Get-RepoClone $repo
        if (-not $tmp) {
            Write-Warn "    clone failed - listing as [unavailable]"
            $results += [pscustomobject]@{
                Name        = "[clone failed]"
                Description = "git clone https://github.com/$repo failed at inventory time"
                Repo        = $repo
                Subpath     = $subpath
            }
            continue
        }
        try {
            $srcDir = Join-Path $tmp $subpath
            if (-not (Test-Path $srcDir)) {
                Write-Warn "    subpath '$subpath' not found in $repo"
                $results += [pscustomobject]@{
                    Name        = "[subpath missing]"
                    Description = "Subpath '$subpath' not present in $repo"
                    Repo        = $repo
                    Subpath     = $subpath
                }
                continue
            }
            # Find every SKILL.md (case-insensitive) anywhere under srcDir
            $skillFiles = Get-ChildItem -Path $srcDir -Filter "SKILL.md" -Recurse -File
            foreach ($f in $skillFiles | Sort-Object FullName) {
                $parsed = Read-SkillMd $f.FullName
                if ($parsed) {
                    $results += [pscustomobject]@{
                        Name        = $parsed.Name
                        Description = $parsed.Description
                        Repo        = $repo
                        Subpath     = $subpath
                    }
                }
            }
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        }
    }
    return $results
}

# --- Generate markdown ---
$sb = New-Object System.Text.StringBuilder

function Append { param([string]$line = "") $null = $sb.AppendLine($line) }

Append "# AI Sherpa - Skills & Plugins Inventory"
Append ""
Append "> Generated by ``scripts/generate-skills-inventory.ps1``. Do not edit by hand."
Append "> Re-run the script when ``plugins.json`` changes."
Append ""
Append "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC$([TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).Hours.ToString('+00;-00'))"
Append ""
Append "---"
Append ""

# Global section
Append "## Global (installed for every domain)"
Append ""

Append "### Plugins"
Append ""
if ($config.global -and @($config.global).Count -gt 0) {
    foreach ($p in $config.global) {
        Append "- ``$($p.name)`` @ ``$($p.marketplace)``"
    }
} else {
    Append "_(none)_"
}
Append ""

Append "### Skills"
Append ""
if ($config.skills -and $config.skills.global -and @($config.skills.global).Count -gt 0) {
    Write-Info "Resolving global skills..."
    $globalSkills = Resolve-SkillEntries $config.skills.global
    foreach ($repo in ($globalSkills | Group-Object Repo)) {
        Append "**From ``$($repo.Name)`` (subpath: ``$($repo.Group[0].Subpath)``):**"
        Append ""
        foreach ($s in $repo.Group) {
            Append "- ``$($s.Name)`` - $($s.Description)"
        }
        Append ""
    }
} else {
    Append "_(none)_"
}
Append ""

# Per-domain sections
$domainNames = @()
if ($config.domains)        { $domainNames += $config.domains.PSObject.Properties.Name }
if ($config.skills)         { $domainNames += $config.skills.PSObject.Properties.Name | Where-Object { $_ -ne 'global' } }
$domainNames = $domainNames | Sort-Object -Unique

foreach ($domain in $domainNames) {
    Append "## Domain: $domain"
    Append ""

    # Plugins for this domain
    Append "### Plugins"
    Append ""
    $domainPlugins = $null
    if ($config.domains -and $config.domains.PSObject.Properties[$domain]) {
        $domainPlugins = $config.domains.$domain
    }
    if ($domainPlugins -and @($domainPlugins).Count -gt 0) {
        foreach ($p in $domainPlugins) {
            Append "- ``$($p.name)`` @ ``$($p.marketplace)``"
        }
    } else {
        Append "_(none - domain relies on global plugins + CLAUDE.md rules)_"
    }
    Append ""

    # Skills for this domain
    Append "### Skills"
    Append ""
    $domainSkills = $null
    if ($config.skills -and $config.skills.PSObject.Properties[$domain]) {
        $domainSkills = $config.skills.$domain
    }
    if ($domainSkills -and @($domainSkills).Count -gt 0) {
        Write-Info "Resolving skills for domain: $domain..."
        $resolved = Resolve-SkillEntries $domainSkills
        $totalCount = @($resolved).Count
        $repoCount = @($resolved | Group-Object Repo).Count
        Append "**$totalCount skills from $repoCount repo(s):**"
        Append ""
        foreach ($repoGroup in ($resolved | Group-Object Repo)) {
            Append "**From ``$($repoGroup.Name)`` (subpath: ``$($repoGroup.Group[0].Subpath)``):**"
            Append ""
            foreach ($s in $repoGroup.Group) {
                Append "- ``$($s.Name)`` - $($s.Description)"
            }
            Append ""
        }
    } else {
        Append "_(none)_"
    }
    Append ""
}

# Write file
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sb.ToString() | Set-Content -Path $OutputPath -Encoding UTF8

Write-Info "Inventory written to: $OutputPath"
