# Changelog

All notable changes to AI Sherpa are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the project is in `0.x`, minor bumps may contain breaking changes — they
will be called out under **Breaking** in the relevant entry.

## [Unreleased]

## [0.5.0] - 2026-06-05

Setup is now domain-agnostic, globally-installed only, and substantially
more robust on Windows. Project-level setup mode has been removed.

### Breaking

- **Removed project-level setup mode.** `setup.ps1` / `setup.sh` no longer
  sniff the current working directory to decide between "user-level" and
  "project-level" install. Setup always configures `~/.claude` globally.
  The `C:\Windows\System32` footgun (where running setup from an elevated
  shell would write a project `.claude/` into a system folder) is gone.
  See `docs/superpowers/specs/2026-06-05-drop-project-level-setup-mode.md`.
- Removed helpers `Write-ProjectSettings` / `Copy-ClaudeMd` (PS) and
  `write_project_settings` / `copy_claude_md` (bash) along with their tests.

### Added

- **GitHub-release tool installer.** New `Install-GitHubReleaseTool` flow in
  `setup.ps1` with platform-arch detection, manifest fetch, asset selection,
  download + extract, and skip-if-installed. Plugins can now declare
  `source: github-release` in `plugins.json` and bypass cargo/PyPI entirely.
  `rtk` switched to install via this path.
- **Bun auto-install** as a prerequisite (required by `claude-mem` runtime).
- **`superpowers:brainstorming` auto-fires** via a `UserPromptSubmit` hook
  shipped by setup — feature/build-intent prompts now reliably trigger the
  brainstorm gate without depending on the model noticing.
- **`disabled_domains` in `plugins.json`** lets teams skip business-only
  marketplaces during install.
- **PS test harness** for the platform-arch detection helpers.
- Every plugin is now explicitly activated after install/update, instead of
  relying on Claude Code's implicit enable.
- All declared domains' plugins and marketplaces are installed, not only
  the domain the user selected at prompt time.

### Changed

- The interactive domain prompt is commented out — install is fully
  domain-agnostic now.
- Plugin git clone timeout bumped to **15 minutes** to survive slow corporate
  networks on first marketplace install.
- Banner / install messages reworded to match the new global-only flow.

### Fixed

- **Windows MSI mutex (1618) retry** for `winget` prerequisite installs —
  unblocks setup on machines with active Windows Update / AV agents.
- **EBUSY retries** on marketplace add and plugin install (Windows file-lock
  race on first `git clone`).
- **PowerShell 5.1 native-command stderr trap** no longer swallows real errors
  from `claude marketplace update` / `claude plugin enable`; failures now
  surface their real cause.
- **`settings.json` UTF-8 BOM** bug — file is now written without BOM so
  Claude Code parses it correctly.
- **CLAUDE.md merge** now reads source files as UTF-8 (was misreading
  non-ASCII content under the default PS encoding).
- **`rtk init` wiring** is correct on first setup.
- **Python upfront-prereq + PATH races** in the one-pass installer — Python
  is now resolved before any tool that depends on it.
- **Plugin lifecycle** correctness:
  - `claude plugin enable` is called against the v2 `installed_plugins`
    schema, not the old shape.
  - We write `enabledPlugins` ourselves (workaround for
    [claude-code#20661](https://github.com/anthropics/claude-code/issues/20661)).
  - "Already enabled" is treated as success.
  - Setup re-runs skip already-installed PyPI / cargo tools.
  - Non-user-scope entries are ignored when probing installed plugins.
- `claude-plugins-official` marketplace is now explicitly declared; the
  broken "builtin marketplace" path was removed.

### Removed

- Project-level CWD-sniffing dual-mode dispatch (see **Breaking**).
- Cross-AI-tool MCP integration files (Cursor / Windsurf / Qoder / Gemini /
  OpenCode) — AI Sherpa is Claude-Code-only.
- Stale `How Setup Works` flow and Graphify references from `AGENTS.md`.
- Stale user-guide troubleshooting row referencing the removed user-level log.

## [0.4.0] - 2026-05-27

- `setup.ps1` and `setup.sh` read the plugin list from `plugins.json` — single
  source of truth for the installed plugin set.
- `plugins.json` config file introduced with design + implementation plan in
  `docs/superpowers/`.

## [0.3.0] - 2026-05-27

Documentation pack:

- Developer quick start guide.
- Windows step-by-step setup guide.
- Troubleshooting guide.
- Domain do's-and-don'ts reference card.
- Feedback submission guide.

## [0.2.0] - 2026-05-27

- `setup.bat` Windows thin launcher with folder picker and double-click flow.
- `setup.ps1` Windows PowerShell implementation of the full installer.
- `setup.sh` main flow: prerequisites, domain selection, skill installation.

## [0.1.0] - 2026-05-26

Initial release.

- Global `CLAUDE.md` with pre-flight check and universal rules.
- Per-domain `CLAUDE.md` for embedded, web/frontend, backend (Node/Python),
  data science, and devops.
- Project `CLAUDE.md` template.
- Secrets protection settings template.
- Repository scaffold + CODEOWNERS.

[Unreleased]: https://github.com/ccjain/AI-Sherpa-Setup/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/ccjain/AI-Sherpa-Setup/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ccjain/AI-Sherpa-Setup/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ccjain/AI-Sherpa-Setup/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ccjain/AI-Sherpa-Setup/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ccjain/AI-Sherpa-Setup/releases/tag/v0.1.0
