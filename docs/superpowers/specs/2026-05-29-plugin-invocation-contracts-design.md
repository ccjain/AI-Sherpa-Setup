# Plugin Invocation Contracts in CLAUDE.md — Design

**Status:** Draft, pending review
**Date:** 2026-05-29
**Owner:** AI Sherpa core
**Related files:** `plugins.json`, `core/CLAUDE.md`, `domains/*/CLAUDE.md`, `setup.ps1`, `setup.sh`, `AGENTS.md`

---

## Summary

Make plugin/skill auto-invocation behavior explicit in the user-installed
`~/.claude/CLAUDE.md` by adding scoped "Invocation Contract" sections — global
rules in `core/CLAUDE.md`, per-domain rules in `domains/<name>/CLAUDE.md`.
Setup concatenates those two source files at install time and writes the
merged file to `~/.claude/CLAUDE.md`. A lint check verifies `plugins.json`
and the contracts stay in sync.

This makes plugin invocation reproducible (everyone running AI Sherpa for a
given domain sees the same rules) and discoverable (the contract sits in the
file Claude already reads), without introducing a JSON-driven generator
pipeline that would be premature at current scale (~100 rules across 13
domains, edited a handful of times a year).

---

## Goal

For every plugin/skill installed by AI Sherpa, the user's `~/.claude/CLAUDE.md`
should include:

- An explicit acknowledgment of the plugin (so both the user and Claude know
  it's installed for this scope).
- For plugins where the project has an opinion about when to use them: a
  `MANDATORY` rule with trigger phrase + rationale.
- For plugins that auto-fire fine from their own `SKILL.md` descriptions: a
  one-line `Self-described` entry confirming the plugin's presence, no
  override needed.

Rules live in the scope file matching the plugin's scope:

- `plugins.json` → `global[]` or `skills.global[]` → `core/CLAUDE.md`
- `plugins.json` → `domains.<name>[]` or `skills.<name>[]` → `domains/<name>/CLAUDE.md`

No duplication. No upfront SKILL.md audit.

## Non-goals

- **No JSON-driven generator.** Hand-authored markdown is sufficient at this
  scale. A lint check covers the only real drift mode (plugins added without
  matching rules).
- **No per-skill rows for multi-skill plugins.** `fullstack-dev-skills`' 66
  skills get one `Self-described` bullet, not 66 rows.
- **No upstream SKILL.md quality audit.** Mandatory rules come from project
  opinion ("we always brainstorm first"), not from reviewing how well each
  upstream skill describes its triggers.
- **No new `plugins.json` fields.** No `"invocation"`, `"triggers"`, or
  similar annotations on plugin entries. The existing schema is sufficient.
- **No changes to Claude Code's session-load behavior.** Relies entirely on
  existing `~/.claude/CLAUDE.md` loading.

---

## Background / current state

### What setup does today

`setup.ps1` (`Write-GlobalClaudeMd`) and `setup.sh` (`write_global_claudemd`)
install the user's `~/.claude/CLAUDE.md` by **copying only the chosen domain's
CLAUDE.md**. They do not merge with `core/CLAUDE.md`. Result:

- `core/CLAUDE.md` (~195 lines of universal rules, the 7 principles, NDA
  guidance) exists in the source repo but **never reaches the installed user.**
- Each `domains/<name>/CLAUDE.md` says "extends global rules in
  `core/CLAUDE.md`" — but that extension is purely textual; Claude only sees
  the domain file.
- Each `domains/<name>/CLAUDE.md` ends with a vague *"Bundled Stack Skills"*
  paragraph that says skills "auto-activate when working in their context" —
  no specific triggers, no project opinions, no diagnostic guidance.

### What the user actually sees

The installed `~/.claude/CLAUDE.md` is effectively a single-layer file (the
domain content only). AGENTS.md describes a three-layer design
(core + domain + project) but only one layer (domain) actually ships.

### Why this matters

When a user reports *"plugin X didn't fire when I asked for Y,"* there's no
project-controlled mechanism to fix it. The skill's upstream `SKILL.md`
description is the only signal — fuzzy, hard to override, tied to upstream
release cycles. This design gives the project an explicit override surface.

---

## Architecture

### Source repo (file locations unchanged)

```
core/CLAUDE.md                       — universal rules + GLOBAL plugin invocation contract
domains/<name>/CLAUDE.md             — domain rules + DOMAIN plugin invocation contract
CLAUDE.md  (project root)            — project workflow rules + new "plugins workflow" meta-rule
scripts/lint-invocation-tables.js    — NEW: verifies plugins.json ↔ CLAUDE.md sync
```

### Install-time output

When the user runs `setup.bat` and picks "embedded":

```
~/.claude/CLAUDE.md  ←  core/CLAUDE.md  +  "\n\n---\n\n"  +  domains/embedded/CLAUDE.md
```

Estimated combined size: 400–500 lines (within the revised budget; see below).

### Why core-before-domain

Universal rules read first (set baseline behavior); domain rules read second
(refine for the current context). Matches how AGENTS.md describes the layers
and avoids the inversion where domain rules might be overridden by
later-loaded universal ones.

### Line budget — revised

AGENTS.md's current "~300 lines combined" target is conservative and not
backed by a cited source; Claude Code reliably honors longer CLAUDE.md files
in practice. This spec raises the combined ceiling to **~500 lines** to
accommodate the new Invocation Contract sections without aggressive trim work
on the existing dense domain content (embedded toolchain tables, web browser
tooling guidance, etc).

Per-file targets:
- `core/CLAUDE.md`: keep ≤ 230 lines (currently 195 + ~30 for global
  invocation contract).
- `domains/<name>/CLAUDE.md`: keep ≤ 275 lines (largest current = embedded at
  160; add ~20 for invocation contract = 180; comfortable headroom).
- Combined: ≤ 500 lines. Validated via real Claude Code session before
  scaling to all 13 domains.

---

## Content shape — the Invocation Contract section

Same template in both `core/CLAUDE.md` and each `domains/<name>/CLAUDE.md`.
Appended to the end of the file (after existing rules, before any final
footer):

```markdown
---

## Plugin & Skill Invocation Contract — Global

These plugins ship with AI Sherpa globally. Reach for them by default;
rules below override any defaults from their SKILL.md descriptions.

### MANDATORY — invoke without asking

| When the user…                                          | Invoke                                | Why                              |
|---------------------------------------------------------|---------------------------------------|----------------------------------|
| says "build a feature", "add X", or "modify behavior"   | `superpowers:brainstorming`           | Hard gate before any implementation |
| asks to write tests for new code                        | `superpowers:test-driven-development` | Test-first standard              |
| asks for code review on current branch / PR             | `superpowers:requesting-code-review`  | Mandatory pre-merge              |

### Self-described — auto-fires for its listed use cases, no override needed

- `claude-mem` — persistent memory across sessions
- `agent-browser` — browser automation tasks
- `fullstack-dev-skills` — ~66 framework-specific skills (React, Next.js,
  FastAPI, Django, …) auto-activate when their context matches

### Diagnostic — if a skill isn't firing when expected

1. Run `/plugin` — does it show `[ON]`?
2. Installed but not loaded? Run `/reload-plugins`.
3. Absent? Re-run AI Sherpa setup; check `[ACTION REQUIRED]` at the end.
```

The per-domain version uses the same template with title `Plugin & Skill
Invocation Contract — Domain (<name>)` and rows drawn from the corresponding
`plugins.json.domains.<name>` + `plugins.json.skills.<name>` entries.

**Note on the Diagnostic subsection:** include it in `core/CLAUDE.md` only by
default — it's generic advice that doesn't change per domain. Domain
contracts may add their own Diagnostic subsection only when there are
domain-specific troubleshooting steps (e.g. embedded might add "if Zephyr
skills aren't loading, check `~/.claude/embedded-toolchain.json` was written
by `detect-toolchain.ps1`"). Don't duplicate the generic Diagnostic content.

### Section length budget

- Global contract: ~25–35 lines (pushes `core/CLAUDE.md` from 195 → ~225).
- Per-domain contract: ~15–25 lines (varies with plugin count).

---

## Setup-time merge

### Windows — `setup.ps1`

Modify `Write-GlobalClaudeMd`:

```powershell
function Write-GlobalClaudeMd {
    param([string]$Domain)
    $core   = "$ScriptDir\core\CLAUDE.md"
    $domain = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $core))   { Write-Err "core/CLAUDE.md missing at $core"; exit 1 }
    if (-not (Test-Path $domain)) { Write-Err "Domain CLAUDE.md missing at $domain"; exit 1 }

    $claudeDir = "$env:USERPROFILE\.claude"
    $target    = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }

    $coreContent   = (Get-Content $core -Raw).TrimEnd()
    $domainContent = (Get-Content $domain -Raw)
    $merged = $coreContent + "`r`n`r`n---`r`n`r`n" + $domainContent
    Set-Content -Path $target -Value $merged -Encoding UTF8
    Write-Info "Merged core + $Domain rules written to $target"
}
```

Apply the same merge logic to `Copy-ClaudeMd` (project-level install path).

### Unix — `setup.sh`

Modify `write_global_claudemd`:

```bash
write_global_claudemd() {
  local domain="$1"
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  [[ -f "$core_md" ]]   || { log_error "core/CLAUDE.md missing at $core_md"; exit 1; }
  [[ -f "$domain_md" ]] || { log_error "Domain CLAUDE.md missing at $domain_md"; exit 1; }

  local claude_dir="$HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "$target.bak"
    log_warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
  fi

  {
    cat "$core_md"
    printf '\n\n---\n\n'
    cat "$domain_md"
  } > "$target"
  log_info "Merged core + $domain rules written to $target ($(wc -l < "$target") lines)"
}
```

Apply same merge logic to `copy_claudemd` (project-level path).

### Backup behavior

Single `.bak` file, overwritten each run. Pre-existing `.bak` from older
setups gets silently replaced — matches today's behavior; no `.bak.bak`
proliferation.

---

## Meta-rule for AI Sherpa project CLAUDE.md

Append to `<repo-root>/CLAUDE.md`:

```markdown
## Plugins & invocation rules workflow

When adding or removing an entry in `plugins.json`, you MUST also update the
matching CLAUDE.md in the same commit:
  - `global[]` or `skills.global[]`        → `core/CLAUDE.md`
  - `domains.<name>[]` / `skills.<name>[]` → `domains/<name>/CLAUDE.md`

Every plugin/skill must appear in either the MANDATORY table or the
Self-described list of the matching CLAUDE.md.

CI runs `node scripts/lint-invocation-tables.js` which fails the build on
mismatches. Run it locally before commit.

Do NOT put global plugin rules in domain files, or domain plugin rules in
core. The merge of core + chosen-domain happens at user setup time.
```

---

## Lint script — `scripts/lint-invocation-tables.js`

Node (matches existing `setup.sh` practice of `node -e "..."` for JSON
parsing). Single file, no dependencies beyond Node's built-in `fs` / `path`.
Runs equally on Windows and Unix.

```javascript
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(ROOT, 'plugins.json'), 'utf8'));

// Collect expected plugin/skill identifiers per scope.
const expected = { global: new Set() };
for (const p of config.global || [])           expected.global.add(p.name);
for (const s of (config.skills?.global) || []) expected.global.add(s.repo);

for (const [dom, plugins] of Object.entries(config.domains || {})) {
  expected[dom] = expected[dom] || new Set();
  for (const p of plugins) expected[dom].add(p.name);
}
for (const [dom, skills] of Object.entries(config.skills || {})) {
  if (dom === 'global') continue;
  expected[dom] = expected[dom] || new Set();
  for (const s of skills) expected[dom].add(s.repo);
}

let failed = false;
for (const [scope, names] of Object.entries(expected)) {
  const mdPath = scope === 'global'
    ? path.join(ROOT, 'core/CLAUDE.md')
    : path.join(ROOT, 'domains', scope, 'CLAUDE.md');
  if (!fs.existsSync(mdPath)) {
    console.error(`MISSING FILE: ${mdPath} (referenced by plugins.json scope "${scope}")`);
    failed = true;
    continue;
  }
  const content = fs.readFileSync(mdPath, 'utf8');
  for (const name of names) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp('`' + escaped + '(:|`)');
    if (!pattern.test(content)) {
      console.error(`MISSING: \`${name}\` not mentioned in ${path.relative(ROOT, mdPath)}`);
      failed = true;
    }
  }
}

process.exit(failed ? 1 : 0);
```

**What it checks (v1):**

- For every plugin/skill in `plugins.json`, asserts its identifier appears as
  a backticked token in the matching CLAUDE.md (e.g. `` `superpowers` `` or
  `` `superpowers:brainstorming` ``).
- Reports missing entries with the exact file + missing name.
- Exit 0 = clean; exit 1 = at least one mismatch.

**What it does NOT check (v1, by design):**

- Trigger phrase quality.
- Rationale text quality / accuracy.
- Whether the entry is in MANDATORY vs. Self-described section.
- Reverse direction (rules referencing plugins not in plugins.json — "dead
  rules"). Easy to add; deferred until drift becomes a problem.

**Where it runs:**

- Manually: `node scripts/lint-invocation-tables.js` before commit.
- CI: GitHub Actions on every push touching `plugins.json`, `core/CLAUDE.md`,
  or `domains/**/CLAUDE.md`.
- Optional pre-commit hook (documented in admin-guide.md; not auto-installed).

---

## Migration plan

Ordered, each step independently verifiable.

### Phase 1 — Foundation (one focused commit)

1. **Update `AGENTS.md`** — raise the combined line-budget number from 300 →
   500; document the new "Invocation Contract" section convention; document
   that user-installed `~/.claude/CLAUDE.md` is the merge of core + chosen
   domain.
2. **Update project `CLAUDE.md`** — add the "Plugins & invocation rules
   workflow" meta-rule.
3. **Add Global Invocation Contract to `core/CLAUDE.md`** — append the
   section covering all `plugins.json.global` + `plugins.json.skills.global`
   entries (today: `superpowers`, `fullstack-dev-skills`, `claude-mem`,
   `agent-browser`).
4. **Add Domain Invocation Contract to `domains/embedded/CLAUDE.md`** —
   proof-of-concept; uses the template against `plugins.json.domains.embedded`
   + `plugins.json.skills.embedded` (today: `antigravity-bundle-systems-
   programming` + `beriberikix/zephyr-agent-skills`).
5. **Modify `setup.ps1` and `setup.sh`** — change `Write-GlobalClaudeMd` /
   `write_global_claudemd` and `Copy-ClaudeMd` / `copy_claudemd` to
   concatenate core + domain.
6. **Add `scripts/lint-invocation-tables.js`** — exactly the script above.
7. **Wire lint into CI** — extend the existing test workflow (or add a new
   one) to run `node scripts/lint-invocation-tables.js` on relevant file
   changes.

### Phase 2 — Verify (manual)

8. **Verify on embedded end-to-end** — run setup on a clean Windows box,
   inspect `~/.claude/CLAUDE.md`, confirm merged content, confirm lint
   passes, confirm Claude Code session sees both rule sets and invokes
   `superpowers:brainstorming` on a "build a feature" prompt.

### Phase 3 — Bulk rollout (separate commit)

9. **Author remaining 12 domain Invocation Contracts** — apply template to
   web, ai, frontend, devops, marketing, sales, finance, service,
   procurement, data, backend, uiux. One section per file, drawn from
   `plugins.json`.
10. **Run lint, fix gaps, commit.**

Phases 1-2 are the validation gate. Phase 3 is mechanical once Phase 2
confirms the pattern works.

---

## Testing plan

### Automated

- **Lint smoke test** (extend `scripts/test-setup.sh` or add a sibling):
  1. Copy `plugins.json` to a temp file with a fake plugin name added to
     `global[]`. Point lint at it. Assert exit 1.
  2. Add the fake plugin name as a backticked token in a temp `core/CLAUDE.md`
     copy. Re-run. Assert exit 0.

- **Setup merge test** (extend the existing setup test harness):
  1. Stage sentinel `core/CLAUDE.md` containing `__CORE_SENTINEL__` and a
     sentinel `domains/test/CLAUDE.md` containing `__DOMAIN_SENTINEL__`.
  2. Invoke the merge function. Assert resulting `~/.claude/CLAUDE.md`
     contains both sentinels separated by `---`.
  3. Pre-create `~/.claude/CLAUDE.md` with `__PREEXISTING__`. Re-run.
     Assert `~/.claude/CLAUDE.md.bak` contains `__PREEXISTING__`.

### Manual

- **Real-install smoke** on a clean Windows VM:
  - Run `setup.bat`, choose embedded.
  - Inspect `~/.claude/CLAUDE.md`:
    - Contains `# CLAUDE.md` heading (core).
    - Contains `# AI Sherpa — Embedded Software Rules` heading (domain).
    - Contains both Invocation Contract sections (Global + Domain).
    - Line count 400–500.
  - Open Claude Code, ask: *"let's build a new feature for X."* Assert
    Claude invokes `superpowers:brainstorming` per the MANDATORY rule, not
    `Edit`/`Write` directly.

- **Pre-existing CLAUDE.md backup**: with existing `~/.claude/CLAUDE.md` and
  existing `.bak`, re-run setup. Assert `.bak` is overwritten cleanly; no
  `.bak.bak`.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Combined file (~500 lines) is more than Claude reliably honors | Low | Medium — rules at end of file might be deprioritized | Validate via real session in Phase 2 before bulk rollout; if hit, trim non-essential narrative from core (e.g. compress the 7-principles prose). |
| Lint false-positives from special characters in plugin names | Low | Low | Plugin names in current `plugins.json` are alphanumeric + `-`; regex-escape handles others. Tested on existing data. |
| Admins commit `plugins.json` changes and forget the CLAUDE.md update | Medium | Low — caught at CI | Document the lint command in `CLAUDE.md` + `admin-guide.md`; CI fails the PR; optional pre-commit hook. |
| Merge order (core-before-domain vs. reverse) affects Claude's prioritization | Low | Low | Document chosen order in AGENTS.md; rationale = universal first, domain refines; validate empirically in Phase 2. |
| `Get-Content -Raw` on Windows produces inconsistent line endings | Low | Low | Explicit `TrimEnd` + `\r\n` separator. Covered by automated setup merge test. |
| Domain rule duplicates a rule that's already in a plugin's SKILL.md | Low | Cosmetic | Admin discipline; reactive — remove if it causes ambiguity in practice. |

---

## Out of scope (explicit non-goals)

- **No JSON-driven generator.** No regeneration of CLAUDE.md from a structured
  rules file. Reconsider if drift becomes painful in practice — until then,
  premature.
- **No per-skill rows for multi-skill plugins.** One row/bullet per plugin.
- **No `plugins.json` schema extension.** No new `"invocation"` /
  `"triggers"` fields.
- **No upstream SKILL.md audit.** We don't read every installed skill's
  description to decide whether it needs an override; mandatory rules come
  from project opinion.
- **No auto-install of a pre-commit hook.** Documented for admins; opt-in.
- **No changes to Layer 3 (per-project `<project>/CLAUDE.md`) behavior.**
  Claude Code's native stacking handles it.

---

## Open questions (deferred to implementation discretion)

- **Lint v2: detect dead rules (entries pointing to plugins not in
  plugins.json).** Useful but not blocking; add after first dead-rule sighting.
- **Per-project CLAUDE.md merge handling.** `Copy-ClaudeMd` /
  `copy_claudemd` currently writes only the domain file to
  `<project>/CLAUDE.md`. Should it also merge core there? Default in this
  spec: yes — apply the same merge logic for parity. Confirm during
  implementation; flag if behavior should differ.
- **Order of optional sections within the contract.** This spec puts MANDATORY
  first, then Self-described, then Diagnostic. Confirm visual hierarchy at
  Phase 2 review.

---

## Acceptance criteria

This spec is implemented when:

1. `core/CLAUDE.md` contains a Global Invocation Contract section covering
   every `plugins.json.global[]` and `plugins.json.skills.global[]` entry.
2. Every `domains/<name>/CLAUDE.md` contains a Domain Invocation Contract
   covering its `plugins.json.domains.<name>[]` + `plugins.json.skills.<name>[]`
   entries.
3. `setup.ps1` and `setup.sh` merge core + chosen-domain into
   `~/.claude/CLAUDE.md` at install time.
4. `scripts/lint-invocation-tables.js` exists and exits 0 on the current
   repo state.
5. CI runs the lint on every push touching `plugins.json` or
   `**/CLAUDE.md`.
6. AGENTS.md documents the revised 500-line budget and the merge convention.
7. Project `CLAUDE.md` includes the "Plugins & invocation rules workflow"
   meta-rule.
8. Manual real-install smoke test on Windows passes (Phase 2).
