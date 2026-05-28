# AI Sherpa — Admin Guide

How to add, remove, or replace plugins and skills in AI Sherpa. This is the
companion to [user-guide.md](user-guide.md), which covers the end-user side
(running setup, picking a domain, invoking what's installed).

**Audience:** the person curating `plugins.json` for the team.

---

## 1. The four sections of `plugins.json`

`plugins.json` at the repo root is the single source of truth. The setup
scripts (`setup.ps1`, `setup.sh`) read it; the inventory generator
(`scripts/generate-skills-inventory.ps1`) reads it; nothing else does.

```json
{
  "marketplaces": [ ... ],
  "global":       [ ... ],
  "domains":      { "<name>": [ ... ], ... },
  "skills":       { "<name>": [ ... ], ... }
}
```

| Section | Holds | Reached when |
|---|---|---|
| `marketplaces[]` | Declarations of which Claude Code marketplaces exist | Auto-registered if any selected plugin references them |
| `global[]` | Marketplace plugins installed for **every** domain | Always |
| `domains.<x>[]` | Marketplace plugins for domain `<x>` only | When user picks domain `<x>` |
| `skills.<x>[]` | Raw-skills repos for domain `<x>` (or `global`) | When user picks domain `<x>` (or always for `global`) |

**Plugins** ship through a Claude Code marketplace (versioned, installed via
`claude plugin install`). **Skills** are raw `SKILL.md` files copied from a
GitHub repo into `~/.claude/skills/` by the setup script.

---

## 2. Adding a marketplace plugin

### Case A — marketplace is already declared

If the plugin's marketplace already appears in `marketplaces[]` (check by
name), you only edit one section.

**Example:** add `playwright` (which ships in `claude-plugins-official`) to
the web domain.

```json
"domains": {
  "web": [
    { "name": "figma",           "marketplace": "claude-plugins-official" },
    { "name": "frontend-design", "marketplace": "claude-plugins-official" },
    { "name": "vercel",          "marketplace": "claude-plugins-official" },
    { "name": "playwright",      "marketplace": "claude-plugins-official" }
  ]
}
```

Done. The marketplace name `claude-plugins-official` is already known to
the setup script.

### Case B — marketplace is new

You also need to declare the marketplace itself, naming the GitHub repo
that backs it.

**Example (real history):** when we added the antigravity systems-programming
bundle, we did this in two steps:

```json
// Step 1 — add the marketplace
"marketplaces": [
  { "repo": "anthropics/knowledge-work-plugins",  "name": "knowledge-work-plugins"        },
  { "repo": "anthropics/financial-services",      "name": "claude-for-financial-services" },
  { "repo": "jeffallan/claude-skills",            "name": "fullstack-dev-skills"          },
  { "repo": "sickn33/antigravity-awesome-skills", "name": "antigravity-awesome-skills"    }
]
```

```json
// Step 2 — add the plugin entry under its domain
"domains": {
  "embedded": [
    { "name": "antigravity-bundle-systems-programming", "marketplace": "antigravity-awesome-skills" }
  ]
}
```

### How to find the right `name` for a plugin

The plugin's `name` in `plugins.json` must match what the marketplace
publishes. To discover it:

```bash
# Register the marketplace locally first (so you can list its contents)
claude plugin marketplace add <owner>/<repo>

# List the plugins it publishes
claude plugin list --marketplace <name>
```

Or read the marketplace's `.claude-plugin/marketplace.json` directly on
GitHub. Each entry under `plugins[]` has a `name` field — that's what
goes into `plugins.json`.

---

## 3. Adding a raw-skills repo

Raw-skills repos are GitHub repos that contain `SKILL.md` files but don't
publish a Claude marketplace. The setup script clones them at install time
and copies the skill folders into `~/.claude/skills/`.

**Example (real):** wiring Zephyr skills into the embedded domain.

```json
"skills": {
  "global": [],
  "embedded": [
    { "repo": "beriberikix/zephyr-agent-skills", "subpath": "skills" }
  ]
}
```

### Required fields

| Field | Required? | Default | Notes |
|---|---|---|---|
| `repo` | yes | — | `owner/repo` on GitHub |
| `subpath` | no | `skills` | Path inside the repo that contains the skill folders |

### Picking the right `subpath`

After cloning the repo, find where the `SKILL.md` files live and use the
parent directory as `subpath`.

| Repo layout | Use `subpath` |
|---|---|
| `repo/skills/<name>/SKILL.md` | `skills` (default — can omit) |
| `repo/.claude/skills/<name>/SKILL.md` | `.claude/skills` |
| `repo/engine/.claude/skills/<name>/SKILL.md` | `engine/.claude/skills` (real case: `bitjaru/styleseed`) |
| `repo/<name>/SKILL.md` (no wrapping dir) | `.` |

Quick probe from PowerShell:

```powershell
$tmp = Join-Path $env:TEMP "probe"
git clone --depth 1 https://github.com/<owner>/<repo> $tmp
Get-ChildItem $tmp -Filter "SKILL.md" -Recurse | Select-Object FullName
Remove-Item $tmp -Recurse -Force
```

Whatever directory the `SKILL.md` files share as their parent — that's
your `subpath` (minus the temp prefix).

---

## 4. Validating before commit

Three quick checks before you commit a `plugins.json` change.

### 4.1 — JSON validity

```powershell
Get-Content plugins.json -Raw | ConvertFrom-Json | Out-Null
```

If the file is malformed, this errors out. No output = pass.

### 4.2 — Regenerate the inventory

```powershell
.\scripts\generate-skills-inventory.ps1
```

This updates `docs/skills-inventory.md`. Open it and verify:
- Your new entry appears in the right section
- The skill count is non-zero and reasonable
- No `skill count unavailable` lines (those mean something is wrong — wrong
  plugin name, wrong marketplace name, etc.)

Commit both `plugins.json` and the regenerated `docs/skills-inventory.md`
in the same commit so they don't drift.

### 4.3 — Smoke test

The cheapest real test: run setup against your own machine.

```powershell
# Windows native
.\setup.ps1
# pick the affected domain
```

```bash
# WSL or Linux/macOS
bash setup.sh
# pick the affected domain
```

Watch for `install failed` / `clone failed` lines in the output. The
end-of-setup report calls out any plugin that didn't register, including
which one and why. If the report is clean, you're good.

---

## 5. Adding a brand-new domain

Rare — but if you need a 10th domain (e.g., `gaming`), six files change:

| File | Change |
|---|---|
| `plugins.json` | Add `"gaming": [ ... ]` under both `domains` and (if relevant) `skills` |
| `domains/gaming/CLAUDE.md` | Create the file — domain-specific rules for Claude |
| `setup.ps1` | Add to `$domainMap` and the menu, increment the `[1-N]` prompt |
| `setup.sh` | Add to the `case` statement and the menu, increment the prompt |
| `docs/user-guide.md` | Add a row to §5 (Domain Options) |
| `docs/admin-guide.md` | (this file) Update if the new domain has unusual constraints |

The two setup scripts must stay in sync — anything you change in one,
mirror in the other. Same option numbers, same labels.

Smoke test on **both** Windows and WSL before committing — the bash and
PowerShell paths exercise slightly different code.

---

## 6. Removing or replacing entries

### Removing a single plugin or skill

Just delete the line in `plugins.json`. Re-run the inventory generator
to update `docs/skills-inventory.md`, and commit both.

**Important caveat:** removing an entry stops *future* installs. Teammates
who already ran setup will still have the plugin/skill on their machines.
There's no auto-uninstall. If you need them off, you either:

- Tell teammates to run `claude plugin uninstall <name>` manually, or
- Delete the directory from `~/.claude/skills/<name>/` (for raw skills)

### Replacing a marketplace with a fork

If an upstream repo breaks (bad schema, abandoned, license change), point
to a fixed fork by editing the `repo` field in `marketplaces[]`. The
plugin `name` stays the same since it's published by the fork. Re-run
`claude plugin marketplace update <name>` to refresh local caches.

### Removing an entire marketplace

If no plugin under `global[]` or `domains.<x>[]` references the
marketplace's `name`, the `marketplaces[]` declaration is unused — the
setup script's `Register-Marketplaces` filters by what's actually
referenced. You can delete the row to keep the file clean.

---

## 7. Reference — full example shapes

For copy-paste convenience, here's every entry type with a minimal
working example.

```json
// marketplaces[] entry
{ "repo": "owner/repo", "name": "marketplace-id" }

// global[] / domains.<x>[] entry  (marketplace plugin)
{ "name": "plugin-name", "marketplace": "marketplace-id" }

// global[] / domains.<x>[] entry  (GitHub-direct plugin, fallback)
{ "name": "plugin-name", "github": "owner/repo" }

// skills.<x>[] entry  (raw-skill repo)
{ "repo": "owner/repo", "subpath": "skills" }
```

---

## 8. Common mistakes (and what they look like)

| Symptom | Likely cause | Fix |
|---|---|---|
| `Plugin "<x>" not found in marketplace "<y>"` during setup | Plugin name doesn't match what the marketplace publishes | Run `claude plugin list --marketplace <y>` to find the correct name |
| `Marketplace '<y>' not found. Available marketplaces: ...` | Missing entry in `marketplaces[]` | Add the marketplace declaration |
| Skills clone succeeds but `~/.claude/skills/` doesn't get new dirs | Wrong `subpath` | Probe the repo (see §3) and fix the subpath |
| `Subpath '<path>' not found in <repo>` in setup output | Same as above, but caught explicitly | Fix the subpath |
| Inventory shows `skill count unavailable (parse-error)` | Marketplace JSON has duplicate-by-case keys or other PS5.1 parser issue | Already handled by the JavaScriptSerializer fallback in the generator |
| Inventory shows `skill count unavailable (plugin-not-found)` | Wrong plugin name OR plugin was renamed upstream | Re-check the upstream marketplace.json for the current name |

---

## 9. The `tools` section — CLI tools alongside plugins

`plugins.json` has a fifth top-level key — `tools` — alongside `marketplaces`,
`global`, `domains`, and `skills`. It declares CLI tools that get installed
globally even though they aren't Claude Code marketplace plugins.

### Why this section exists

Some tools your team needs aren't Claude plugins (no `.claude-plugin/marketplace.json`):
they're standalone CLIs (Rust binaries, Python packages, git-cloned scripts).
You can't install them with `claude plugin install`. They install via `pip`,
`cargo`, `npm`, or `git clone`. The `tools[]` section lets you declare them
declaratively in the same config file as plugins.

### Schema

```json
"tools": {
  "global": [
    { "name": "<id>", "source": "pypi|cargo|git-clone", ...source-specific fields }
  ]
}
```

Source types and the fields each one reads:

| `source` | Fields | What it does |
|---|---|---|
| `pypi` | `package` (required), `postInstall` (optional) | `pip install <package>` (or `pipx install` on PEP 668 systems), then optionally run `postInstall` |
| `cargo` | `git` OR `package` | `cargo install --git <git>` or `cargo install <package>`. Requires Rust toolchain on PATH; skipped with a warning if not present. |
| `git-clone` | `repo` (required), `destination`, `postInstall` | `git clone https://github.com/<repo> <destination>`. `~` in destination is expanded. Pulls latest if dest already exists. |

### Current entries

```json
"tools": {
  "global": [
    {
      "name": "code-review-graph",
      "source": "pypi",
      "package": "code-review-graph",
      "postInstall": "code-review-graph install"
    },
    {
      "name": "rtk",
      "source": "cargo",
      "git": "https://github.com/rtk-ai/rtk"
    },
    {
      "name": "claude-usage",
      "source": "git-clone",
      "repo": "phuryn/claude-usage",
      "destination": "~/.claude/tools/claude-usage"
    }
  ]
}
```

| Tool | What it does | Auto-mode |
|---|---|---|
| `code-review-graph` | Tree-sitter code intelligence + MCP server, replaces graphify | Yes — via SessionStart hook (`crg-daemon`) |
| `rtk` | Token-compression shell wrapper from rtk-ai (Apache-2.0). 60–90% token savings on large CLI output. | No — runs transparently when in PATH |
| `claude-usage` | Local dashboard for Claude session log analysis (MIT). Reads `~/.claude/projects/*/session.jsonl`. | No — run manually: `python ~/.claude/tools/claude-usage/cli.py dashboard` |

### How it's wired

`setup.ps1` → `Install-Tools` and `setup.sh` → `install_tools` read the
`tools.global[]` (always) and `tools.<picked-domain>[]` (when domain is
specified) entries from `plugins.json` and dispatch by `source` to:
- `Install-PyPiTool` / `install_pypi_tool`
- `Install-CargoTool` / `install_cargo_tool`
- `Install-GitCloneTool` / `install_git_clone_tool`

In WSL+Windows hybrid mode, PyPI tools install on the Windows side via
`powershell.exe` interop (`install_pypi_tool_windows_side`). Cargo and
git-clone tools install on the WSL side (lives in `~/.claude/tools/`).

### Toolchains and prerequisites

Setup auto-installs the language toolchain each `source` needs, so admins
don't have to ensure Rust / Python / Node is present before running setup:

| `source` | Required toolchain | Auto-installed by |
|---|---|---|
| `pypi` | Python 3 + pip (or pipx on PEP 668 systems) | `Install-Python` (winget on Windows) / `install_python` (apt/dnf/brew on Linux/macOS, plus `ensure_pipx` for PEP 668) |
| `cargo` | Rust toolchain (`cargo`, `rustc`) | `Install-Rust` (winget `Rustlang.Rustup` on Windows) / `install_rust` (apt/dnf/brew, or rustup-init.sh fallback) |
| `git-clone` | `git` (already a setup prerequisite) | Setup's `Install-Git` / `install_git_via_pkg_manager` (always runs) |

If an auto-install fails (corporate-locked machine, no network, package
manager not available), the affected tool gets recorded in the
end-of-setup `SkippedSteps` report with the manual install command.
The rest of setup continues.

**Caveat for hybrid mode (WSL with Windows-side `claude` binary):** PyPI
tools install on the Windows side (so Windows-side Claude can see them).
Cargo and git-clone tools install on the WSL side — they live in
`~/.claude/tools/` in WSL's filesystem. If Windows-side Claude needs a
cargo tool (e.g., `rtk` to compress shell output it runs through
PowerShell), install it manually on the Windows side too:
```powershell
winget install Rustlang.Rustup
cargo install --git https://github.com/rtk-ai/rtk
```

### Adding a new tool

To add e.g. a new Python CLI for everyone:

```json
"tools": {
  "global": [
    {
      "name": "pyright",
      "source": "pypi",
      "package": "pyright"
    }
  ]
}
```

No setup script changes needed. Re-run setup (or `--update`) on each machine.

### What `tools` is NOT

- Not a substitute for plugins. If a tool ships a `.claude-plugin/marketplace.json`,
  declare it under `marketplaces[]` + `global[]` (or `domains.<x>[]`) instead.
  That's a real Claude plugin and benefits from `claude plugin update`,
  uninstall, etc.
- Not a substitute for raw skills. Skills with `SKILL.md` frontmatter that
  Claude can auto-activate go under `skills.<domain>[]`.

### When a tool's upstream publishes a real Claude marketplace

Migrate it out of `tools[]` into `marketplaces[]` + the appropriate domain.
Delete the `tools[]` entry and the related `templates/<tool>-ignore` if any.
Marketplace-published plugins are always preferable to CLI shims when the
choice exists.

---

## See also

- [user-guide.md](user-guide.md) — end-user setup and invocation
- [skills-inventory.md](skills-inventory.md) — generated inventory of what's currently configured
- [superpowers/specs/2026-05-27-plugin-config-design.md](superpowers/specs/2026-05-27-plugin-config-design.md) — original design spec for the plugins.json schema
- [troubleshooting.md](troubleshooting.md) — common install failures and fixes
