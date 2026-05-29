# Plugin Invocation Contracts — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the foundation for explicit plugin invocation contracts in CLAUDE.md: merge core+domain at setup, add Global contract to core, add Domain contract to embedded (proof-of-concept), build the lint script, and wire CI.

**Architecture:** Hand-authored markdown contract sections live in `core/CLAUDE.md` (global) and `domains/<name>/CLAUDE.md` (domain). `setup.ps1` / `setup.sh` concatenate the chosen domain's file with `core/CLAUDE.md` at install time, writing the merged result to `~/.claude/CLAUDE.md`. A Node-based lint script verifies each plugin in `plugins.json` is acknowledged in the matching CLAUDE.md; in Phase 1 it operates in **permissive mode** (skips domain files that have not yet received an Invocation Contract section). CI runs the lint on every PR touching `plugins.json` or `**/CLAUDE.md`.

**Tech Stack:** Markdown, PowerShell 5.1+, Bash 4+, Node.js (built-in `fs` / `path`), GitHub Actions YAML.

**Spec reference:** `docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md`

**Out of scope for Phase 1:** All 12 non-embedded domains' Invocation Contracts (Phase 3). Real-install smoke testing on Windows (Phase 2). Pre-commit hook installation (deferred indefinitely per spec).

---

## File structure for Phase 1

| Path | Action | Responsibility |
|---|---|---|
| `AGENTS.md` | Modify | Document the revised line-budget (300→500) and the core+domain merge convention. |
| `CLAUDE.md` (project root) | Modify | Add the "Plugins & invocation rules workflow" meta-rule for contributors. |
| `core/CLAUDE.md` | Modify (append) | Add the Global Plugin & Skill Invocation Contract section. |
| `domains/embedded/CLAUDE.md` | Modify (append) | Add the Domain Plugin & Skill Invocation Contract section as proof-of-concept. |
| `setup.ps1` | Modify | Change `Write-GlobalClaudeMd` and `Copy-ClaudeMd` to merge core+domain instead of copying domain alone. |
| `setup.sh` | Modify | Change `write_global_claudemd` and `copy_claudemd` to do the same merge. |
| `scripts/lint-invocation-tables.js` | Create | Node script: verifies every plugin in `plugins.json` is mentioned (as a backticked token) in the matching CLAUDE.md scope file. Permissive in Phase 1 — skips files that don't yet have a contract section. |
| `scripts/test-lint-invocation.sh` | Create | Bash tests for the lint script: clean repo passes, missing entry fails. |
| `scripts/test-setup.sh` | Modify | Add a test case for the core+domain merge (sentinel-based). |
| `.github/workflows/lint-invocation.yml` | Create | GitHub Actions workflow: runs lint on every push touching `plugins.json` or `**/CLAUDE.md`. |

---

## Task 1: Raise line-budget and document merge convention in AGENTS.md

**Files:**
- Modify: `AGENTS.md` (the "CLAUDE.md Rules (Three-Layer Design)" section, currently around lines 104-110)

- [ ] **Step 1.1: Inspect current AGENTS.md table**

```bash
grep -n -A 8 "CLAUDE.md Rules (Three-Layer Design)" AGENTS.md
```
Expected: a markdown table with three rows (Global, Domain, Project) and a "**Critical:** Combined total must stay under ~300 lines" line beneath it.

- [ ] **Step 1.2: Update the table values and the critical-line statement**

Use the Edit tool with this old_string:
```
### CLAUDE.md Rules (Three-Layer Design)
| Layer | Location | Max Lines | Purpose |
|---|---|---|---|
| 1 — Global | `core/CLAUDE.md` | ~150 | Company-wide guardrails, NDA check, universal do's/don'ts |
| 2 — Domain | `domains/<domain>/CLAUDE.md` | ~80 | Domain-specific rules (embedded, web, backend, data, devops, etc.) |
| 3 — Project | `<project>/CLAUDE.md` (template) | ~100 | Project-specific context, stack, known issues |

**Critical:** Combined total must stay under **~300 lines** to avoid Claude deprioritizing later content. Keep each layer tight and high-signal — verbose rules get ignored.
```
and this new_string:
```
### CLAUDE.md Rules (Three-Layer Design)
| Layer | Location | Max Lines | Purpose |
|---|---|---|---|
| 1 — Global | `core/CLAUDE.md` | ~230 | Company-wide guardrails, NDA check, universal do's/don'ts, **Global Plugin & Skill Invocation Contract** |
| 2 — Domain | `domains/<domain>/CLAUDE.md` | ~275 | Domain-specific rules (embedded, web, backend, data, devops, etc.), **Domain Plugin & Skill Invocation Contract** |
| 3 — Project | `<project>/CLAUDE.md` (template) | ~100 | Project-specific context, stack, known issues |

**Critical:** Combined total must stay under **~500 lines** to avoid Claude deprioritizing later content. Keep each layer tight and high-signal — verbose rules get ignored. (Previous target was ~300 lines; raised after empirical testing showed Claude reliably honors longer files. See `docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md`.)

**Layer 1 + Layer 2 merge at setup time.** `setup.ps1` and `setup.sh` concatenate `core/CLAUDE.md` + `domains/<chosen>/CLAUDE.md` (with a `---` separator) and write the result to `~/.claude/CLAUDE.md`. The user's installed file is the merge, not a single layer.
```

- [ ] **Step 1.3: Verify the edit landed and overall file is still well-formed**

```bash
grep -n "~/.claude/CLAUDE.md" AGENTS.md
wc -l AGENTS.md
```
Expected: grep returns at least one line referencing the merge; `wc -l` returns the same line count as before + ~4 (we added ~4 lines net).

- [ ] **Step 1.4: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): raise CLAUDE.md line budget 300->500, document core+domain merge

Reflects the spec at docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md:
- Layer 1 (core) max raised 150->230 to fit the Global Invocation Contract.
- Layer 2 (domain) max raised 80->275 to fit the Domain Invocation Contract
  alongside existing dense content (embedded toolchain tables, etc).
- Combined budget raised 300->500 to match what Claude Code reliably honors.
- Document that setup merges core + chosen-domain at install time."
```

---

## Task 2: Add Plugins workflow meta-rule to project CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (project root — currently contains "Environment Rules" and "MCP Tools: code-review-graph" sections)

- [ ] **Step 2.1: Inspect current file**

```bash
cat CLAUDE.md
```
Expected: starts with `# Environment Rules`, ends near line 54 with the `query_graph pattern="tests_for"` workflow note.

- [ ] **Step 2.2: Append the meta-rule section**

Use the Edit tool with this old_string (the last line of the current file plus a small amount of context to make it unique):
```
4. Use `query_graph` pattern="tests_for" to check coverage.
```
and this new_string:
```
4. Use `query_graph` pattern="tests_for" to check coverage.

---

## Plugins & invocation rules workflow

When adding or removing an entry in `plugins.json`, you MUST also update the
matching CLAUDE.md in the same commit:

- `global[]` or `skills.global[]`        → `core/CLAUDE.md`
- `domains.<name>[]` / `skills.<name>[]` → `domains/<name>/CLAUDE.md`

Every plugin/skill must appear in either the MANDATORY table or the
Self-described list of the matching CLAUDE.md.

CI runs `node scripts/lint-invocation-tables.js` which fails the build on
mismatches. Run it locally before commit:

```bash
node scripts/lint-invocation-tables.js
```

Do NOT put global plugin rules in domain files, or domain plugin rules in
core. The merge of core + chosen-domain happens at user setup time.

See `docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md`
for the full design.
```

- [ ] **Step 2.3: Verify**

```bash
grep -n "Plugins & invocation rules workflow" CLAUDE.md
wc -l CLAUDE.md
```
Expected: grep returns one line; `wc -l` returns previous count + ~22.

- [ ] **Step 2.4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): add Plugins & invocation rules workflow meta-rule

Tells contributors that any plugins.json edit must be paired with the
matching CLAUDE.md edit (core for global, domains/<name> for domain),
and that CI lint will fail the build on mismatches."
```

---

## Task 3: Build the lint script (TDD)

**Files:**
- Create: `scripts/lint-invocation-tables.js`
- Create: `scripts/test-lint-invocation.sh`

- [ ] **Step 3.1: Write the test file (failing — script doesn't exist yet)**

Create `scripts/test-lint-invocation.sh`:
```bash
#!/usr/bin/env bash
# Tests for scripts/lint-invocation-tables.js
# Exit 0 = all pass; exit 1 = at least one failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-invocation-tables.js"

fail=0
pass()  { echo "  PASS: $1"; }
oops()  { echo "  FAIL: $1"; fail=1; }

if [[ ! -f "$LINT" ]]; then
  echo "FAIL: lint script not found at $LINT"; exit 1
fi

# --- Test 1: clean repo state should pass ---
echo "Test 1: lint on current repo state"
if node "$LINT" >/tmp/lint-out 2>&1; then pass "exit 0 on clean repo"
else oops "exit non-zero on clean repo; output:"; cat /tmp/lint-out
fi

# --- Test 2: missing plugin entry should fail ---
echo "Test 2: lint with missing plugin entry"
TMP_REPO=$(mktemp -d)
cp -r "$REPO_ROOT/core" "$REPO_ROOT/domains" "$REPO_ROOT/plugins.json" "$REPO_ROOT/scripts" "$TMP_REPO/"
# Inject a fake plugin into the test copy's plugins.json
node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$TMP_REPO/plugins.json', 'utf8'));
cfg.global = cfg.global || [];
cfg.global.push({ name: 'definitely-not-a-real-plugin', marketplace: 'fake' });
fs.writeFileSync('$TMP_REPO/plugins.json', JSON.stringify(cfg, null, 2));
"
# Run lint against the tampered repo
(cd "$TMP_REPO" && node "$TMP_REPO/scripts/lint-invocation-tables.js" >/tmp/lint-out 2>&1)
rc=$?
if [[ $rc -ne 0 ]] && grep -q "definitely-not-a-real-plugin" /tmp/lint-out; then
  pass "exit non-zero with the missing plugin name in output"
else
  oops "expected exit non-zero AND 'definitely-not-a-real-plugin' in output; got rc=$rc, output:"
  cat /tmp/lint-out
fi
rm -rf "$TMP_REPO"

# --- Test 3: permissive mode — domain file with no contract section is skipped ---
echo "Test 3: domain file without contract section is skipped, not flagged"
TMP_REPO=$(mktemp -d)
cp -r "$REPO_ROOT/core" "$REPO_ROOT/domains" "$REPO_ROOT/plugins.json" "$REPO_ROOT/scripts" "$TMP_REPO/"
# 'web' likely has plugins but no contract section in Phase 1 — lint should NOT flag this
(cd "$TMP_REPO" && node "$TMP_REPO/scripts/lint-invocation-tables.js" >/tmp/lint-out 2>&1)
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "exit 0 — domains without contract section are skipped"
else
  oops "expected exit 0 in permissive mode; got rc=$rc, output:"
  cat /tmp/lint-out
fi
rm -rf "$TMP_REPO"

exit $fail
```

Make it executable:
```bash
chmod +x scripts/test-lint-invocation.sh
```

- [ ] **Step 3.2: Run the test, verify it fails**

```bash
bash scripts/test-lint-invocation.sh
```
Expected: `FAIL: lint script not found at .../scripts/lint-invocation-tables.js` and exit 1.

- [ ] **Step 3.3: Create the lint script**

Create `scripts/lint-invocation-tables.js`:
```javascript
#!/usr/bin/env node
// Verify every plugin/skill in plugins.json is acknowledged in the matching
// CLAUDE.md scope file.
//
// Scope routing:
//   plugins.json.global[]            → core/CLAUDE.md
//   plugins.json.skills.global[]     → core/CLAUDE.md
//   plugins.json.domains.<name>[]    → domains/<name>/CLAUDE.md
//   plugins.json.skills.<name>[]     → domains/<name>/CLAUDE.md
//
// Phase 1 permissive mode: a domain CLAUDE.md without a
// "## Plugin & Skill Invocation Contract" heading is SKIPPED, not flagged.
// Phase 3 (bulk rollout) will remove this skip behavior once every domain
// has a contract.
//
// Exit 0 = clean; exit 1 = at least one missing entry.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CONTRACT_HEADING = '## Plugin & Skill Invocation Contract';

function loadConfig() {
  const raw = fs.readFileSync(path.join(ROOT, 'plugins.json'), 'utf8');
  return JSON.parse(raw);
}

function collectExpected(config) {
  const expected = { global: new Set() };
  for (const p of config.global || [])             expected.global.add(p.name);
  for (const s of (config.skills?.global) || [])   expected.global.add(s.repo);

  for (const [dom, plugins] of Object.entries(config.domains || {})) {
    expected[dom] = expected[dom] || new Set();
    for (const p of plugins) expected[dom].add(p.name);
  }
  for (const [dom, skills] of Object.entries(config.skills || {})) {
    if (dom === 'global') continue;
    expected[dom] = expected[dom] || new Set();
    for (const s of skills) expected[dom].add(s.repo);
  }
  return expected;
}

function scopeFile(scope) {
  return scope === 'global'
    ? path.join(ROOT, 'core/CLAUDE.md')
    : path.join(ROOT, 'domains', scope, 'CLAUDE.md');
}

function backtickedTokenRegex(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('`' + escaped + '(:|`)');
}

function main() {
  const config = loadConfig();
  const expected = collectExpected(config);
  let failed = false;

  for (const [scope, names] of Object.entries(expected)) {
    const mdPath = scopeFile(scope);
    if (!fs.existsSync(mdPath)) {
      console.error(`MISSING FILE: ${mdPath} (referenced by plugins.json scope "${scope}")`);
      failed = true;
      continue;
    }
    const content = fs.readFileSync(mdPath, 'utf8');

    // Phase 1 permissive mode: skip if this file hasn't received an
    // Invocation Contract yet. Phase 3 removes this skip.
    if (!content.includes(CONTRACT_HEADING)) {
      console.log(`SKIP: ${path.relative(ROOT, mdPath)} has no "${CONTRACT_HEADING}" heading yet.`);
      continue;
    }

    for (const name of names) {
      const pattern = backtickedTokenRegex(name);
      if (!pattern.test(content)) {
        console.error(`MISSING: \`${name}\` not mentioned in ${path.relative(ROOT, mdPath)}`);
        failed = true;
      }
    }
  }

  process.exit(failed ? 1 : 0);
}

main();
```

- [ ] **Step 3.4: Run the test, verify all pass**

```bash
bash scripts/test-lint-invocation.sh
```
Expected output:
```
Test 1: lint on current repo state
  PASS: exit 0 on clean repo
Test 2: lint with missing plugin entry
  PASS: exit non-zero with the missing plugin name in output
Test 3: domain file without contract section is skipped, not flagged
  PASS: exit 0 — domains without contract section are skipped
```
And exit 0.

- [ ] **Step 3.5: Commit**

```bash
git add scripts/lint-invocation-tables.js scripts/test-lint-invocation.sh
git commit -m "feat(scripts): add lint-invocation-tables.js with TDD test harness

Lint verifies every plugin/skill in plugins.json is mentioned (as a
backticked token) in the matching CLAUDE.md:
- plugins.json.global / skills.global -> core/CLAUDE.md
- plugins.json.domains.<name> / skills.<name> -> domains/<name>/CLAUDE.md

Phase 1 permissive mode: a file without a '## Plugin & Skill Invocation
Contract' heading is skipped (not flagged), to support partial rollout.
Phase 3 (bulk rollout) will remove this skip.

scripts/test-lint-invocation.sh exercises three cases:
  1. clean repo state passes
  2. injected fake plugin causes failure with the plugin name in output
  3. domains without contract sections are skipped, not flagged"
```

---

## Task 4: Add Global Invocation Contract to core/CLAUDE.md

**Files:**
- Modify: `core/CLAUDE.md` (append at end)

- [ ] **Step 4.1: Verify contract section doesn't exist yet**

```bash
grep -n "Plugin & Skill Invocation Contract" core/CLAUDE.md
```
Expected: no output (the section doesn't exist).

- [ ] **Step 4.2: Append the contract section**

Use the Edit tool with this old_string (the very last paragraph of the file — it must be unique):
```
The worst outcome is a complete version of something that already exists as a
one-liner. The best outcome is a complete version of something nobody thought of
yet — because you searched, understood the landscape, and saw what others missed.
```
and this new_string:
```
The worst outcome is a complete version of something that already exists as a
one-liner. The best outcome is a complete version of something nobody thought of
yet — because you searched, understood the landscape, and saw what others missed.

---

## Plugin & Skill Invocation Contract — Global

These plugins ship with AI Sherpa globally. Reach for them by default; the rules
below override any defaults from their `SKILL.md` descriptions.

### MANDATORY — invoke without asking

| When the user…                                          | Invoke                                  | Why                                  |
|---------------------------------------------------------|-----------------------------------------|--------------------------------------|
| says "build a feature", "add X", or "modify behavior"   | `superpowers:brainstorming`             | Hard gate before any implementation  |
| asks to write tests for new code                        | `superpowers:test-driven-development`   | Test-first standard                  |
| asks for code review on current branch or a PR          | `superpowers:requesting-code-review`    | Mandatory pre-merge                  |

### Self-described — auto-fires for its listed use cases, no override needed

- `superpowers` — workflow skills (brainstorming, writing-plans, executing-plans, verification-before-completion, ...); the MANDATORY rules above cover the cases where this project has an opinion.
- `fullstack-dev-skills` — ~66 framework-specific skills (React, Next.js, FastAPI, Django, ...) that auto-activate when their context matches.
- `claude-mem` — persistent memory across sessions.
- `agent-browser` — browser automation tasks.

### Diagnostic — if a skill isn't firing when expected

1. Run `/plugin` — does it show `[ON]`?
2. Installed but not loaded? Run `/reload-plugins`.
3. Absent? Re-run AI Sherpa setup; check `[ACTION REQUIRED]` at the end.
```

- [ ] **Step 4.3: Run lint, verify it now checks core (and passes)**

```bash
node scripts/lint-invocation-tables.js
```
Expected: a "SKIP:" line for each domain without a contract section, but exit 0 (no "MISSING:" lines for core).

- [ ] **Step 4.4: Verify line count stays under budget**

```bash
wc -l core/CLAUDE.md
```
Expected: ~225 lines (was 195 + ~30 added). Must be ≤ 230 per AGENTS.md.

- [ ] **Step 4.5: Commit**

```bash
git add core/CLAUDE.md
git commit -m "feat(core): add Global Plugin & Skill Invocation Contract

Acknowledges every plugin in plugins.json.global[] and skills.global[]:
- superpowers (3 MANDATORY rules: brainstorming, TDD, code review)
- fullstack-dev-skills, claude-mem, agent-browser (Self-described)

Lint script verifies presence of each backticked plugin name."
```

---

## Task 5: Add Domain Invocation Contract to domains/embedded/CLAUDE.md

**Files:**
- Modify: `domains/embedded/CLAUDE.md` (append at end)

- [ ] **Step 5.1: Verify contract section doesn't exist yet**

```bash
grep -n "Plugin & Skill Invocation Contract" domains/embedded/CLAUDE.md
```
Expected: no output.

- [ ] **Step 5.2: Append the contract section, replacing the existing "Bundled Stack Skills" subsection (which the new contract supersedes)**

Use the Edit tool with this old_string:
```
## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin includes skills for **C/C++**
and **Rust** that auto-activate when working in those languages. No additional
install is needed. Mention the language explicitly in your prompt if a skill
isn't activating when you expect it to.
```
and this new_string:
```
## Plugin & Skill Invocation Contract — Domain (embedded)

These plugins ship for the embedded domain. Reach for them by default; the rules
below override any defaults from their `SKILL.md` descriptions.

### MANDATORY — invoke without asking

| When the user…                                                              | Invoke                  | Why                                                |
|-----------------------------------------------------------------------------|-------------------------|----------------------------------------------------|
| asks about Zephyr device-tree, kernel threads, `BIT`/`CONTAINER_OF`         | `zephyr-foundations`    | Reach for Zephyr-specific patterns first           |
| asks to set up or bring up a new custom board                               | `board-bringup`         | Hardware-aware skill; reads `board.yml` correctly  |
| asks about West workspace, manifest, or Sysbuild                            | `build-system`          | Zephyr-specific build-system knowledge             |
| asks about BLE GATT services / characteristics or `Send-When-Idle`          | `connectivity-ble`      | Embedded BLE patterns, including power-aware design |
| asks about sensors, GPIO, pinctrl, or peripheral fetch/get                  | `hardware-io`           | Sensor subsystem + Devicetree integration          |

### Self-described — auto-fires for its listed use cases, no override needed

- `antigravity-bundle-systems-programming` — systems-programming skills (C/C++/Rust focused) that auto-activate alongside `fullstack-dev-skills`.
- `beriberikix/zephyr-agent-skills` — 44 Zephyr RTOS skills (BLE, IP networking, USB/CAN, kernel basics + services, hardware I/O, multicore, native simulation, power/performance, security/updates, storage, testing/debugging, industrial protocols, IoT, board bringup, build system, devicetree, modules, specialized, Zephyr foundations) that auto-activate when their context matches.

The C/C++ and Rust skills from the globally-installed `fullstack-dev-skills` plugin also auto-activate in this domain.
```

- [ ] **Step 5.3: Run lint, verify embedded now checked and passing**

```bash
node scripts/lint-invocation-tables.js
```
Expected: exit 0; the SKIP for `domains/embedded/CLAUDE.md` is gone (since the heading is now there); no MISSING entries.

- [ ] **Step 5.4: Verify line count stays under budget**

```bash
wc -l domains/embedded/CLAUDE.md
```
Expected: ~180 lines (was 160 + ~25 contract − ~5 removed "Bundled Stack Skills"). Must be ≤ 275 per AGENTS.md.

- [ ] **Step 5.5: Commit**

```bash
git add domains/embedded/CLAUDE.md
git commit -m "feat(embedded): add Domain Plugin & Skill Invocation Contract

Proof-of-concept for the spec's domain contract pattern.

Replaces the vague 'Bundled Stack Skills' paragraph with:
- 5 MANDATORY invocation rules pointing at specific Zephyr skills
  (zephyr-foundations, board-bringup, build-system, connectivity-ble,
   hardware-io)
- Self-described list acknowledging antigravity-bundle-systems-programming
  and beriberikix/zephyr-agent-skills (44 skills) — matches what's in
  plugins.json.domains.embedded[] + plugins.json.skills.embedded[].

Lint passes for embedded after this change. Phase 3 will author the
remaining 12 domain contracts using this as the template."
```

---

## Task 6: Update setup.ps1 to merge core + domain

**Files:**
- Modify: `setup.ps1` — `Write-GlobalClaudeMd` function, and `Copy-ClaudeMd` function (project-level path)

- [ ] **Step 6.1: Locate `Write-GlobalClaudeMd`**

```bash
grep -n "function Write-GlobalClaudeMd" setup.ps1
```
Expected: one line number (currently around line 484 — verify before editing).

- [ ] **Step 6.2: Replace `Write-GlobalClaudeMd` with the merge version**

Use the Edit tool with this old_string (verify exact contents match before applying):
```
function Write-GlobalClaudeMd {
    param([string]$Domain)
    $source = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $source)) {
        Write-Err "Domain CLAUDE.md not found at: $source"
        exit 1
    }
    $claudeDir  = "$env:USERPROFILE\.claude"
    $target     = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    Copy-Item $source $target -Force
    Write-Info "Domain rules written to $target (active for all projects)"
}
```
and this new_string:
```
function Write-GlobalClaudeMd {
    param([string]$Domain)
    $core   = "$ScriptDir\core\CLAUDE.md"
    $domain = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    if (-not (Test-Path $domain)) {
        Write-Err "Domain CLAUDE.md not found at: $domain"
        exit 1
    }
    $claudeDir = "$env:USERPROFILE\.claude"
    $target    = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    # Merge: core rules first, then the chosen domain's rules. Universal guidance
    # reads first, domain refines on top. Separator makes the boundary obvious.
    $coreContent   = (Get-Content $core -Raw).TrimEnd()
    $domainContent = (Get-Content $domain -Raw)
    $merged = $coreContent + "`r`n`r`n---`r`n`r`n" + $domainContent
    Set-Content -Path $target -Value $merged -Encoding UTF8
    Write-Info "Merged core + $Domain rules written to $target (active for all projects)"
}
```

- [ ] **Step 6.3: Locate `Copy-ClaudeMd` and apply the same merge**

```bash
grep -n "function Copy-ClaudeMd" setup.ps1
```
Then use the Edit tool with this old_string:
```
function Copy-ClaudeMd {
    param([string]$Domain, [string]$ProjectType)
    $source = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $source)) {
        Write-Err "Domain CLAUDE.md not found at: $source"
        Write-Err "Is '$Domain' a valid domain? Valid: embedded, web, data, devops, marketing, sales, finance, service, procurement"
        exit 1
    }
    $target = "$(Get-Location)\CLAUDE.md"
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending domain rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---"
        Add-Content $target "<!-- AI Sherpa domain rules - do not edit below this line -->"
        Get-Content $source | Add-Content $target
    } else {
        Copy-Item $source $target -Force
    }
    Write-Info "Domain CLAUDE.md installed at $target"
}
```
and this new_string:
```
function Copy-ClaudeMd {
    param([string]$Domain, [string]$ProjectType)
    $core   = "$ScriptDir\core\CLAUDE.md"
    $domain = "$ScriptDir\domains\$Domain\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    if (-not (Test-Path $domain)) {
        Write-Err "Domain CLAUDE.md not found at: $domain"
        Write-Err "Is '$Domain' a valid domain? Valid: embedded, web, data, devops, marketing, sales, finance, service, procurement"
        exit 1
    }
    $target = "$(Get-Location)\CLAUDE.md"
    $coreContent   = (Get-Content $core -Raw).TrimEnd()
    $domainContent = (Get-Content $domain -Raw)
    $merged = $coreContent + "`r`n`r`n---`r`n`r`n" + $domainContent
    if ($ProjectType -eq "existing" -and (Test-Path $target)) {
        Write-Warn "Appending AI Sherpa rules to existing CLAUDE.md (original preserved)"
        Add-Content $target "`n---"
        Add-Content $target "<!-- AI Sherpa core + $Domain rules - do not edit below this line -->"
        Add-Content $target $merged
    } else {
        Set-Content -Path $target -Value $merged -Encoding UTF8
    }
    Write-Info "Merged core + $Domain CLAUDE.md installed at $target"
}
```

- [ ] **Step 6.4: PowerShell parse check**

```powershell
$tokens=$null; $errs=$null; [System.Management.Automation.Language.Parser]::ParseFile("setup.ps1", [ref]$tokens, [ref]$errs) | Out-Null; if ($errs -and $errs.Count) { 'PARSE ERRORS:'; $errs | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber)  $($_.Message)" } } else { 'OK - setup.ps1 parses cleanly' }
```
Expected: `OK - setup.ps1 parses cleanly`.

- [ ] **Step 6.5: Commit**

```bash
git add setup.ps1
git commit -m "feat(setup-ps1): merge core + domain CLAUDE.md at install time

Write-GlobalClaudeMd and Copy-ClaudeMd now concatenate core/CLAUDE.md +
domains/<chosen>/CLAUDE.md (separated by ---) into the target file
instead of copying only the domain layer.

Fixes the long-standing gap where AGENTS.md documented a three-layer
design but only Layer 2 (domain) was actually delivered to the user."
```

---

## Task 7: Update setup.sh to merge core + domain (with test)

**Files:**
- Modify: `setup.sh` — `write_global_claude_md` (around line 196-212) and `copy_claude_md` (around line 158-170)
- Modify: `scripts/test-setup.sh` — add merge test case

Note: the actual function names in `setup.sh` are `write_global_claude_md` and `copy_claude_md` (with `claude_md` not `claudemd`). The home directory variable is `$EFFECTIVE_HOME`, not `$HOME` — `$EFFECTIVE_HOME` is the WSL+Windows hybrid-aware variable that points at the Windows user's home in hybrid mode and the Linux home otherwise.

- [ ] **Step 7.1: Replace `write_global_claude_md` with the merge version**

Use the Edit tool with this old_string:
```
write_global_claude_md() {
  local domain="$1"
  local source="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$source" ]]; then
    log_error "Domain CLAUDE.md not found at: $source"
    exit 1
  fi
  local claude_dir="$EFFECTIVE_HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.bak"
    log_warn "Backed up existing $target to $target.bak"
  fi
  cp "$source" "$target"
  log_info "Domain rules written to $target (active for all projects)"
}
```
and this new_string:
```
write_global_claude_md() {
  local domain="$1"
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  if [[ ! -f "$domain_md" ]]; then
    log_error "Domain CLAUDE.md not found at: $domain_md"
    exit 1
  fi
  local claude_dir="$EFFECTIVE_HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.bak"
    log_warn "Backed up existing $target to $target.bak"
  fi
  # Merge: core (universal) first, then the chosen domain's rules.
  # Universal guidance reads first; domain refines on top.
  {
    cat "$core_md"
    printf '\n\n---\n\n'
    cat "$domain_md"
  } > "$target"
  log_info "Merged core + $domain rules written to $target ($(wc -l < "$target") lines)"
}
```

- [ ] **Step 7.2: Replace `copy_claude_md` with the merge version**

Use the Edit tool with this old_string:
```
copy_claude_md() {
  local domain="$1" project_type="$2"
  local source="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending domain rules to existing CLAUDE.md (original preserved)"
    printf '\n---\n<!-- AI Sherpa domain rules — do not edit below this line -->\n' >> "$target"
    cat "$source" >> "$target"
  else
    cp "$source" "$target"
  fi
  log_info "Domain CLAUDE.md installed at $target"
}
```
and this new_string:
```
copy_claude_md() {
  local domain="$1" project_type="$2"
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  local domain_md="$SCRIPT_DIR/domains/$domain/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  if [[ ! -f "$domain_md" ]]; then
    log_error "Domain CLAUDE.md not found at: $domain_md"
    exit 1
  fi
  local target="$PWD/CLAUDE.md"
  if [[ "$project_type" == "existing" && -f "$target" ]]; then
    log_warn "Appending AI Sherpa rules to existing CLAUDE.md (original preserved)"
    {
      printf '\n---\n'
      echo "<!-- AI Sherpa core + $domain rules — do not edit below this line -->"
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } >> "$target"
  else
    {
      cat "$core_md"
      printf '\n\n---\n\n'
      cat "$domain_md"
    } > "$target"
  fi
  log_info "Merged core + $domain CLAUDE.md installed at $target"
}
```

- [ ] **Step 7.4: Bash syntax check**

```bash
bash -n setup.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 7.3: Bash syntax check**

```bash
bash -n setup.sh && echo OK
```
Expected: `OK`.

- [ ] **Step 7.4: Add a merge test case to scripts/test-setup.sh**

`scripts/test-setup.sh` already sources `setup.sh` at the top (line 27) so all helper functions are available in the test shell. The existing tests follow this pattern: redirect `HOME` and `EFFECTIVE_HOME` to a tempdir, call the function, assert, clean up. Append this test at the end of the file (before any final `exit` if one exists; otherwise just at the end):
```bash

# --- Test: write_global_claude_md merges core + chosen domain ---
echo "=== Test: write_global_claude_md merges core + chosen domain ==="
TMP=$(mktemp -d)
mkdir -p "$TMP/core" "$TMP/domains/embedded"
echo "__CORE_SENTINEL__"   > "$TMP/core/CLAUDE.md"
echo "__DOMAIN_SENTINEL__" > "$TMP/domains/embedded/CLAUDE.md"
SCRIPT_DIR_BAK="$SCRIPT_DIR"
EFFECTIVE_HOME_BAK="$EFFECTIVE_HOME"
HOME_BAK="$HOME"
SCRIPT_DIR="$TMP"
HOME="$TMP/home"
EFFECTIVE_HOME="$TMP/home"
mkdir -p "$EFFECTIVE_HOME/.claude"

write_global_claude_md embedded

merged="$EFFECTIVE_HOME/.claude/CLAUDE.md"
assert_file_exists "merged CLAUDE.md written" "$merged"
assert_file_contains "merged file contains core sentinel"   "$merged" "__CORE_SENTINEL__"
assert_file_contains "merged file contains domain sentinel" "$merged" "__DOMAIN_SENTINEL__"
assert_file_contains "merged file contains --- separator"   "$merged" "^---\$"

# Re-run with a pre-existing target → backup must be created
write_global_claude_md embedded
assert_file_exists ".bak created on re-run" "${merged}.bak"

SCRIPT_DIR="$SCRIPT_DIR_BAK"
EFFECTIVE_HOME="$EFFECTIVE_HOME_BAK"
HOME="$HOME_BAK"
rm -rf "$TMP"
```

- [ ] **Step 7.5: Run scripts/test-setup.sh, verify pass**

```bash
bash scripts/test-setup.sh
```
Expected: all existing tests still pass + the new merge tests (4 new PASS lines: written, core sentinel, domain sentinel, separator) + the .bak test. Final exit 0.

- [ ] **Step 7.6: Commit**

```bash
git add setup.sh scripts/test-setup.sh
git commit -m "feat(setup-sh): merge core + domain CLAUDE.md at install time

write_global_claude_md and copy_claude_md now concatenate core/CLAUDE.md +
domains/<chosen>/CLAUDE.md (separated by ---) into the target file
instead of copying only the domain layer.

scripts/test-setup.sh adds sentinel-based merge tests verifying both
core and domain content land in the target file separated by ---, and
that re-running with a pre-existing target creates the .bak."
```

---

## Task 8: Wire lint into CI

**Files:**
- Create: `.github/workflows/lint-invocation.yml`

- [ ] **Step 8.1: Verify the workflows directory doesn't exist yet**

```bash
ls .github/workflows/ 2>&1 || echo "missing as expected"
```
Expected: "missing as expected" (or a "No such file" error).

- [ ] **Step 8.2: Create the directory and the workflow file**

```bash
mkdir -p .github/workflows
```
Then create `.github/workflows/lint-invocation.yml`:
```yaml
name: Lint invocation contracts

on:
  pull_request:
    paths:
      - 'plugins.json'
      - 'core/CLAUDE.md'
      - 'domains/**/CLAUDE.md'
      - 'scripts/lint-invocation-tables.js'
      - '.github/workflows/lint-invocation.yml'
  push:
    branches:
      - master
    paths:
      - 'plugins.json'
      - 'core/CLAUDE.md'
      - 'domains/**/CLAUDE.md'
      - 'scripts/lint-invocation-tables.js'
      - '.github/workflows/lint-invocation.yml'

jobs:
  lint:
    name: Verify plugins.json ↔ CLAUDE.md sync
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Run lint
        run: node scripts/lint-invocation-tables.js
      - name: Run lint self-tests
        run: bash scripts/test-lint-invocation.sh
```

- [ ] **Step 8.3: Verify YAML is syntactically well-formed**

```bash
node -e "const y=require('fs').readFileSync('.github/workflows/lint-invocation.yml','utf8'); /^[a-z]/i.test(y) && console.log('YAML opens with expected token')"
```
Expected: `YAML opens with expected token`. (Full YAML validation happens on GitHub when the workflow is pushed.)

- [ ] **Step 8.4: Sanity-run the same command CI will run**

```bash
node scripts/lint-invocation-tables.js
bash scripts/test-lint-invocation.sh
```
Expected: both exit 0.

- [ ] **Step 8.5: Commit and push**

```bash
git add .github/workflows/lint-invocation.yml
git commit -m "ci: lint invocation contracts on PR + master push

Runs node scripts/lint-invocation-tables.js + the bash test harness
whenever plugins.json or any CLAUDE.md changes. Fails the build on
plugins.json <-> CLAUDE.md mismatches.

In Phase 1 the lint runs in permissive mode (domain files without an
Invocation Contract section are skipped). Phase 3 will remove that
permissiveness once every domain has a contract."
git push
```

- [ ] **Step 8.6: Open the PR (or the master push) on GitHub and confirm the workflow ran green**

Navigate to the Actions tab on github.com/ccjain/AI-Sherpa-Setup. Confirm the "Lint invocation contracts" workflow appears and shows a green check on this commit.

---

## End-of-phase verification

After all eight tasks, run this end-to-end check:

```bash
# 1. Lint passes
node scripts/lint-invocation-tables.js

# 2. Lint tests pass
bash scripts/test-lint-invocation.sh

# 3. Setup tests pass (including the new merge test)
bash scripts/test-setup.sh

# 4. Line counts within budget
wc -l core/CLAUDE.md domains/embedded/CLAUDE.md
# Expected: core <=230, embedded <=275

# 5. setup.ps1 still parses
pwsh -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('setup.ps1', [ref]\$null, [ref]\$null) | Out-Null; 'OK'"

# 6. setup.sh still parses
bash -n setup.sh && echo OK
```

Phase 1 is complete when all six checks pass and the GitHub Actions workflow shows green on the merge commit.

---

## What's next (Phase 2 and 3)

- **Phase 2 (separate plan): Verify on embedded end-to-end.** Real-install smoke test on a clean Windows VM — run `setup.bat`, choose embedded, inspect `~/.claude/CLAUDE.md`, then test that Claude Code actually invokes `superpowers:brainstorming` on a "build a feature" prompt per the new MANDATORY rule.
- **Phase 3 (separate plan): Bulk rollout to 12 remaining domains.** Author Domain Invocation Contracts for web, ai, frontend, devops, marketing, sales, finance, service, procurement, data, backend, uiux. After all 13 contracts exist, remove the permissive-mode skip from `lint-invocation-tables.js` so missing contracts become hard errors.

Do NOT pull Phase 2 or Phase 3 work into this Phase 1 plan.
