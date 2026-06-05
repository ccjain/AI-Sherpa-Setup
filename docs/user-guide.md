# AI Sherpa — User Guide

AI Sherpa configures Claude Code for your team in one command: plugins, domain-specific rules,
secrets protection, and a codebase knowledge graph — all set up automatically.

This guide covers three install scenarios:

| Scenario | Run | Result |
|---|---|---|
| **Native Windows** (PowerShell / cmd) | `setup.bat` | Everything in `C:\Users\<you>\.claude\` |
| **Native macOS / Linux** | `bash setup.sh` | Everything in `~/.claude/` |
| **WSL + Windows hybrid** (most common dev-on-Windows-with-WSL case) | `bash setup.sh` from WSL | Auto-redirects to Windows-side `.claude/` |

---

## 1. What Setup Does

1. Checks **base prerequisites** — Node.js, Git, Claude Code — and **auto-installs**
   any that are missing (winget on Windows, nvm on Linux/macOS for Node, package
   manager for Git).
2. Registers every Claude Code marketplace declared in `plugins.json` →
   `marketplaces[]` (currently 8: `knowledge-work-plugins`, `claude-for-financial-services`,
   `fullstack-dev-skills`, `antigravity-awesome-skills`, `anthropic-agent-skills`,
   `claude-code-workflows`, `thedotmack`, `agent-browser`). Setup only registers
   the marketplaces that are actually referenced by global / domain plugins, so
   unused marketplaces in the list don't cost time.
3. Installs **global Claude plugins** declared in `plugins.json` → `global[]` for
   every domain: `superpowers`, `fullstack-dev-skills` (which bundles 66 stack-specific
   skills like react-expert, vue-expert, python-pro, etc.), `claude-mem` (persistent
   memory across sessions), `agent-browser` (Vercel's browser automation).
4. Installs **domain-specific plugins** declared in `plugins.json` → `domains.<x>[]`
   for the domain you pick.
5. Installs **raw-skill repos** declared in `plugins.json` → `skills.<x>[]` (e.g.
   Zephyr skills for embedded, addyosmani/styleseed for web).
6. Installs **CLI tools** declared in `plugins.json` → `tools.global[]` plus any
   `tools.<x>[]` for the picked domain. Currently 3 globals:
   - `code-review-graph` (PyPI) — Tree-sitter code intelligence + MCP server.
     Runs in **auto mode** via a SessionStart hook that keeps `crg-daemon` alive.
   - `rtk` (cargo) — Rust shell-output compressor; 60–90% token savings.
   - `claude-usage` (git-clone) — Local dashboard for Claude session token/cost stats.

   Toolchains auto-install on demand: Python (winget/brew/apt) for PyPI tools,
   pipx on PEP 668 systems, Rust (`Rustlang.Rustup` / `rustup-init.sh`) for cargo tools.
7. Writes secrets-protection rules to `~/.claude/settings.json` (active for every Claude session, every project).
8. Writes the merged core + domain rules to `~/.claude/CLAUDE.md` (active for every Claude session, every project).
9. **Verifies** every install succeeded; if anything failed, prints a clear FAIL
   report at the end alongside the manual install command for each.

---

## 2. Quick Start — Native Windows

> Run from PowerShell or cmd.

```powershell
cd C:\tools\ai-sherpa
.\setup.bat
```

The script can also be invoked from anywhere by full path (e.g. `C:\tools\ai-sherpa\setup.bat`) — the current working directory does not affect the install. Setup writes only to `~/.claude/`.

You'll be prompted for one thing only:
- Domain (1–11)

Setup runs for 2–5 minutes. Restart your terminal, then:

```powershell
claude
```

code-review-graph runs in **auto mode** — no manual indexing step. The
SessionStart hook starts `crg-daemon` on first session and reuses it on
subsequent sessions. Drop a `.code-review-graphignore` at your project
root (template at `templates/code-review-graphignore` in this repo) to
control what gets indexed.

---

## 3. Quick Start — Native macOS / Linux

> Always invoke with `bash`. **Do not** use `sh setup.sh` — `sh` is dash on Ubuntu/Debian and
> lacks bash features used by the script. The script will auto-correct if you do, but it's
> cleaner to call it right.

```bash
cd ~/tools/ai-sherpa
bash setup.sh
```

The script can also be invoked from anywhere by full path (e.g. `bash ~/tools/ai-sherpa/setup.sh`) — the current working directory does not affect the install. Setup writes only to `~/.claude/`.

After setup:

```bash
claude
# code-review-graph is in auto mode — no manual step needed
```

---

## 4. Quick Start — WSL + Windows Hybrid

This is the common case if you have Claude Code installed on Windows (via `npm install -g
@anthropic-ai/claude-code` from a Windows shell) and also use WSL for development. Your WSL
shell sees the Windows `claude.exe` automatically because Windows npm bin is in WSL's PATH.

Just run:

```bash
cd /mnt/c/tools/ai-sherpa     # or wherever the repo lives
bash setup.sh
```

The script detects the hybrid and prints:

```
[AI Sherpa] WSL detected (Ubuntu).
[AI Sherpa] WSL+Windows hybrid detected:
[AI Sherpa]   claude binary: /mnt/c/Users/Admin/AppData/Roaming/npm/claude
[AI Sherpa]   Redirecting global config to: /mnt/c/Users/Admin/.claude
[AI Sherpa]   (WSL ~/.claude/ would be ignored by the Windows-side claude)
```

It then:
- Writes `CLAUDE.md` and `settings.json` to `/mnt/c/Users/<you>/.claude/` (Windows-side, where
  the Windows `claude.exe` actually reads from).
- Installs code-review-graph on the **Windows** side by calling `powershell.exe` → `winget install Python`
  → `pip install code-review-graph` — no need to leave WSL.
- Plugins land on the Windows side too (they're already there if you've run setup before).

After this, `claude` works identically from PowerShell and WSL — same plugins, same rules,
same code-review-graph.

### Three caveats for hybrid users

1. **Projects should live on a Windows-accessible path.** `/mnt/e/foo` (= `E:\foo`) is ideal.
   Projects in `/home/<you>/...` would have to be accessed via `\\wsl.localhost\Ubuntu\...`
   from Windows — works but slower.
2. **Line endings.** Git on Windows defaults to CRLF. Most tooling handles it transparently;
   if it bothers you, `git config --global core.autocrlf input`.
3. **Live edits to `CLAUDE.md`.** Edits picked up on next session; mid-session file-change
   events don't always cross the WSL boundary.

---

## 5. Domain Options

| # | Domain | For |
|---|---|---|
| 1 | Embedded Software | C/C++, firmware, RTOS |
| 2 | Web (full-stack) | Frontend + backend + UI/UX (React, Vue, Django, Spring, etc.) |
| 3 | Data Science / ML | Python notebooks, pipelines, RAG, fine-tuning |
| 4 | DevOps / Platform | Terraform, K8s, CI/CD, SRE |
| 5 | Marketing | Campaigns, content, analytics |
| 6 | Sales | Outreach, deal management, CRM |
| 7 | Finance / Accounting | Month-end, financial analysis, statements |
| 8 | Customer Service / Support | Tickets, escalation, knowledge base |
| 9 | Procurement / Operations | Sourcing, vendors, workflows |
| 10 | AI / ML Agents | RAG, evals, prompt engineering, agent loops, Anthropic SDK |
| 11 | Frontend + UI/UX | Component libraries, design systems, accessibility, Core Web Vitals |

Stack-specific plugins (React, Vue, Django, FastAPI, Kubernetes, Terraform, Salesforce, etc.)
are bundled inside `fullstack-dev-skills` as **skills**, not separate plugins. They auto-activate
when relevant context appears. You don't install them individually.

---

## 6. Invoking Plugins & Skills

Plugins and skills work differently. **Plugins** expose **slash commands** you type explicitly.
**Skills** auto-activate when their topic comes up in the conversation — you don't invoke them
by name, you just mention the topic and the matching skill loads.

### 6.1 Invoking a plugin (slash command)

Inside a `claude` session, type `/` to open the command palette, or just type the command
directly:

```
/code-review                   # from the code-reviewer plugin
/verify                        # from superpowers
code-review-graph build                      # from code-review-graph
/help                          # list every command available right now
/plugin                        # plugin management UI inside Claude Code
```

See all installed plugins from the terminal:

```bash
claude plugin list
claude plugin list --marketplace fullstack-dev-skills
```

Enable / disable / update a single plugin:

```bash
claude plugin enable  <name>
claude plugin disable <name>
claude plugin update  <name>
```

Or update everything at once via setup:

```powershell
C:\tools\ai-sherpa\setup.bat --update          # Windows
bash ~/tools/ai-sherpa/setup.sh --update        # Linux/macOS/WSL
```

### 6.2 Invoking a skill (context-triggered)

You **do not** invoke skills with a slash command. Each skill has a `description:` line in its
`SKILL.md` frontmatter; Claude loads the skill automatically when your prompt matches that
description.

Example — once the Zephyr skills are installed, asking about Zephyr triggers them:

> "Set up a custom board definition for a new STM32 target using Zephyr HWMv2."

The `board-bringup` skill activates because its description mentions "Custom board bringup for
Zephyr RTOS using Hardware Model v2 (HWMv2)…". You don't say `/board-bringup` — you just write
about the task and the right skill loads.

**To force-load a specific skill** when auto-detection isn't picking it up:

> "Use the **board-bringup** skill to help me port Zephyr to this STM32H7."

Mentioning the skill name explicitly is enough.

### 6.3 What's installed on this machine

| Where | What's there | Inspect |
|---|---|---|
| **Plugins** | `~/.claude/plugins/installed_plugins.json` | `claude plugin list` |
| **Skills** | `~/.claude/skills/<name>/SKILL.md` | `dir %USERPROFILE%\.claude\skills` (Windows) or `ls ~/.claude/skills` (Linux/macOS/WSL) |
| **PyPI tools** | On PATH (e.g. `code-review-graph`) | `where code-review-graph` (Windows) or `which code-review-graph` (Linux/macOS) |
| **Cargo tools** | `~/.cargo/bin/<name>` (e.g. `rtk`) | `cargo install --list` |
| **Git-clone tools** | `~/.claude/tools/<name>/` (e.g. `~/.claude/tools/claude-usage/`) | `ls ~/.claude/tools` |

Each `SKILL.md` starts with frontmatter that explains when it triggers — read those if you want
to know what's in your kit. The full per-domain rollup of plugins + their internal skill counts
lives in `docs/skills-inventory.md`.

### 6.4 Embedded domain — what you get

After picking domain **1** (Embedded):

| Source | Type | Contents |
|---|---|---|
| `antigravity-bundle-systems-programming` plugin | plugin | Editorial bundle of low-level / systems skills (C, C++, Rust, embedded, performance) |
| `beriberikix/zephyr-agent-skills` | raw skills | 21 Zephyr skills: `board-bringup`, `build-system`, `connectivity-ble`, `devicetree`, `hardware-io`, `kernel-basics`, `kernel-services`, `multicore`, `power-performance`, `security-updates`, `storage`, `testing-debugging`, `zephyr-foundations`, and more |

All of these auto-activate on relevant prompts; none need a slash command.

### 6.5 Web domain — what you get

After picking domain **2** (Web):

| Source | Type | Contents |
|---|---|---|
| `figma`, `frontend-design`, `vercel` plugins (from `claude-plugins-official`) | plugins | Design tooling, frontend-design guidance, Vercel deployment workflow |
| `addyosmani/web-quality-skills` | raw skills | Lighthouse / Core Web Vitals / accessibility / SEO / best-practices — Agent Skills from Addy Osmani (Google Chrome team) |
| `bitjaru/styleseed` | raw skills | 69 design rules + 48 shadcn components + brand skins (Toss / Stripe / Linear / Vercel / Notion) on Tailwind v4 + Radix |

The `fullstack-dev-skills` global bundle still applies on top — React, Vue, Next.js, TypeScript, etc. auto-activate as usual.

### 6.6 AI domain — what you get

After picking domain **10** (AI / ML Agents):

| Source | Type | Contents |
|---|---|---|
| `claude-api` plugin (`anthropic-agent-skills`) | plugin | Official Anthropic Claude API/SDK documentation skill (~18 skills inside covering prompt caching, thinking budgets, tool use, batch, files, citations, memory) |
| `llm-application-dev` plugin (`claude-code-workflows`) | plugin | RAG, LangGraph, vector search, AI agent architectures |
| `agent-orchestration` plugin (`claude-code-workflows`) | plugin | Multi-agent system patterns |
| `machine-learning-ops` plugin (`claude-code-workflows`) | plugin | ML training pipelines, hyperparameter tuning, deployment, experiment tracking |

### 6.7 Frontend + UI/UX domain — what you get

After picking domain **11** (Frontend + UI/UX):

| Source | Type | Contents |
|---|---|---|
| `accessibility-compliance` plugin (`claude-code-workflows`) | plugin | WCAG 2.2 AA auditing, keyboard nav, screen-reader testing |
| `ui-design` plugin (`claude-code-workflows`) | plugin | Mobile + web UI/UX design systems |
| `application-performance` plugin (`claude-code-workflows`) | plugin | Profiling, Core Web Vitals, observability |

---

## 7. Verifying The Install

### Check the plugin registry (Windows native or hybrid)

```powershell
type C:\Users\Admin\.claude\plugins\installed_plugins.json
```

You should see entries like `superpowers@claude-plugins-official` and `fullstack-dev-skills@fullstack-dev-skills`.

### Check via CLI

```bash
claude plugin list                 # all enabled plugins
claude plugin list --marketplace fullstack-dev-skills
```

### Check inside Claude Code

```
/help              # lists all commands available now
/plugin            # plugin management UI
```

### Common slash commands + tool checks to test

| Command | From | Verifies |
|---|---|---|
| `/verify` | superpowers plugin | Core skills loaded |
| `/code-review` | superpowers + code-reviewer skill | Review workflow active |
| `code-review-graph --version` | PyPI tool (terminal) | code-review-graph installed |
| `rtk --version` | cargo tool (terminal) | rtk installed and on PATH |
| `python ~/.claude/tools/claude-usage/cli.py stats` | git-clone tool | claude-usage cloned correctly |

---

## 8. Understanding The End-Of-Setup Report

Setup ends with one of three outcomes:

### ✅ Clean success
```
[AI Sherpa] All expected plugins verified.
```
Everything is installed and active.

### ⚠️ Optional steps skipped (yellow block)
```
======================================================
  OPTIONAL STEPS SKIPPED (1)
======================================================
  > code-review-graph (PyPI tool)
    Reason: pip install code-review-graph failed (exit 1)
    Install manually: pip install code-review-graph; code-review-graph install
```
**Plugins are fine.** A non-critical step (usually one of the `tools[]` entries
like code-review-graph, rtk, or claude-usage, or its language toolchain) couldn't
install automatically. The reason and manual install command are shown. Setup is
otherwise complete.

### ❌ Setup incomplete (red block)
```
======================================================
  SETUP INCOMPLETE
  2 plugin(s) did not register:
======================================================
  [FAIL] fullstack-dev-skills@fullstack-dev-skills
  [FAIL] figma@claude-plugins-official
```
**One or more required plugins failed to install.** Re-run setup to retry. If it persists,
install each failed plugin manually:
```bash
claude plugin install <name>@<marketplace> --scope user
```

---

## 9. Common Errors & Fixes

| Error | Cause | Fix |
|---|---|---|
| `setup.sh: 2: set: Illegal option -o pipefail` | You used `sh setup.sh` and `sh` is dash | Use `bash setup.sh` |
| `sudo: 3 incorrect password attempts` (on Python install) | Your sudo password is wrong | Get the correct sudo password and re-run, or install Python manually (`sudo apt-get install python3 python3-pip`) |
| `error: externally-managed-environment` (PEP 668) | Ubuntu 24+ blocks system pip globals | Setup uses pipx instead — update to the latest setup.sh and re-run |
| `Plugin "<name>" not found in marketplace "<name>"` | Wrong plugin name in `plugins.json`, or marketplace is stale | Run `claude plugin marketplace update <marketplace>` and re-run setup |
| `winget failed to install Python (exit N)` | Corporate-locked machine or network restriction | Install Python 3 manually from https://python.org and re-run setup |
| `winget failed to install Rust (exit N)` | Corporate-locked machine, or `Rustlang.Rustup` package unavailable | Install Rust manually from https://rustup.rs (Windows) or `sudo apt-get install rustc cargo` (Linux), then re-run setup. Affects `rtk` and any other cargo-source tool. |
| `cargo not on PATH` after Rust install | New PATH not picked up by current shell | Close and reopen your terminal, then re-run setup |
| code-review-graph install fails in hybrid mode | Python isn't on Windows | Setup will try `winget install` via `powershell.exe`. If that fails too, install Python on Windows manually then re-run |
| `rtk` not visible to Claude in WSL+Windows hybrid mode | rtk installed on WSL side; Windows-side Claude can't see it | On the Windows side: `winget install Rustlang.Rustup` then `cargo install --git https://github.com/rtk-ai/rtk` |

---

## 10. The Pre-Flight Check

At the start of every Claude Code session, Claude asks:

> "Before we start — can this project's code be shared with Anthropic's API? Does this project
> have any NDA, confidentiality agreement, or export control restrictions?"

Answer honestly. Claude also scans automatically for `NDA.md`, `CONFIDENTIAL.md`, and similar
files. If found, it stops and asks for explicit confirmation before proceeding.

**High-security projects:** Do not use Claude Code on projects that management has flagged as
restricted. Access is controlled at the seat level — if you were not given a Claude Code seat
for a project, that is intentional.

---

## 11. Updating Later

```powershell
C:\tools\ai-sherpa\setup.bat --update          # Windows
bash ~/tools/ai-sherpa/setup.sh --update        # Linux/macOS/WSL
```

### What `--update` actually does

The update flow refreshes **everything** in your install to the latest
upstream version, scoped to the domain you originally picked:

| Layer | How it's refreshed |
|---|---|
| Marketplaces | `claude plugin marketplace update <name>` for each marketplace in `plugins.json` — pulls fresh marketplace.json from GitHub |
| Global plugins (`global[]`) | `claude plugin update <name>` for each — uses the freshly-refreshed marketplace data |
| Domain plugins (`domains.<x>[]`) | Same `claude plugin update` for every plugin in your originally-picked domain (see "How we remember your domain" below) |
| Raw skills (`skills.*`) | Each repo is re-cloned shallowly; existing folders in `~/.claude/skills/` are overwritten with latest |
| PyPI tools (`tools[].source == pypi`) | `pip install --upgrade <package>` |
| Cargo tools (`tools[].source == cargo`) | `cargo install --force --git <repo>` (rebuilds from latest upstream) |
| Git-clone tools (`tools[].source == git-clone`) | `git pull` in the destination dir |
| `~/.claude/settings.json` | Re-written from the current `settings/settings-template.json` |
| Project `CLAUDE.md` | **Never** touched |

### How we remember your domain

When you first run `setup` and pick a domain, the script writes a small state
file at `~/.claude/.ai-sherpa-state.json` recording the choice:

```json
{ "domain": "embedded", "installed": "2026-05-28T14:32:11Z", "version": "1" }
```

On every subsequent `--update`, the script reads that file and refreshes only
the plugins / skills / tools for **your** domain — not every domain in
`plugins.json` (which would error on plugins not installed on your machine).

If the state file is missing (e.g. you've already uninstalled, or the file
was deleted), `--update` falls back to refreshing globals only and warns you
to re-run `setup` without the flag to pick a domain.

### Re-running for a different domain

If you want to switch domains (e.g. you originally picked Embedded but now
want to work in Data), run `setup` **without** `--update`. The interactive
prompt lets you pick a new domain, installs its plugins/skills/tools, and
updates the state file. Plugins from the old domain stay installed —
remove them with `--uninstall` first if you want a truly clean switch.

---

## 11b. Uninstalling — start fresh

If something gets into a bad state, or you just want to wipe everything setup
wrote and start over:

```powershell
C:\tools\ai-sherpa\setup.bat --uninstall       # Windows
bash ~/tools/ai-sherpa/setup.sh --uninstall     # Linux/macOS/WSL
```

You'll be shown what's about to be removed and asked to type **`uninstall`**
to confirm (anything else aborts).

### What gets removed

- Every Claude plugin in `plugins.json` `global[]` + every `domains.*[]`
- Every raw skill directory cloned from `plugins.json` `skills.*` repos
- Every CLI tool from `plugins.json` `tools.*` — `pip uninstall`,
  `cargo uninstall`, or `rm -rf` on git-clone destinations
- Every marketplace registered (`claude plugin marketplace remove`)
- `~/.claude/settings.json` and `~/.claude/CLAUDE.md` — restored from
  `.bak` if those exist (i.e. you ran setup over a pre-existing config),
  otherwise deleted

### What stays — by design

- **Toolchains:** Node.js / Python / Rust / Git stay installed. They're useful
  to many tools beyond AI Sherpa, and removing them risks breaking unrelated
  work. If you actually want them gone, do it manually via your package
  manager.
- **Your projects:** Untouched. The uninstall never reads or writes outside
  `~/.claude/`.
- **`~/.claude/projects/...` session logs:** Conversation history stays —
  it's user data, not AI Sherpa's to delete.
- **Manually-installed plugins / skills:** Anything you installed outside of
  `plugins.json` is preserved. Uninstall only removes what setup wrote.

After uninstall, re-run `setup.bat` / `bash setup.sh` to start fresh.

---

## 12. Using The Same Setup From Both Windows and WSL

You already can, with no extra work — see Section 4 (WSL + Windows Hybrid). The Windows `claude`
binary is reachable from WSL automatically, so a single setup run from WSL configures the
Windows-side files where they'll actually be used.

If you'd rather have a **second native install** in WSL (so each side has its own `claude`), see
section 13.

---

## 13. Advanced: Pure-WSL Install Alongside Windows

If you want Claude Code installed natively in WSL (not piggybacking on Windows):

```bash
# 1. Make WSL's nvm-installed claude win over Windows claude in PATH
echo '[interop]' | sudo tee -a /etc/wsl.conf
echo 'appendWindowsPath = false' | sudo tee -a /etc/wsl.conf
# Then from PowerShell:  wsl --shutdown
# Reopen WSL.

# 2. Install Claude Code in WSL
nvm use 20
npm install -g @anthropic-ai/claude-code
which claude    # should now be /home/<you>/.nvm/versions/node/v20/bin/claude

# 3. Run setup from WSL
bash /mnt/c/tools/ai-sherpa/setup.sh
```

This gives you a fully independent WSL install. Plugins must be installed on each side
separately (they include native binaries / platform-specific paths), but you can symlink the
data files to keep rules and settings in sync:

```bash
rm ~/.claude/CLAUDE.md ~/.claude/settings.json
ln -sf /mnt/c/Users/Admin/.claude/CLAUDE.md     ~/.claude/CLAUDE.md
ln -sf /mnt/c/Users/Admin/.claude/settings.json ~/.claude/settings.json
```

---

## 14. More Guides

- [Admin Guide — adding plugins and skills](admin-guide.md) (for whoever curates `plugins.json`)
- [Skills & Plugins Inventory](skills-inventory.md) (generated — what's currently configured per domain)
- [Do's & Don'ts Reference Card](dos-and-donts.md)
- [How to Report AI Errors](feedback-guide.md)
- [Windows-specific Setup Notes](windows-setup.md) (if present)
- [Troubleshooting](troubleshooting.md) (if present)
