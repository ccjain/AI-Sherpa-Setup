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

## 9. Tools installed outside `plugins.json`

A handful of things land on every machine but are **not** declared in
`plugins.json`. They install through the setup script's Python path
instead, because they're CLI tools published on PyPI rather than
Claude Code marketplace plugins.

### Current entry: `code-review-graph`

| | |
|---|---|
| What it is | Tree-sitter code intelligence + MCP server, replaces graphify |
| Upstream | [tirth8205/code-review-graph](https://github.com/tirth8205/code-review-graph) |
| Install path | `setup.ps1` → `Install-CodeReviewGraph` / `setup.sh` → `install_code_review_graph` |
| How it's invoked | Auto mode via SessionStart hook in `settings/settings-template.json` (ensures `crg-daemon` is running) |
| Why not in `plugins.json` | Upstream repo has no `.claude-plugin/marketplace.json`. It's a Python package on PyPI (`pip install code-review-graph`), not a Claude Code marketplace plugin. The two install mechanisms aren't interchangeable. |

### When does this migrate into `plugins.json`?

If upstream ever publishes a `.claude-plugin/marketplace.json` (we periodically
re-check), then:

1. Add their repo to `plugins.json` → `marketplaces[]`
2. Add the plugin to `global[]`
3. Delete `Install-CodeReviewGraph` from setup.ps1 and `install_code_review_graph`
   from setup.sh
4. Remove the templates/code-review-graphignore generated-ignore path if the
   plugin handles it natively

Until then, the dual-path setup is intentional, not a bug.

### Adding more PyPI tools later

If we want to install another Python CLI (e.g. `pyright`, `black`, a project-
specific linter), follow the `Install-CodeReviewGraph` shape — one function per
tool, called from the main setup flow. We deliberately did **not** generalize
this into a `tools[]` schema in `plugins.json` because the population is small
and unlikely to grow fast. Revisit if the count gets above ~3.

---

## See also

- [user-guide.md](user-guide.md) — end-user setup and invocation
- [skills-inventory.md](skills-inventory.md) — generated inventory of what's currently configured
- [superpowers/specs/2026-05-27-plugin-config-design.md](superpowers/specs/2026-05-27-plugin-config-design.md) — original design spec for the plugins.json schema
- [troubleshooting.md](troubleshooting.md) — common install failures and fixes
