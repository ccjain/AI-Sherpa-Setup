# RTK GitHub-Release Installer — Design

**Status:** Draft, pending review
**Date:** 2026-06-02
**Owner:** AI Sherpa core
**Related files:** `plugins.json` (`tools.global[]` rtk entry), `setup.ps1`
(`Install-Tools` switch + new `Install-GitHubReleaseTool`), `setup.sh`
(`install_tools` + new `install_github_release_tool`)

---

## Summary

Switch `rtk` installation from `cargo install --git ...` to downloading the
pre-built binary from `rtk-ai/rtk` GitHub releases. Eliminates the MSVC
linker dependency that's been blocking installs on Windows machines without
Visual Studio Build Tools (today: CHJAIN; likely many others). ~5 MB
download + ~10 seconds, instead of a from-source compile that needs ~2-5 GB
of build tools.

Adds a new `source: "github-release"` value to `plugins.json`'s tool schema
and a matching `Install-GitHubReleaseTool` installer in both `setup.ps1` and
`setup.sh`. **Scope-limited to rtk only** — the schema and installer are
designed so adding future github-release tools is trivial, but no other
tools migrate as part of this change.

## Goal

For each setup run on Windows that needs to install `rtk`:

- No MSVC linker required, no Visual Studio Build Tools needed.
- Download the official upstream `rtk-x86_64-pc-windows-msvc.zip` from the
  latest GitHub release, extract `rtk.exe`, drop it on PATH at
  `~/.local/bin/rtk.exe`. Total time: ~10s.
- Equivalent behavior on Linux (musl tarball) and macOS (Intel + ARM
  tarballs).
- Skip entirely on re-runs if `rtk` is already on PATH (same gate as the
  `Install-PyPiTool` / `Install-CargoTool` fix in commit `ff03996`).
- Any failure surfaces as `[ACTION REQUIRED]` with the exact manual-download
  URL and steps. No silent skip, no noisy compiler error.

## Non-goals

- **No backwards-compatible cargo fallback.** The cargo path was failing on
  the affected user's machine; falling back to it would still fail with the
  same linker error. Surface a clear ACTION REQUIRED instead.
- **No generalization to a "github-release source" feature for arbitrary
  tools yet.** rtk is the only current consumer. If a second tool needs the
  pattern, the existing schema accommodates trivially — but we don't pre-
  ship infrastructure we don't have a second user for.
- **No VS Build Tools detection or auto-install.** Once rtk is off cargo,
  we have zero tools that need MSVC linker. If a future tool needs cargo,
  we'll deal with that then.
- **No Windows-ARM64 support.** Upstream rtk doesn't ship an ARM64 Windows
  asset; ARM64 users hit ACTION REQUIRED with manual instructions. (~0.5%
  of expected user base.)
- **No checksum / signature verification.** rtk's GitHub releases don't
  ship checksum files. We rely on GitHub's HTTPS for download integrity.
  Surface as a follow-up if/when upstream starts publishing checksums.

## Background — current behavior

`plugins.json` defines rtk in `tools.global[]`:

```json
{
  "name": "rtk",
  "source": "cargo",
  "git": "https://github.com/rtk-ai/rtk"
}
```

`Install-Tools` switches on `source: "cargo"` → `Install-CargoTool` →
`cargo install --git https://github.com/rtk-ai/rtk`. On Windows without
MSVC build tools (`link.exe`), the compile fails inside the `proc-macro2`
build script with:

```
error: linker `link.exe` not found
note: the msvc targets depend on the msvc linker
```

Setup catches the non-zero exit, adds rtk to the SkippedSteps report, and
continues. But:

1. The compile error output (proc-macro2, quote, serde_core failures) is
   alarming and doesn't tell the user how to fix it.
2. The fix the user actually needs (install VS Build Tools) is 2-5 GB and
   takes 10-30 minutes — disproportionate for a single CLI tool.
3. **rtk-ai/rtk's own README recommends downloading pre-built binaries on
   Windows**, not compiling from source.

We're doing the slow + failure-prone thing on every Windows machine when
upstream provides the fast + reliable option.

## Architecture

### Schema change in `plugins.json`

The rtk entry in `tools.global[]` changes from:

```json
{
  "name": "rtk",
  "source": "cargo",
  "git": "https://github.com/rtk-ai/rtk"
}
```

to:

```json
{
  "name": "rtk",
  "source": "github-release",
  "repo": "rtk-ai/rtk",
  "asset": {
    "windows-x64": "rtk-x86_64-pc-windows-msvc.zip",
    "linux-x64":   "rtk-x86_64-unknown-linux-musl.tar.gz",
    "macos-x64":   "rtk-x86_64-apple-darwin.tar.gz",
    "macos-arm64": "rtk-aarch64-apple-darwin.tar.gz"
  },
  "binary": "rtk",
  "destination": "~/.local/bin"
}
```

Field semantics (used by the new installer):

- `source: "github-release"` — routes to `Install-GitHubReleaseTool` instead
  of `Install-CargoTool`.
- `repo` — `<owner>/<name>` slug; appended to
  `https://api.github.com/repos/<repo>/releases/latest` to fetch the release
  manifest.
- `asset` — map of platform-arch key → asset filename to look for in the
  release's `assets[]`. Key format: `<os>-<arch>` (lowercase). If the
  current platform-arch isn't a key, surface ACTION REQUIRED.
- `binary` — name of the binary inside the archive (without `.exe`). On
  Windows the installer appends `.exe` automatically; on Unix it doesn't.
- `destination` — directory the binary is moved into. `~` is expanded.

### Two new installer functions

**`Install-GitHubReleaseTool` (PowerShell)** — `setup.ps1`. Called from
`Install-Tools`'s switch on `'github-release'`. Pseudocode:

```
function Install-GitHubReleaseTool {
    param($Entry)  # the plugins.json tool object

    # 1. Skip-if-installed gate (matches existing PyPI/cargo pattern)
    if (-not $Upgrade -and (Test-CommandExists $Entry.name)) {
        Write-Info "  [SKIP]   $($Entry.name) already installed at ..."
        return
    }

    # 2. Resolve platform key
    $platformKey = Get-PlatformArchKey  # "windows-x64", "linux-x64", etc.
    $assetName   = $Entry.asset.$platformKey
    if (-not $assetName) {
        # No asset for this platform → ACTION REQUIRED
        return
    }

    # 3. Query GitHub releases/latest, find asset.browser_download_url
    $manifest = Invoke-RestMethod "https://api.github.com/repos/$($Entry.repo)/releases/latest"
    $asset = $manifest.assets | Where-Object name -eq $assetName
    if (-not $asset) {
        # Asset name not in latest release → ACTION REQUIRED with the
        # actual asset names from the manifest
        return
    }

    # 4. Download to temp, extract, move binary to destination
    $tmpDir   = New-TempDir
    $download = Join-Path $tmpDir $assetName
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $download

    if ($assetName -like '*.zip')    { Expand-Archive $download $tmpDir }
    elseif ($assetName -like '*.tar.gz') { tar -xzf $download -C $tmpDir }

    $binFile = if ($IsWindows) { "$($Entry.binary).exe" } else { $Entry.binary }
    $found = Get-ChildItem -Recurse -Filter $binFile $tmpDir | Select-Object -First 1
    if (-not $found) {
        # Binary not in archive → ACTION REQUIRED
        return
    }

    $destDir = Resolve-DestinationPath $Entry.destination
    New-Item -Type Directory -Path $destDir -Force | Out-Null
    Move-Item $found.FullName (Join-Path $destDir $binFile) -Force
    Add-WindowsUserPath $destDir   # adds destDir to PATH if not already on it

    Remove-Item $tmpDir -Recurse -Force
    Write-Info "  [READY]  $($Entry.name) installed to $destDir\$binFile"
}
```

**`install_github_release_tool` (Bash)** — `setup.sh`. Same logic via
`curl` + `node -e` (for JSON parsing) + `unzip`/`tar`.

### Platform-arch detection

A small new helper in each script. Returns one of `windows-x64`,
`windows-arm64`, `linux-x64`, `linux-arm64`, `macos-x64`, `macos-arm64`.

```powershell
function Get-PlatformArchKey {
    $os = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } else { 'macos' }
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    $arch = switch ($arch) { 'x64' { 'x64' } 'arm64' { 'arm64' } default { 'x64' } }
    return "$os-$arch"
}
```

Bash equivalent reads `OSTYPE` and `uname -m`.

## Decision flow

```
Install-GitHubReleaseTool(Entry, Upgrade)
│
├─ CASE A: Entry.name binary on PATH AND not Upgrade
│   └─ "[SKIP]   <name> already installed at <path> (run setup.bat --update to upgrade)"
│   └─ return
│
├─ Platform key = Get-PlatformArchKey
├─ assetName = Entry.asset[platformKey]
│
├─ CASE B: assetName missing for this platform
│   └─ Write-Action "<name>: no pre-built asset for <platform>"
│   └─ Add-UserAction "Manually install <name>"
│       │ Why: rtk doesn't ship a binary for <platform>. You can build from
│       │      source via `cargo install --git <repo>` (needs Rust + native
│       │      build tools on this platform).
│       └ Command: cargo install --git https://github.com/rtk-ai/rtk
│   └─ return
│
├─ manifest = GitHub API /releases/latest for Entry.repo
│
├─ CASE C: API query fails (network, 403 rate limit, 5xx)
│   └─ Write-Action "<name> download failed: GitHub API returned <status>"
│   └─ Add-UserAction with manual URL
│   └─ return
│
├─ asset = first entry in manifest.assets matching assetName
│
├─ CASE D: asset name not in latest release (upstream rename, removal)
│   └─ Write-Action "<name>: expected asset '<assetName>' not in latest release"
│   └─ Add-UserAction listing the actual asset names from the manifest
│   └─ return
│
├─ Download asset.browser_download_url to temp
│
├─ CASE E: HTTP download fails
│   └─ Write-Action "<name> download failed: <status>"
│   └─ Add-UserAction with browser_download_url for manual download
│   └─ return
│
├─ Extract archive (zip or tar.gz)
│
├─ CASE F: extraction fails (corrupt archive, no unzip/tar)
│   └─ Write-Action "<name>: could not extract archive"
│   └─ Add-UserAction with downloaded file path
│   └─ return
│
├─ Find binary inside extracted tree
│
├─ CASE G: binary not in archive (upstream rename)
│   └─ Write-Action "<name>: archive didn't contain '<binary>'"
│   └─ Add-UserAction with extracted dir path so user can find binary manually
│   └─ return
│
└─ CASE H: success
    └─ Move binary to destination, add destination to PATH
    └─ Write-Info "  [READY]  <name> installed to <destination>"
    └─ return
```

## Data flow

```
plugins.json
    │ tools.global[] with source: "github-release"
    ▼
Install-Tools (existing switch)
    │ source == "github-release"
    ▼
Install-GitHubReleaseTool
    ├─ Get-PlatformArchKey ─→ "windows-x64"
    ├─ Entry.asset[platformKey] ─→ "rtk-x86_64-pc-windows-msvc.zip"
    ▼
GitHub API: /repos/rtk-ai/rtk/releases/latest
    │ HTTPS, 1 request, ~200ms
    ▼
manifest.assets[name == "rtk-...zip"].browser_download_url
    │ HTTPS, ~5 MB
    ▼
$env:TEMP/rtk-install-xxx/
    ├─ rtk-x86_64-pc-windows-msvc.zip   (download)
    └─ rtk.exe                          (after Expand-Archive)
    │ Move-Item
    ▼
~/.local/bin/rtk.exe
    │ Add-WindowsUserPath
    ▼
$env:Path now includes ~/.local/bin
```

## Error handling

| Condition | Behavior | Why |
|---|---|---|
| Platform-arch not in `asset` map | `[ACTION REQUIRED]` with `cargo install --git` as manual alternative | We don't pretend to handle every platform; user gets one clear path forward. |
| GitHub API rate-limited (HTTP 403, header `X-RateLimit-Remaining: 0`) | `[ACTION REQUIRED]` with manual `browser_download_url` from the API error message if available, or generic releases page URL | 60 req/hour unauth limit is enough for normal use; corporate networks proxying GitHub may compound. |
| GitHub API 5xx / network failure | `[ACTION REQUIRED]` with manual releases page URL | Generic graceful degradation. |
| Asset name mismatch (404) | `[ACTION REQUIRED]` listing actual asset names from manifest | Upstream rename → admin should update `plugins.json`. |
| Zip / tarball corrupt | `[ACTION REQUIRED]` with downloaded file path | Rare. User can re-download. |
| `tar` / `unzip` not installed | Fallback to `Expand-Archive` (PS) / `python -c "import zipfile,..."` (Bash where available). If neither works → ACTION REQUIRED with extraction instructions. | Both are usually present, but old Win/Linux installs may lack them. |
| Binary missing from archive | `[ACTION REQUIRED]` with extracted dir path so user can locate manually | Upstream restructure → admin should update `plugins.json` `binary` field. |
| `destination` directory unwritable | `[ACTION REQUIRED]` with manual move command | Rare; usually a privilege issue. |

**Graceful-degradation invariant:** every failure mode results in an
`[ACTION REQUIRED]` with a copy-pasteable remediation. Setup continues to
install other tools regardless — `rtk` failure never blocks the rest of
the install.

## Testing

### Unit (PowerShell)

| Test | Setup | Expected |
|---|---|---|
| Skip-if-installed | Mock `Test-CommandExists rtk` → true, no -Upgrade | Logs SKIP, no network call |
| Platform missing | Set platform-key returning "freebsd-x64" (not in asset map) | Write-Action emitted, Add-UserAction collected, no network call |
| Happy path | Mock GitHub API + download succeed, archive contains binary | Binary at destination, PATH updated, Write-Info READY emitted |
| API rate limit | Mock API returns 403 with rate limit headers | Write-Action emitted, Add-UserAction with manual URL |
| Asset rename | Mock API returns manifest without expected asset name | Write-Action emitted, manifest's actual asset names listed in user action |
| Binary missing from archive | Mock archive extraction produces unexpected files | Write-Action emitted, Add-UserAction with extracted dir path |

### Unit (Bash)

Mirror the six scenarios using function overrides for `curl` and
`unzip` / `tar`. Extend `scripts/test-setup.sh`.

### Manual smoke

- Fresh Windows VM without VS Build Tools → run `setup.bat` → rtk installs
  cleanly from binary, no linker error. Verify `rtk --version` works.
- Same VM, immediate re-run → rtk shows `[SKIP]` line, no network call.
- Disconnect network mid-install → API fails → ACTION REQUIRED appears in
  end-of-run report with manual URL.
- Edit `plugins.json` to set a bogus asset name → re-run → ACTION REQUIRED
  lists the real available asset names.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Upstream rtk renames release assets | Low | Low — fails loudly, ACTION REQUIRED tells admin to update plugins.json | The asset-mismatch error message includes the actual asset names so the fix is one edit. |
| GitHub API rate limit hits during heavy testing | Medium | Low — ACTION REQUIRED with manual download URL | Real users hit setup once or twice; not a real-world rate-limit concern. Could add `Authorization: Bearer <PAT>` later if needed. |
| rtk binary depends on a runtime DLL (VC++ Redistributable) that's missing | Low | Medium — `rtk.exe` would fail to launch | Upstream binary is built with `-pc-windows-msvc` so VC++ Redist may be needed. Test on clean VM to confirm; if needed, add a follow-up to install VC++ Redist via winget (much smaller than Build Tools). |
| Destination dir not on PATH after install | Low | Medium — `rtk` won't be findable | `Add-WindowsUserPath` (PS) and the equivalent PATH-fix (Bash) are existing helpers; same pattern as `Install-PyPiTool`. |
| Schema change in `plugins.json` confuses contributors | Low | Low | One new `source` value documented in `docs/admin-guide.md`. |

## Acceptance criteria

This spec is implemented when:

1. `plugins.json`'s rtk entry uses `source: "github-release"` with the asset
   map shown in §Architecture.
2. `setup.ps1` has an `Install-GitHubReleaseTool` function that implements
   the decision flow (§Decision Flow Cases A through H).
3. `setup.sh` has the equivalent `install_github_release_tool` function.
4. Both scripts' `Install-Tools` / `install_tools` switch routes
   `source: "github-release"` entries to the new installer.
5. On a Windows machine without VS Build Tools, `setup.bat` installs rtk
   successfully via the binary path. No `link.exe not found` error appears.
6. On a re-run, rtk shows `[SKIP]   rtk already installed at <path>`.
7. Failure paths (rate limit, asset rename, missing binary in archive) all
   produce `[ACTION REQUIRED]` entries in the end-of-run report with
   copy-pasteable remediation.
8. `docs/admin-guide.md` documents the new `source: "github-release"` value
   and its fields.

## Open questions

Three deferred to implementation discretion:

- **Whether to pin rtk to a specific release tag rather than `latest`.**
  Spec uses `releases/latest` for forward-compatibility. If a future
  upstream release breaks AI Sherpa, admin can switch the API URL to
  `releases/tags/v<X>` in the installer. Not pinning now — YAGNI.
- **Whether to verify checksums.** rtk doesn't publish checksums. If they
  start (e.g. via `cargo-dist`), add SHA-256 verification as a follow-up.
- **Where to install on Linux/macOS.** Spec uses `~/.local/bin` (matches
  what `uv tool install` does). If a future tool wants `/usr/local/bin`,
  the `destination` field already supports that.
