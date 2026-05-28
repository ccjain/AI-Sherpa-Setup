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

# Helpers to construct GitHub URLs from a (repo, ref, path) tuple.
# Use 'HEAD' so links always resolve to the default branch (main or master).
function Get-GitHubTreeUrl {
    param([string]$Repo, [string]$Ref = 'HEAD', [string]$Path = '')
    $base = "https://github.com/$Repo"
    if (-not $Path) { return "$base/tree/$Ref" }
    $clean = $Path -replace '^\./', '' -replace '\\', '/' -replace '^/+', ''
    return "$base/tree/$Ref/$clean"
}
function Get-GitHubBlobUrl {
    param([string]$Repo, [string]$Ref = 'HEAD', [string]$Path = '')
    $base = "https://github.com/$Repo"
    $clean = $Path -replace '^\./', '' -replace '\\', '/' -replace '^/+', ''
    return "$base/blob/$Ref/$clean"
}

# Escape a string for safe inclusion as a markdown table cell.
function Escape-MdCell {
    param([string]$Text)
    if (-not $Text) { return '' }
    return ($Text -replace '\|', '\|' -replace '\r?\n', ' ').Trim()
}

# Returns @{ Status; Skills = @(@{Name; Description; Url}, ...); SourceUrl }
# Walks the plugin's source directory, parses each SKILL.md, and produces a
# GitHub URL for every skill plus a URL for the plugin's source dir.
function Get-PluginDetails {
    param([string]$PluginName, [string]$MarketplaceName)
    $mp = Get-MarketplaceClone $MarketplaceName
    if (-not $mp.Path) { return @{ Status = $mp.Reason; Skills = @(); SourceUrl = $null } }

    $mpJson = Join-Path $mp.Path '.claude-plugin/marketplace.json'
    if (-not (Test-Path $mpJson)) { return @{ Status = 'no-marketplace-json'; Skills = @(); SourceUrl = $null } }
    try {
        $mpData = ConvertFrom-JsonCaseSafe (Get-Content $mpJson -Raw)
    } catch {
        return @{ Status = 'parse-error'; Skills = @(); SourceUrl = $null }
    }
    $plugins = $mpData['plugins']
    if (-not $plugins) { return @{ Status = 'no-plugins-array'; Skills = @(); SourceUrl = $null } }
    $found = $null
    foreach ($p in @($plugins)) {
        if ($p['name'] -eq $PluginName) { $found = $p; break }
    }
    if (-not $found) { return @{ Status = 'plugin-not-found'; Skills = @(); SourceUrl = $null } }

    # Two source shapes (same as before):
    #   1. string => relative path inside the marketplace repo
    #   2. object { url, sha } => external repo, must be cloned separately
    $source = $found['source']
    $srcDir = $null
    $sourceUrl = $null
    $skillRepo = $null  # the repo to use when building per-skill URLs
    $skillRef  = 'HEAD'

    $mpRepo = Get-MarketplaceRepo $MarketplaceName
    $defaultSubpath = "plugins/$PluginName"

    if (-not $source) {
        $srcDir = Join-Path $mp.Path $defaultSubpath
        $sourceUrl = Get-GitHubTreeUrl -Repo $mpRepo -Path $defaultSubpath
        $skillRepo = $mpRepo
    } elseif ($source -is [string]) {
        $srcDir = Join-Path $mp.Path $source
        $sourceUrl = Get-GitHubTreeUrl -Repo $mpRepo -Path $source
        $skillRepo = $mpRepo
    } elseif ($source['url']) {
        $extClone = Resolve-ExternalPluginClone $source['url'] $source['sha']
        if (-not $extClone) { return @{ Status = 'external-clone-failed'; Skills = @(); SourceUrl = $null } }
        $srcDir = $extClone
        # Derive an owner/repo string from the external URL
        $extRepo = ($source['url'] -replace '\.git$', '' -replace '^https?://github\.com/', '')
        $skillRepo = $extRepo
        if ($source['sha']) { $skillRef = $source['sha'] }
        $sourceUrl = Get-GitHubTreeUrl -Repo $extRepo -Ref $skillRef
    } else {
        return @{ Status = 'unknown-source-shape'; Skills = @(); SourceUrl = $null }
    }

    if (-not (Test-Path $srcDir)) { return @{ Status = 'no-source-dir'; Skills = @(); SourceUrl = $sourceUrl } }

    $skills = @()
    $srcDirFull = (Get-Item $srcDir).FullName
    $skillFiles = Get-ChildItem -Path $srcDir -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $skillFiles | Sort-Object FullName) {
        $parsed = Read-SkillMd $f.FullName
        if (-not $parsed) { continue }
        # Build a path relative to either the plugin source dir (for in-marketplace
        # plugins) or the external clone root (for { url, sha } plugins).
        $relToSrc = $f.FullName.Substring($srcDirFull.Length).TrimStart('\','/')
        $pathForUrl = if ($source -is [string]) {
            (($source -replace '^\./', '') + '/' + ($relToSrc -replace '\\', '/'))
        } elseif (-not $source) {
            "$defaultSubpath/" + ($relToSrc -replace '\\', '/')
        } else {
            ($relToSrc -replace '\\', '/')
        }
        $url = Get-GitHubBlobUrl -Repo $skillRepo -Ref $skillRef -Path $pathForUrl
        $skills += [pscustomobject]@{
            Name        = $parsed.Name
            Description = $parsed.Description
            Url         = $url
        }
    }
    return @{ Status = 'ok'; Skills = $skills; SourceUrl = $sourceUrl }
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
            $srcDirFull = (Get-Item $srcDir).FullName
            $skillFiles = Get-ChildItem -Path $srcDir -Filter "SKILL.md" -Recurse -File
            foreach ($f in $skillFiles | Sort-Object FullName) {
                $parsed = Read-SkillMd $f.FullName
                if ($parsed) {
                    $relToSrc = $f.FullName.Substring($srcDirFull.Length).TrimStart('\','/')
                    $cleanSubpath = $subpath -replace '^\./', ''
                    $pathForUrl = if ($cleanSubpath -eq '.') {
                        ($relToSrc -replace '\\', '/')
                    } else {
                        "$cleanSubpath/" + ($relToSrc -replace '\\', '/')
                    }
                    $url = Get-GitHubBlobUrl -Repo $repo -Path $pathForUrl
                    $results += [pscustomobject]@{
                        Name        = $parsed.Name
                        Description = $parsed.Description
                        Repo        = $repo
                        Subpath     = $subpath
                        Url         = $url
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
Append "Each plugin entry below links to its source on GitHub. Expand the"
Append "**Skills inside** block to see every individual SKILL.md the plugin"
Append "ships, with a direct link to each file."
Append ""
Append '## How skills get invoked'
Append ''
Append 'Skills auto-activate based on the **description** Claude reads from'
Append "each SKILL.md frontmatter. There is no slash command for an"
Append "individual skill -- Claude matches the current task to the skill's"
Append 'description and loads the skill on its own. So the **Trigger /'
Append 'what it does** column below is the activation criterion: if your'
Append 'prompt mentions a matching topic, verb (e.g. audit, debug, review),'
Append 'or a phrase like "Use when..." that the skill description names,'
Append 'the skill kicks in.'
Append ''
Append "To force-load a skill that isn't auto-detecting, just name it in"
Append 'your prompt (e.g., "Use the board-bringup skill to ...").'
Append ''
Append "---"
Append ""

# --- helpers for table rendering ---
function Render-PluginsTable {
    param([array]$Plugins)
    if (-not $Plugins -or @($Plugins).Count -eq 0) {
        Append "_(none)_"
        return
    }

    # First pass: gather details for every plugin so we can render the
    # summary table and the per-plugin detail blocks below it.
    $rows = @()
    foreach ($p in $Plugins) {
        $info = Get-PluginDetails $p.name $p.marketplace
        $rows += [pscustomobject]@{
            Name        = $p.name
            Marketplace = $p.marketplace
            Info        = $info
        }
    }

    # Summary table
    Append "| Plugin | Marketplace | Skills | Source |"
    Append "|---|---|---|---|"
    foreach ($r in $rows) {
        $count = @($r.Info.Skills).Count
        $srcCell = if ($r.Info.SourceUrl) { "[link]($($r.Info.SourceUrl))" } else { "_unavailable_" }
        $countCell = if ($r.Info.Status -eq 'ok') { "$count" } else { "_$($r.Info.Status)_" }
        Append "| ``$($r.Name)`` | ``$($r.Marketplace)`` | $countCell | $srcCell |"
    }
    Append ""

    # Per-plugin skill detail (collapsible)
    foreach ($r in $rows) {
        $skills = @($r.Info.Skills)
        if ($skills.Count -eq 0) { continue }
        Append "<details><summary><strong>Skills inside <code>$($r.Name)</code></strong> ($($skills.Count))</summary>"
        Append ""
        Append "| Skill | Trigger / what it does | Source |"
        Append "|---|---|---|"
        foreach ($s in $skills) {
            $desc = Escape-MdCell $s.Description
            Append "| ``$($s.Name)`` | $desc | [SKILL.md]($($s.Url)) |"
        }
        Append ""
        Append "</details>"
        Append ""
    }
}

function Render-SkillsTable {
    param([array]$SkillEntries)
    if (-not $SkillEntries -or @($SkillEntries).Count -eq 0) {
        Append "_(none)_"
        return
    }

    Write-Info "Resolving skill entries..."
    $resolved = Resolve-SkillEntries $SkillEntries
    $resolved = @($resolved)
    if ($resolved.Count -eq 0) { Append "_(none)_"; return }

    $repoCount = @($resolved | Group-Object Repo).Count
    Append "**$($resolved.Count) skills from $repoCount repo(s):**"
    Append ""

    # Per-repo summary table
    Append "| Repo | Subpath | Skill count | Source |"
    Append "|---|---|---|---|"
    foreach ($g in ($resolved | Group-Object Repo)) {
        $subpath = $g.Group[0].Subpath
        $treeUrl = Get-GitHubTreeUrl -Repo $g.Name -Path $subpath
        Append "| ``$($g.Name)`` | ``$subpath`` | $(@($g.Group).Count) | [link]($treeUrl) |"
    }
    Append ""

    # Per-repo skill detail (collapsible)
    foreach ($g in ($resolved | Group-Object Repo)) {
        $skills = @($g.Group)
        Append "<details><summary><strong>Skills from <code>$($g.Name)</code></strong> ($($skills.Count))</summary>"
        Append ""
        Append "| Skill | Trigger / what it does | Source |"
        Append "|---|---|---|"
        foreach ($s in $skills) {
            $desc = Escape-MdCell $s.Description
            $srcCell = if ($s.Url) { "[SKILL.md]($($s.Url))" } else { '-' }
            Append "| ``$($s.Name)`` | $desc | $srcCell |"
        }
        Append ""
        Append "</details>"
        Append ""
    }
}

# Global section
Append "## Global (installed for every domain)"
Append ""

Append "### Plugins"
Append ""
Render-PluginsTable $config.global

Append "### Skills"
Append ""
if ($config.skills -and $config.skills.global) {
    Render-SkillsTable $config.skills.global
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

    Append "### Plugins"
    Append ""
    $domainPlugins = $null
    if ($config.domains -and $config.domains.PSObject.Properties[$domain]) {
        $domainPlugins = $config.domains.$domain
    }
    if ($domainPlugins -and @($domainPlugins).Count -gt 0) {
        Render-PluginsTable $domainPlugins
    } else {
        Append "_(none - domain relies on global plugins + CLAUDE.md rules)_"
        Append ""
    }

    Append "### Skills"
    Append ""
    $domainSkills = $null
    if ($config.skills -and $config.skills.PSObject.Properties[$domain]) {
        $domainSkills = $config.skills.$domain
    }
    if ($domainSkills -and @($domainSkills).Count -gt 0) {
        Render-SkillsTable $domainSkills
    } else {
        Append "_(none)_"
        Append ""
    }
}

# Write file
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sb.ToString() | Set-Content -Path $OutputPath -Encoding UTF8

# Clean up cached clones (best-effort; ignore failures)
Clear-MarketplaceClones
Clear-ExternalPluginClones

Write-Info "Inventory written to: $OutputPath"
