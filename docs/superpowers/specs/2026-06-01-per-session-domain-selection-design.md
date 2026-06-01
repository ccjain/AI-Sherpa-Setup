# Per-Session Domain Selection — Design

**Status:** Draft, pending review
**Date:** 2026-06-01
**Branch:** `feat/per-session-domain-selection`
**Owner:** AI Sherpa core
**Related files:** `setup.ps1`, `setup.sh`, `plugins.json`, `core/CLAUDE.md`, `domains/*/CLAUDE.md`, `settings/settings-template.json`, `scripts/lint-invocation-tables.js`

---

## Summary

Today, `setup.bat` asks the user to pick exactly one of 11 domains at install
time and installs plugins/skills only for that domain. This forces a
machine-wide single-domain choice that doesn't match real usage — many users
work across multiple domains (full-stack web + AI integration, embedded +
devops) and across multiple projects with different stacks.

This design replaces install-time domain selection with **per-project domain
selection** driven by a hybrid auto-detect → propose → confirm flow at the
start of each conversation:

1. Setup installs **all** domains' plugins/skills/tools unconditionally.
2. A new SessionStart hook inspects the project at conversation start, infers
   likely domain(s) via deterministic file-fingerprint rules, and injects the
   matching domain rules as context. The hook gives Claude an instruction to
   announce the inference to the user on its first response.
3. The user confirms, corrects, or opts out — recorded once in a per-project
   file `<project>/.claude/ai-sherpa-domains.json`.
4. A `/ai-sherpa-domains` slash command (shipped as a Claude Code skill)
   re-runs the selector at any time.

---

## Goals

- Remove the install-time domain prompt; install every domain's plugins.
- Make domain selection per-project, not per-machine.
- Support multi-domain projects (multiple domain rule sets active at once).
- Auto-detect the common case (real project with a recognizable stack) so the
  user sees zero menu friction; fall back to an explicit prompt only when
  detection finds nothing.
- Preserve the existing lint contract: every plugin in `plugins.json` is
  still acknowledged in the matching `core/CLAUDE.md` or `domains/<X>/CLAUDE.md`.

## Non-goals

- **No new plugin marketplace for AI Sherpa itself.** The slash command ships
  as a standalone Claude Code skill, not as a published plugin.
- **No detection ML.** Rules are deterministic file checks, hardcoded in the
  hook script.
- **No user-overridable rule file.** Detection rules are not exposed via
  config in v1 (future work).
- **No detection of business domains** (`marketing`, `sales`, `finance`,
  `service`, `procurement`). These are knowledge-work domains with no
  reliable code signal; users pick them explicitly.
- **No backwards-compat read path for the old `domain` field** in
  `~/.claude/.ai-sherpa-state.json`. The field is dropped on first migration.
- **No automatic cleanup of stale per-project CLAUDE.md** from older
  project-level installs. Manual cleanup is documented in the install summary.

---

## 1. High-level architecture

### Install-time (one shot, no domain prompts)

```
setup.ps1 / setup.sh →
  installs global + ALL 11 domains' plugins/skills/tools
  copies repo's domains/<X>/CLAUDE.md → ~/.claude/ai-sherpa/domains/<X>/CLAUDE.md  (runtime cache)
  writes hook script              → ~/.claude/ai-sherpa/hooks/sessionstart.js
  appends a new SessionStart hook entry to ~/.claude/settings.json
       (alongside the existing code-review-graph hook — both run)
  writes ~/.claude/CLAUDE.md = core/CLAUDE.md only (no domain rules baked in)
  writes ~/.claude/ai-sherpa/state.json (install manifest, no `domain` field)
  installs slash-command skill at ~/.claude/skills/ai-sherpa-domains/
```

### Every new conversation (SessionStart hook fires)

```
hook reads <cwd>/.claude/ai-sherpa-domains.json

  Case A — file exists, domains listed:
    Concatenate ~/.claude/ai-sherpa/domains/<X>/CLAUDE.md for each domain.
    Emit as system reminder. Silent — rules active from turn 1.

  Case B — file missing → run Layer 1 detection (file fingerprints):

    Case B1 — detection found ≥1 domain:
      Emit system reminder containing:
        - the detected domain set
        - the signals that triggered each
        - an instruction telling Claude to announce the inference
          on its first response, e.g.
            "I see Next.js + langchain — activating web + ai rules.
             Type /ai-sherpa-domains to change."
        - an instruction to write the selection file with detected=true
        - the concatenated rules for those domains
      → Claude announces, writes file, rules active from turn 1.

    Case B2 — detection found nothing:
      Emit a short reminder telling Claude to ask the user with the
      full menu (incl. "skip — opt out").
      → Claude asks, writes the file with the user's answer.

  Case C — file exists with empty domains (`domains: []`):
    Opted-out. Hook emits nothing. (The opt-out shape sets
    `user_confirmed:true` for diagnostic clarity but the hook
    only checks `domains.length`.)
```

### Re-selection

```
User types /ai-sherpa-domains (or says "change domains" — NL fallback)
  → skill re-prompts, rewrites <cwd>/.claude/ai-sherpa-domains.json
  → skill reads the new domains' CLAUDE.md files and emits them inline
    so the change takes effect in the current conversation
```

### Key invariants

- Per-domain `domains/<X>/CLAUDE.md` files in the repo remain the source of
  truth; the existing `lint-invocation-tables.js` still gates them against
  `plugins.json`.
- Selection state is per-project (`<project>/.claude/ai-sherpa-domains.json`).
  No machine-wide "current domain" anymore.
- `~/.claude/ai-sherpa/` is the new runtime directory — owned by setup,
  regenerated on update, removed on uninstall.

---

## 2. File schemas

### `<project>/.claude/ai-sherpa-domains.json`

```json
{
  "version": 1,
  "domains": ["web", "ai"],
  "detected": true,
  "detected_from": ["package.json:next", "package.json:langchain"],
  "user_confirmed": false,
  "updated_at": "2026-06-01T18:57:27Z"
}
```

| Field | Meaning |
| --- | --- |
| `version` | Schema version. Start at `1`. |
| `domains` | Array of domain slugs to activate. `[]` with `user_confirmed:true` = opt-out. Must match a slug under `domains/` in the repo. |
| `detected` | `true` if Layer 1 detection produced this list; `false` if user picked explicitly. |
| `detected_from` | `["<file>:<signal>"]` strings showing what triggered detection. Omitted when `detected:false`. |
| `user_confirmed` | `false` for auto-detected selections the user hasn't acted on; `true` once the user has explicitly picked via `/ai-sherpa-domains`, answered a B2 prompt, or written/edited the file by hand. In v1, **this field is diagnostic only** — surfaced in the `/ai-sherpa-domains` UI ("Confirmed by you: yes/no") but does NOT affect hook behavior. (The hook's "show detected banner only once" behavior is keyed on file existence, not on this field.) |
| `updated_at` | ISO 8601 timestamp of last write. |

**Opt-out shape:**
```json
{ "version": 1, "domains": [], "detected": false, "user_confirmed": true, "updated_at": "..." }
```

### `~/.claude/ai-sherpa/state.json`

```json
{
  "version": 1,
  "installed_at": "2026-06-01T18:57:27Z",
  "ai_sherpa_version": "<git sha or release tag>",
  "domains_installed": ["embedded","web","frontend","ai","data","devops","marketing","sales","finance","service","procurement"],
  "plugin_marketplaces": ["claude-plugins-official", "knowledge-work-plugins"],
  "hook_path": "C:\\Users\\Admin\\.claude\\ai-sherpa\\hooks\\sessionstart.js"
}
```

This replaces the old `~/.claude/.ai-sherpa-state.json`. It deliberately
omits any `domain` field. The hook validates the user's selection against
`domains_installed` before activating.

### `~/.claude/ai-sherpa/domains/<X>/CLAUDE.md`

Byte-for-byte copy of `domains/<X>/CLAUDE.md` from the repo. Written by
setup, regenerated on update.

### Directory layout after install

```
~/.claude/
  CLAUDE.md                        ← core only (no domain rules)
  settings.json                    ← contains the existing code-review-graph hook
                                      AND the new ai-sherpa SessionStart hook
  ai-sherpa/
    state.json
    hooks/
      sessionstart.js              ← cross-platform Node script
    domains/
      embedded/CLAUDE.md
      web/CLAUDE.md
      ... (one per installed domain)
  skills/
    ai-sherpa-domains/SKILL.md     ← slash command
```

---

## 3. Layer 1 detection rules

The hook scans the conversation's cwd for these signals. Multiple rules can
fire; the union becomes the detected set.

| Signal | Domain(s) added |
| --- | --- |
| `west.yml` \| `prj.conf` \| `Kconfig` \| `boards/` (Zephyr) | `embedded` |
| `platformio.ini` (PlatformIO) | `embedded` |
| `mbed_app.json` (Mbed OS) | `embedded` |
| `sdkconfig` \| `sdkconfig.defaults` (ESP-IDF) | `embedded` |
| Any `*.ino` at root (Arduino) | `embedded` |
| Any `*.c` \| `*.cpp` \| `*.cxx` \| `*.cc` at root or in `src/` | `embedded` |
| Any `*.h` \| `*.hpp` \| `*.hxx` at root or in `src/` or `include/` | `embedded` |
| `Makefile` containing `arm-none-eabi-` \| `avr-gcc` \| `xtensa-` \| `riscv` | `embedded` |
| Any `*.ld` at root | `embedded` |
| `package.json` dependencies matching `next` \| `react` \| `vue` \| `angular` \| `svelte` \| `nuxt` \| `gatsby` | `web`, `frontend` |
| `package.json` dependencies matching `express` \| `fastify` \| `@nestjs/` \| `koa` \| `hapi` | `web` |
| `requirements.txt` or `pyproject.toml` matching `langchain` \| `anthropic` \| `openai` \| `llama-index` \| `crewai` \| `autogen` | `ai` |
| `requirements.txt` or `pyproject.toml` matching `pandas` \| `scikit-learn` \| `numpy` \| `pytorch` \| `tensorflow` \| `polars` \| `xgboost` | `data` |
| `Dockerfile` \| `docker-compose.yml` \| `kubernetes/` \| `k8s/` \| `helm/` | `devops` |
| `terraform/` exists OR any `*.tf` at root | `devops` |
| `.github/workflows/` | `devops` |
| (no signal) | (fall through to Case B2) |

### Deliberate non-detection

- **Business domains** are never auto-detected (no reliable code signal).
- **Bare presence of `package.json` or `requirements.txt`** without a framework
  match is NOT a signal. Too noisy.

### Scan scope

- Root + one level deep (`./*` and `./*/`).
- Skip `node_modules`, `venv`, `.venv`, `dist`, `build`, `.git`, `.next`,
  `__pycache__`.
- Directory signals (`boards/`, `.github/workflows/`, `terraform/`) only
  checked at project root.

### Performance budget

- Target <500ms total. Real workload: ~12 file existence checks + at most
  4 small file reads + regex. Well within budget on any disk.
- No network calls. No package-manager invocations.

### Honest tradeoff (embedded over-tagging)

Any C/C++ project will be tagged `embedded`. Acceptable because:
1. The detection banner is visible — user catches it on turn 1.
2. Embedded skills are self-gating; over-tagging costs context tokens, not
   wrong behavior.
3. Missing a genuine bare-metal/RTOS project (the worse failure) is now much
   less likely.

---

## 4. Hook script

### Language and location

Node.js, cross-platform single file at `~/.claude/ai-sherpa/hooks/sessionstart.js`.
Reason: Node is already a hard prerequisite (`Install-NodeJS`), the existing
code-review-graph hook is also a Node one-liner, and one script eliminates
PS↔Bash divergence on Windows vs POSIX hosts.

### Registration

Setup appends a second entry to `~/.claude/settings.json`'s
`hooks.SessionStart` array, leaving the code-review-graph entry untouched.
The exact absolute path of the script is stored both in `settings.json` and
in `~/.claude/ai-sherpa/state.json` so uninstall can remove the right entry
deterministically.

```json
"hooks": {
  "SessionStart": [
    {
      "matcher": "startup|resume|clear|compact",
      "hooks": [
        { "type": "command", "command": "<existing code-review-graph one-liner>", "timeout": 60000 }
      ]
    },
    {
      "matcher": "startup|resume|clear|compact",
      "hooks": [
        { "type": "command", "command": "node \"<absolute path to sessionstart.js>\"", "timeout": 10000 }
      ]
    }
  ]
}
```

### Behavior

```js
// ~/.claude/ai-sherpa/hooks/sessionstart.js
// Must always exit 0. Errors go to stderr. Session must never fail due to us.

const cwd = process.cwd();
const home = process.env.USERPROFILE || process.env.HOME;
const STATE_DIR = path.join(home, ".claude", "ai-sherpa");
const RUNTIME_DOMAINS = path.join(STATE_DIR, "domains");
const SELECTION_FILE = path.join(cwd, ".claude", "ai-sherpa-domains.json");

if (cwd === home) { process.exit(0); }  // bail out in $HOME

try {
  if (fs.existsSync(SELECTION_FILE)) {
    const sel = JSON.parse(fs.readFileSync(SELECTION_FILE, "utf8"));
    if (Array.isArray(sel.domains) && sel.domains.length > 0) {
      emitDomainRules(sel.domains, /*banner*/ null);
    }
    // else Case C — opted out; emit nothing
    process.exit(0);
  }

  const { domains, signals } = detect(cwd);
  if (domains.length > 0) {
    emitDomainRules(domains, { kind: "detected", domains, signals });
  } else {
    emitAskUserBanner();
  }
} catch (err) {
  console.error("[ai-sherpa hook] non-fatal:", err.message);
}
process.exit(0);
```

`detect()` implements the Section 3 table — a single pass per candidate file.

`emitDomainRules()` writes a `<system-reminder>` block to stdout containing
(optional) banner instructions for Claude, then concatenates each chosen
domain's runtime CLAUDE.md.

### Edge cases

| Scenario | Behavior |
| --- | --- |
| Selection file is malformed JSON | Log to stderr → treat as missing → detect |
| Selection lists a domain not in `domains_installed` | Log, skip that domain, continue with the rest |
| Runtime CLAUDE.md missing for a listed domain | Log, skip |
| cwd has no `.claude/` directory | Treated as "no selection file" |
| cwd equals `$HOME`/`$USERPROFILE` | Bail early |
| cwd is the AI Sherpa repo | Setup writes a project-local selection file for the repo with `{"domains":["devops"], "user_confirmed":true}` at install time |
| Unexpected throw | Outer try/catch → log → `exit 0`; session never blocked |
| Hook runtime exceeds budget | `timeout: 10000` in settings.json kills the process |

### What the hook explicitly does NOT do

- No network calls. No `npm`/`pip`/`gh`.
- No writes to disk. The hook is read-only; Claude writes the selection file
  per the embedded instructions. This keeps the audit trail in the
  conversation transcript.

---

## 5. Slash command `/ai-sherpa-domains`

### Packaging — standalone skill

Ships as `~/.claude/skills/ai-sherpa-domains/SKILL.md`. Setup copies it from
`skills/ai-sherpa-domains/SKILL.md` in the repo at install time. No new
plugin or marketplace.

Users invoke it as `/ai-sherpa-domains` (autocomplete-discoverable under `/`)
or via natural-language triggers in the skill's description ("change
domains", "switch domain", "reconfigure AI Sherpa"). The description is
phrased imperatively to improve auto-activation reliability — known
mitigation per published research on Claude Code skills.

### Behavior

```
1. Read <cwd>/.claude/ai-sherpa-domains.json (if it exists). Show the user
   their current selection, plus the detection metadata if any.

2. Read ~/.claude/ai-sherpa/state.json → list of installed domains. Render
   the full menu, marking current selection.

3. Use AskUserQuestion with multiSelect=true to collect the new picks.
   Include a "none — opt out" pseudo-option.

4. Write <cwd>/.claude/ai-sherpa-domains.json with:
     { version:1, domains:[…], detected:false, user_confirmed:true,
       updated_at:"<now>" }

5. Read ~/.claude/ai-sherpa/domains/<X>/CLAUDE.md for each chosen domain and
   emit them inline as system-reminder content, so the new rules are active
   in the current conversation without a session restart.
```

### What the skill explicitly does NOT do

- Install or uninstall plugins. All plugins are already on disk from setup.
- Shell out to `setup.ps1`.
- Mutate `~/.claude/ai-sherpa/state.json` or `~/.claude/CLAUDE.md`.

### Future commands (out of scope for v1, namespace reserved)

- `/ai-sherpa-status` — current domains, hook health, last update.
- `/ai-sherpa-version` — installed version + domain count.

---

## 6. Setup script changes & migration

### Removed code

| Existing | Reason |
| --- | --- |
| `Read-Host "Enter number [1-11]"` + `$domainMap` | No domain prompt anymore |
| `Invoke-DomainSwitch` | No more switching at install time |
| `Get-AiSherpaDomain` | Nothing reads it |
| `if ($domain -eq "embedded") { detect-embedded-toolchain.ps1 }` | Toolchain detection becomes unconditional |

### Generalized code

| Existing | Change |
| --- | --- |
| `Install-DomainSkills $domain` | Loop over every key in `plugins.json.domains` |
| `Install-Skills -Domain $domain` | Loop over every key in `plugins.json.skills` |
| `Install-Tools -Domain $domain` | Loop over every domain section in `plugins.json.tools` |
| `Register-Marketplaces -Domain $domain` | Register every marketplace referenced by global + any domain |
| `Write-GlobalClaudeMd $domain` | `Write-CoreOnlyClaudeMd` — writes `core/CLAUDE.md` + a small "Domain Selection Protocol" section, no domain merge |
| `Copy-ClaudeMd $domain $projectType` | Same treatment for the project-level path |
| `Write-AiSherpaState -Domain $domain` | New schema (no `domain` field) |

### New code

| Function | Purpose |
| --- | --- |
| `Copy-DomainRuneCache` | For each domain, copy `domains/<X>/CLAUDE.md` → `~/.claude/ai-sherpa/domains/<X>/CLAUDE.md`. Idempotent. |
| `Write-SessionStartHook` | Copy the repo's `hooks/sessionstart.js` to `~/.claude/ai-sherpa/hooks/sessionstart.js`. The hook lives as a real file in the repo, not a heredoc inside setup. |
| `Register-SessionStartHook-Settings` | Merge a new entry into `settings.json`'s `hooks.SessionStart` array. Idempotent — checks for an existing entry whose `command` ends in `ai-sherpa\\hooks\\sessionstart.js` before appending. |
| `Install-AiSherpaSkill` | Copy `skills/ai-sherpa-domains/` → `~/.claude/skills/ai-sherpa-domains/`. |
| `Install-AiSherpaProjectFile` | At end of install, write `<repo>/.claude/ai-sherpa-domains.json` with `{"domains":["devops"], "user_confirmed":true}` so AI Sherpa work has stable rules. |

### Main flow (revised)

```
Show-Logo
if --update    → Invoke-Update;    exit
if --uninstall → Invoke-Uninstall; exit

Install-NodeJS; Install-Git; Install-ClaudeCode

# No domain prompt.

Register-Marketplaces                # all marketplaces
Install-CoreSkills                   # plugins.json.global
foreach dom in plugins.json.domains: Install-DomainSkills $dom
foreach dom in plugins.json.skills:  Install-Skills -Domain $dom
Install-Tools                        # all domains' tool sections

Copy-DomainRuneCache
Write-SessionStartHook
Register-SessionStartHook-Settings
Install-AiSherpaSkill

if user-level:
  Write-CoreOnlyClaudeMd
else:
  Write-ProjectSettings
  Copy-CoreOnlyClaudeMd-ToProject

scripts/detect-embedded-toolchain.ps1   # unconditional now
Enable-WindowsLongPaths
Write-AiSherpaState
Install-AiSherpaProjectFile
verify-installation
```

### `--update` flow

```
Register-Marketplaces                 # all
for each plugin in plugins.json.global + every domain: claude plugin update
Install-Skills (every domain)
Install-Tools  (every domain, --upgrade)
Copy-DomainRuneCache                  # refresh
Write-SessionStartHook                # rewrite in case logic changed
Install-AiSherpaSkill                 # refresh slash-command skill
Write-GlobalSettings                  # existing
# CLAUDE.md NOT touched (matches today's behavior)
# state.json: refresh timestamp + ai_sherpa_version
```

### `--uninstall` additions

```
... existing steps ...
Remove-Item ~/.claude/ai-sherpa/                  # state + hooks + runtime cache
Remove-Item ~/.claude/skills/ai-sherpa-domains/
# settings.json restored from .bak (existing flow — covers hook entry removal)
# DO NOT touch <project>/.claude/ai-sherpa-domains.json files — user-owned
```

### Migration for users on the old design

When setup detects the legacy `~/.claude/.ai-sherpa-state.json` (with a top-
level `domain` field):

1. Log: `"[AI Sherpa] Detected legacy install with domain='<X>'. Migrating..."`
2. Run the normal install. Old domain's plugins are already there; new
   domains' plugins are installed alongside.
3. Write the new `state.json` schema. Rename the legacy file to
   `~/.claude/.ai-sherpa-state.json.legacy` as a paper trail (not deleted).
4. Overwrite `~/.claude/CLAUDE.md` with core-only content. The existing
   setup already backs up to `CLAUDE.md.bak`; the previous merged content
   is preserved there.
5. The old `domain` value is NOT auto-applied to any project. Layer 1
   detection re-derives it per-project as conversations open. Install
   summary surfaces this:

   ```
   [ACTION REQUIRED] Your previous AI Sherpa install used domain='<X>'
     system-wide. Going forward, each project picks its own domains. The
     first conversation you open in a project will auto-detect (or ask) —
     run /ai-sherpa-domains inside Claude Code to override.
   ```

6. Stale project-level CLAUDE.md files from older project-level installs:
   setup CANNOT locate them automatically (no registry). Result is benign —
   those projects load domain rules twice (once from stale project CLAUDE.md,
   once from the hook). Behavior is correct, just redundant tokens.
   Documented in the install summary:

   ```
   [NOTE] If you previously installed AI Sherpa inside specific project
     directories, those projects' CLAUDE.md files still contain the old
     domain rules in an appended block. Remove the block manually (it's
     delimited by an HTML comment) — leaving it is harmless.
   ```

---

## 7. Linter, tests, docs, scope, risks

### Linter — unchanged

`scripts/lint-invocation-tables.js` is per-file: it scans each
`domains/<X>/CLAUDE.md` for mentions of its declared plugins. Domain file
contents are unchanged. The new "Domain Selection Protocol" section in
`core/CLAUDE.md` references procedures, not plugin names. Linter passes
as-is.

### New tests

| Test | Purpose | Location |
| --- | --- | --- |
| `scripts/test-hook.sh` | Run `node hooks/sessionstart.js` against fixture trees (empty, web-only, full-stack, embedded, opt-out) and assert stdout shape | `scripts/` |
| `scripts/fixtures/detection/<scenario>/` | Mini project trees exercising every detection rule | new dir |
| `scripts/test-migration.sh` | Seed an old-schema `.ai-sherpa-state.json`, run setup, assert legacy file is renamed and new state.json is correct | `scripts/` |
| Extend `scripts/test-setup.sh` | Assert (a) every domain has a runtime rune copy, (b) `settings.json` contains BOTH hook entries, (c) the slash-command skill is installed | edit existing |

### Documentation updates in this work

| File | Change |
| --- | --- |
| `core/CLAUDE.md` | Add ~15-line "AI Sherpa — Domain Selection Protocol" section: hook injects detected/selected domains; `/ai-sherpa-domains` to change; opt-out supported. |
| Project `CLAUDE.md` (this repo's own file) | Update "Plugins & invocation rules workflow" to mention the runtime cache at `~/.claude/ai-sherpa/domains/` and the hook script. Linter section unchanged. |
| `README.md` | Replace any "pick your domain" step in quickstart with "domains auto-detect per project". |

### Scope

**In v1:** every decision in Sections 1–6, expanded embedded detection,
cross-platform Node hook, `/ai-sherpa-domains` skill, legacy-state migration,
detection-rule fixtures.

**Out of scope (future work):**
- User-overridable `~/.claude/ai-sherpa/detection-rules.json`.
- Sibling commands (`/ai-sherpa-status`, `/ai-sherpa-version`, `/ai-sherpa-update`).
- Auto-cleanup of stale per-project CLAUDE.md.
- Detection confidence levels / ML refinement.
- Promoting AI Sherpa to a proper plugin (would unlock `/ai-sherpa:domains`
  namespace syntax).
- Monorepo subdirectory detection deeper than one level.

### Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Hook output exceeds context budget on huge multi-domain selections | low | Soft cap of 10 domains documented in the skill; warn if exceeded |
| Hook throws on a malformed `package.json` and breaks the session | low | Outer `try/catch`; always `exit 0`; stderr only |
| Detection over-tags `embedded` on every C/C++ project | medium | Inline banner shows what was detected; `/ai-sherpa-domains` removes it in one command |
| User has custom `~/.claude/settings.json`; install loses customizations | low | Setup already backs up to `settings.json.bak`; new hook is appended, not overwritten |
| `Register-SessionStartHook-Settings` not idempotent — re-running setup duplicates the hook entry | medium | Check for an existing entry ending in `ai-sherpa\\hooks\\sessionstart.js` before appending |
| Stale project-level CLAUDE.md confuses users ("rules I didn't pick showing up") | medium | Documented in install summary; manual fix instructions in migration note |
| Hook path on Windows contains spaces/Unicode — command-line escaping fails | medium | Setup escapes via Node's `JSON.stringify`; `command` uses double-quoted path |
| User in a non-writable cwd — Claude can't create `.claude/ai-sherpa-domains.json` | low | Skill catches write errors; falls back to session-only rules with a message |

---

## Appendix — files touched

**Added:**
- `hooks/sessionstart.js` (repo source for the runtime hook)
- `skills/ai-sherpa-domains/SKILL.md` (repo source for the slash command)
- `scripts/test-hook.sh`
- `scripts/test-migration.sh`
- `scripts/fixtures/detection/*/` (per-scenario fixture trees)
- `docs/superpowers/specs/2026-06-01-per-session-domain-selection-design.md` (this file)

**Modified:**
- `setup.ps1` (remove domain prompt, generalize loops, new install steps,
  migration block, uninstall additions)
- `setup.sh` (mirror of setup.ps1 changes)
- `core/CLAUDE.md` (add Domain Selection Protocol section)
- `CLAUDE.md` (this repo's project file — note the runtime cache + hook)
- `README.md` (if it mentions the domain prompt step)
- `scripts/test-setup.sh` (extend assertions)

**Untouched (deliberately):**
- `plugins.json` — no schema change
- `scripts/lint-invocation-tables.js` — no logic change
- `domains/<X>/CLAUDE.md` files — no content changes
- `settings/settings-template.json` — written before the hook is added; the
  hook entry is merged separately via `Register-SessionStartHook-Settings`
