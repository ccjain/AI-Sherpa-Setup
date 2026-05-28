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

# --- Plugin introspection ---
# Marketplaces not listed in plugins.json marketplaces[] but referenced by name
$BuiltinMarketplaceRepos = @{
    'claude-plugins-official' = 'anthropics/claude-plugins-official'
}

# Cache marketplace clones — many plugins share a marketplace.
# Maps name -> @{ Path = '...'; CloneFailed = $bool }
$script:MarketplaceClones = @{}

# PS 5.1's ConvertFrom-Json is case-insensitive on object keys and chokes when
# two keys differ only by case (e.g. ".c" vs ".C" in the official marketplace).
# JavaScriptSerializer preserves case. Returns hashtables, which still support
# $h.key dot-access in PS 5.1.
Add-Type -AssemblyName System.Web.Extensions
$script:JsonParser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:JsonParser.MaxJsonLength = 100MB
function ConvertFrom-JsonCaseSafe {
    param([string]$Text)
    return $script:JsonParser.DeserializeObject($Text)
}

function Get-MarketplaceRepo {
    param([string]$MarketplaceName)
    if ($config.marketplaces) {
        foreach ($m in $config.marketplaces) {
            if ($m.name -eq $MarketplaceName) { return $m.repo }
        }
    }
    if ($BuiltinMarketplaceRepos.ContainsKey($MarketplaceName)) {
        return $BuiltinMarketplaceRepos[$MarketplaceName]
    }
    return $null
}

function Get-MarketplaceClone {
    param([string]$MarketplaceName)
    if ($script:MarketplaceClones.ContainsKey($MarketplaceName)) {
        return $script:MarketplaceClones[$MarketplaceName]
    }
    $repo = Get-MarketplaceRepo $MarketplaceName
    if (-not $repo) {
        $script:MarketplaceClones[$MarketplaceName] = @{ Path = $null; Reason = 'no-repo-mapped' }
        return $script:MarketplaceClones[$MarketplaceName]
    }
    Write-Info "  Cloning marketplace $repo (for '$MarketplaceName')..."
    $tmp = Get-RepoClone $repo
    if (-not $tmp) {
        $script:MarketplaceClones[$MarketplaceName] = @{ Path = $null; Reason = 'clone-failed' }
    } else {
        $script:MarketplaceClones[$MarketplaceName] = @{ Path = $tmp; Reason = 'ok' }
    }
    return $script:MarketplaceClones[$MarketplaceName]
}

# Cache external-URL plugin clones too (e.g. claude-plugins-official is a
# meta marketplace where each plugin.source = { url, sha }).
$script:ExternalPluginClones = @{}

function Resolve-ExternalPluginClone {
    param([string]$Url, [string]$Sha)
    $key = "$Url@$Sha"
    if ($script:ExternalPluginClones.ContainsKey($key)) {
        return $script:ExternalPluginClones[$key]
    }
    $slug = ($Url -replace '[^A-Za-z0-9]+', '-').TrimStart('-').Substring(0, [Math]::Min(60, ($Url -replace '[^A-Za-z0-9]+', '-').TrimStart('-').Length))
    $tmp = Join-Path $env:TEMP "ai-sherpa-ext-$slug"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    # Try a shallow clone first; if a specific SHA is required, fall back to
    # a full clone + checkout. Most uses don't need exact-SHA depth.
    & git clone --depth 1 --quiet $Url $tmp
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        $script:ExternalPluginClones[$key] = $null
        return $null
    }
    $script:ExternalPluginClones[$key] = $tmp
    return $tmp
}

function Clear-ExternalPluginClones {
    foreach ($p in $script:ExternalPluginClones.Values) {
        if ($p -and (Test-Path $p)) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $script:ExternalPluginClones = @{}
}

# Returns @{ Skills = N; Status = 'ok'|... } describing a plugin's contents.
function Get-PluginSkillCount {
    param([string]$PluginName, [string]$MarketplaceName)
    $mp = Get-MarketplaceClone $MarketplaceName
    if (-not $mp.Path) { return @{ Skills = -1; Status = $mp.Reason } }
    $mpJson = Join-Path $mp.Path '.claude-plugin/marketplace.json'
    if (-not (Test-Path $mpJson)) { return @{ Skills = -1; Status = 'no-marketplace-json' } }
    try {
        $mpData = ConvertFrom-JsonCaseSafe (Get-Content $mpJson -Raw)
    } catch {
        return @{ Skills = -1; Status = 'parse-error' }
    }
    $plugins = $mpData['plugins']
    if (-not $plugins) { return @{ Skills = -1; Status = 'no-plugins-array' } }
    $found = $null
    foreach ($p in @($plugins)) {
        if ($p['name'] -eq $PluginName) { $found = $p; break }
    }
    if (-not $found) { return @{ Skills = -1; Status = 'plugin-not-found' } }

    # Resolve the plugin's source directory. Two shapes seen in the wild:
    #   1. source as a string => relative path inside the marketplace repo
    #   2. source as an object { source: "url"|"github", url: "...", sha: "..." }
    #      => external repo, must be cloned separately. This is how the
    #      official `claude-plugins-official` marketplace points at plugins.
    $source = $found['source']
    $srcDir = $null
    if (-not $source) {
        $srcDir = Join-Path $mp.Path "./plugins/$PluginName"
    } elseif ($source -is [string]) {
        $srcDir = Join-Path $mp.Path $source
    } elseif ($source['url']) {
        $extClone = Resolve-ExternalPluginClone $source['url'] $source['sha']
        if (-not $extClone) { return @{ Skills = -1; Status = 'external-clone-failed' } }
        $srcDir = $extClone
    } else {
        return @{ Skills = -1; Status = 'unknown-source-shape' }
    }

    if (-not (Test-Path $srcDir)) { return @{ Skills = -1; Status = 'no-source-dir' } }
    $count = (Get-ChildItem -Path $srcDir -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    return @{ Skills = $count; Status = 'ok' }
}

# Render the suffix appended to a plugin's bullet line.
function Format-PluginCount {
    param([string]$PluginName, [string]$MarketplaceName)
    $info = Get-PluginSkillCount $PluginName $MarketplaceName
    if ($info.Status -eq 'ok') {
        $n = $info.Skills
        $s = if ($n -eq 1) { 'skill' } else { 'skills' }
        return "$n $s"
    } else {
        return "skill count unavailable ($($info.Status))"
    }
}

# Clean up cached marketplace clones once the whole inventory has been built.
function Clear-MarketplaceClones {
    foreach ($entry in $script:MarketplaceClones.Values) {
        if ($entry.Path -and (Test-Path $entry.Path)) {
            Remove-Item $entry.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $script:MarketplaceClones = @{}
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
        $countLabel = Format-PluginCount $p.name $p.marketplace
        Append "- ``$($p.name)`` @ ``$($p.marketplace)`` - $countLabel"
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
            $countLabel = Format-PluginCount $p.name $p.marketplace
            Append "- ``$($p.name)`` @ ``$($p.marketplace)`` - $countLabel"
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

# Clean up cached clones (best-effort; ignore failures)
Clear-MarketplaceClones
Clear-ExternalPluginClones

Write-Info "Inventory written to: $OutputPath"
