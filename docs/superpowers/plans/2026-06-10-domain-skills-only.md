# Domain Skills Only — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop the 8 active `domains/<name>/CLAUDE.md` files, replace each with a single `domains/<name>/SKILL.md` skill installed under `~/.claude/skills/ai-sherpa-<name>/`, and stop concatenating domain rules into `~/.claude/CLAUDE.md`.

**Architecture:** One broadly-described skill per active domain. Setup script writes core-only to `~/.claude/CLAUDE.md` and copies every `domains/<name>/SKILL.md` from the repo into `~/.claude/skills/ai-sherpa-<name>/`. Disabled domains keep their CLAUDE.md files untouched. Lint script conditionally reads SKILL.md for non-disabled domains and adds a frontmatter sanity check.

**Tech Stack:** PowerShell (`setup.ps1`), Bash (`setup.sh`, `scripts/test-setup.sh`), Node.js (`scripts/lint-invocation-tables.js`), Markdown + YAML frontmatter (skill files), JSON (`plugins.json`).

**Spec:** `docs/superpowers/specs/2026-06-10-domain-skills-only-design.md`

**8 active domains in scope:** `ai`, `backend`, `data`, `devops`, `embedded`, `frontend`, `uiux`, `web`.

**5 disabled domains untouched:** `finance`, `marketing`, `procurement`, `sales`, `service`.

---

### Task 1: Canonical skill descriptions (the highest-stakes step)

The description field is the single most important property of each skill — lazy-loaded guardrails fire if and only if the description matches the user's task. This task locks in the canonical descriptions used by every following task.

**Files:**
- Create: `docs/superpowers/plans/2026-06-10-domain-skills-descriptions.md` (reference table; the descriptions will be copy-pasted into each SKILL.md in Task 3 / Task 4)

- [ ] **Step 1: Write the description table**

Create `docs/superpowers/plans/2026-06-10-domain-skills-descriptions.md` with the following exact content. Each description follows the pattern "Use when working on … — &lt;framework/keyword enumeration&gt;. Provides &lt;what guardrails this skill carries&gt;." Keep the description on a single line (Markdown YAML frontmatter requires this for the field to parse cleanly).

```markdown
# Canonical Skill Descriptions — ai-sherpa-<domain>

These exact one-line descriptions go into the `description:` frontmatter field of each `domains/<name>/SKILL.md`. Authored 2026-06-10 alongside `2026-06-10-domain-skills-only-design.md`. Update here AND in the SKILL.md when changing.

| Skill name | Description (single line) |
|---|---|
| `ai-sherpa-ai` | Use when working on any AI / LLM application task — Claude API, OpenAI, Anthropic SDK, RAG, vector database, embeddings, agent orchestration, prompt engineering, evals, MLOps, model training, fine-tuning, LangChain. Provides AI-specific guardrails and effectiveness boundaries. |
| `ai-sherpa-backend` | Use when working on any backend service task — REST API, GraphQL, gRPC, microservice, database, ORM, queue, message broker, auth, session, JWT, server-side, business logic, Node.js, Express, FastAPI, Django, Spring, .NET. Provides backend security guardrails and framework conventions. |
| `ai-sherpa-data` | Use when working on any data engineering / data science task — SQL, NoSQL, dbt, Spark, Airflow, pandas, ETL, data pipeline, data warehouse, data lake, schema migration, data quality, analytics, machine learning model. Provides data-handling guardrails and pipeline conventions. |
| `ai-sherpa-devops` | Use when working on any DevOps / platform / SRE task — Kubernetes, Helm, Terraform, Ansible, CI/CD, GitOps, ArgoCD, observability, Prometheus, Grafana, incident response, on-call, cloud infrastructure, AWS, GCP, Azure. Provides infrastructure-as-code guardrails and operational conventions. |
| `ai-sherpa-embedded` | Use when working on any embedded / firmware / RTOS task — C, C++, Zephyr, FreeRTOS, bare-metal, MCU, microcontroller, board bringup, devicetree, Kconfig, GPIO, sensor, BLE, CAN, USB, flashing, JLink, OpenOCD, MISRA, hardware, peripheral, interrupt. Provides toolchain lookup, hardware constraints, and embedded-specific patterns. |
| `ai-sherpa-frontend` | Use when working on any frontend / UI accessibility / performance task — React, Vue, Angular, Next.js, Svelte, HTML, CSS, Tailwind, shadcn, accessibility, a11y, WCAG, ARIA, Core Web Vitals, responsive design, component library, design system. Provides accessibility guardrails and frontend security rules. |
| `ai-sherpa-uiux` | Use when working on any UI design / UX task — wireframe, mockup, prototype, Figma, design system, design tokens, user research, usability, information architecture, visual design, interaction design, design review. Provides UI/UX design conventions and review patterns. |
| `ai-sherpa-web` | Use when working on any full-stack web task — React, Vue, Angular, Next.js, Node.js, Express, FastAPI, Django, Spring, .NET, HTML, CSS, Tailwind, shadcn, frontend, backend, API endpoint, component, accessibility, UI, form, authentication. Provides full-stack security guardrails, accessibility rules, and framework conventions. |

## Description-writing rule

Each description must enumerate the domain's framework and keyword vocabulary broadly enough that any task in the domain triggers the skill. If a description turns out to under-fire in practice, broaden it in a follow-up PR (Risk #1 in the spec).
```

- [ ] **Step 2: Commit the descriptions reference**

```bash
git add docs/superpowers/plans/2026-06-10-domain-skills-descriptions.md
git commit -m "docs(plan): canonical skill descriptions for ai-sherpa-<domain> skills"
```

---

### Task 2: Update lint script (path swap + frontmatter check)

The lint script must read `domains/<name>/SKILL.md` for non-disabled domains while continuing to read `CLAUDE.md` for disabled domains. It also gains a new check: any SKILL.md it opens must have valid YAML frontmatter with `name:` and `description:`.

**Files:**
- Modify: `scripts/lint-invocation-tables.js`

- [ ] **Step 1: Create a temporary SKILL.md fixture and run lint to confirm it fails**

Before touching the script, create a temporary SKILL.md fixture for `domains/embedded/SKILL.md` (do NOT delete the CLAUDE.md yet) with this exact content:

```markdown
---
name: ai-sherpa-embedded
description: Lint fixture — to be replaced in Task 3.
---

# AI Sherpa — Embedded Software Rules

## Plugin & Skill Invocation Contract

### MANDATORY

| When the user… | Invoke | Why |
|---|---|---|
| asks about Zephyr device-tree | `zephyr-foundations` | placeholder |
| asks to set up custom board | `board-bringup` | placeholder |
| asks about BLE GATT | `connectivity-ble` | placeholder |
| asks about sensors / GPIO | `hardware-io` | placeholder |
| asks about West / Sysbuild | `build-system` | placeholder |
```

Run:

```bash
node scripts/lint-invocation-tables.js
```

Expected: exits 0 because lint still reads `domains/embedded/CLAUDE.md`, not the new SKILL.md. The SKILL.md fixture is invisible to lint at this point. Note this — it confirms the current path behavior.

- [ ] **Step 2: Modify `scopeFile` and add frontmatter check**

Open `scripts/lint-invocation-tables.js` and apply these changes:

Replace lines 5-14 (the header comment) with:

```javascript
// Verify every plugin/skill in plugins.json is acknowledged in the matching
// scope file.
//
// Scope routing:
//   plugins.json.global[]            → core/CLAUDE.md
//   plugins.json.skills.global[]     → core/CLAUDE.md
//   plugins.json.domains.<name>[]    → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
//   plugins.json.skills.<name>[]     → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
//
// Phase 1 permissive mode: a file without a
// "## Plugin & Skill Invocation Contract" heading is SKIPPED, not flagged.
// Phase 3 (bulk rollout) will remove this skip behavior once every domain
// has a contract.
//
// SKILL.md files must additionally have valid YAML frontmatter with `name:`
// and `description:` fields. Missing or malformed frontmatter is a hard error.
//
// Exit 0 = clean; exit 1 = at least one missing entry or malformed frontmatter.
```

Replace the `scopeFile(scope)` function (lines 46-50) with:

```javascript
function scopeFile(scope, disabledSet) {
  if (scope === 'global') return path.join(ROOT, 'core/CLAUDE.md');
  const filename = disabledSet.has(scope) ? 'CLAUDE.md' : 'SKILL.md';
  return path.join(ROOT, 'domains', scope, filename);
}
```

Add this helper function immediately after `backtickedTokenRegex` (around line 56):

```javascript
function validateFrontmatter(content, relPath) {
  if (!content.startsWith('---\n') && !content.startsWith('---\r\n')) {
    return `MALFORMED FRONTMATTER: ${relPath} does not start with '---' line`;
  }
  const endMatch = content.match(/\r?\n---\r?\n/);
  if (!endMatch) {
    return `MALFORMED FRONTMATTER: ${relPath} has no closing '---' line`;
  }
  const fmEnd = endMatch.index + endMatch[0].length;
  const fm = content.slice(0, fmEnd);
  if (!/^name:\s*\S/m.test(fm)) {
    return `MALFORMED FRONTMATTER: ${relPath} missing 'name:' field`;
  }
  if (!/^description:\s*\S/m.test(fm)) {
    return `MALFORMED FRONTMATTER: ${relPath} missing 'description:' field`;
  }
  return null;
}
```

Replace the `main()` function (lines 57-88) with:

```javascript
function main() {
  const config = loadConfig();
  const expected = collectExpected(config);
  const disabledSet = new Set(config.disabled_domains || []);
  let failed = false;

  for (const [scope, names] of Object.entries(expected)) {
    const mdPath = scopeFile(scope, disabledSet);
    if (!fs.existsSync(mdPath)) {
      console.error(`MISSING FILE: ${mdPath} (referenced by plugins.json scope "${scope}")`);
      failed = true;
      continue;
    }
    const content = fs.readFileSync(mdPath, 'utf8');

    // Frontmatter check applies only to SKILL.md files.
    if (mdPath.endsWith(`${path.sep}SKILL.md`) || mdPath.endsWith('/SKILL.md')) {
      const err = validateFrontmatter(content, path.relative(ROOT, mdPath));
      if (err) {
        console.error(err);
        failed = true;
        continue;
      }
    }

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
```

- [ ] **Step 3: Run lint against the temporary fixture**

```bash
node scripts/lint-invocation-tables.js
```

Expected: emits multiple `MISSING: ...` errors for `domains/embedded/SKILL.md` because the placeholder contract table doesn't mention the actual plugin names from `plugins.json`. Exit 1.

This confirms: (a) lint now reads SKILL.md for `embedded` (not in disabled_domains), (b) frontmatter validates because the fixture has valid frontmatter.

- [ ] **Step 4: Delete the temporary fixture**

```bash
rm "domains/embedded/SKILL.md"
```

(The real SKILL.md will be written in Task 3.)

- [ ] **Step 5: Run lint to confirm green state**

```bash
node scripts/lint-invocation-tables.js
```

Expected: exits 0. Lint falls back to reading `domains/embedded/CLAUDE.md` (which still has the real contract) for the embedded scope, and all other domains are unchanged.

- [ ] **Step 6: Commit the lint update**

```bash
git add scripts/lint-invocation-tables.js
git commit -m "feat(lint): read SKILL.md for non-disabled domains + validate frontmatter

Conditional file path: domains in plugins.json.disabled_domains continue
to be read as CLAUDE.md; all other domain scopes now expect SKILL.md.
SKILL.md files are validated to have YAML frontmatter with name: and
description: fields before the existing contract-body checks run."
```

---

### Task 3: Convert `embedded` domain (pilot)

Embedded is the pilot because it has the most distinctive content (toolchain JSON lookup, hardware constraints). Doing it first validates the conversion pattern on real complex content.

**Files:**
- Create: `domains/embedded/SKILL.md`
- Delete: `domains/embedded/CLAUDE.md`

- [ ] **Step 1: Capture the current `domains/embedded/CLAUDE.md` content**

Read the file exactly as it stands today; we'll prepend frontmatter and a one-line global-rules pointer, but the rest of the body is verbatim.

```bash
cat "domains/embedded/CLAUDE.md"
```

Note the existing H1 (`# AI Sherpa — Embedded Software Rules`) and the second paragraph "These rules apply to all embedded software projects (C/C++, firmware, RTOS). They extend the global rules in core/CLAUDE.md — do not remove global rules."

- [ ] **Step 2: Write `domains/embedded/SKILL.md`**

Use this exact frontmatter (copied from Task 1's description table). Then keep the H1, replace the existing "These rules apply to all embedded software projects... extend the global rules in core/CLAUDE.md — do not remove global rules." paragraph with the new one-line pointer, and preserve EVERY other line of the body verbatim (all sections from "Architecture Check (Before Every Embedded Task)" through "Plugin & Skill Invocation Contract — Domain (embedded)" and its tables).

```markdown
---
name: ai-sherpa-embedded
description: Use when working on any embedded / firmware / RTOS task — C, C++, Zephyr, FreeRTOS, bare-metal, MCU, microcontroller, board bringup, devicetree, Kconfig, GPIO, sensor, BLE, CAN, USB, flashing, JLink, OpenOCD, MISRA, hardware, peripheral, interrupt. Provides toolchain lookup, hardware constraints, and embedded-specific patterns.
---

# AI Sherpa — Embedded Software Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

<-- The rest of the body is the existing domains/embedded/CLAUDE.md content
     starting from "## Architecture Check (Before Every Embedded Task)"
     through the end of the file, verbatim. Do not edit any rule. -->
```

The comment in `<-- ... -->` is a placeholder for the engineer — replace it with the actual verbatim content from the existing CLAUDE.md (sections "Architecture Check (Before Every Embedded Task)" onward). The cleanest way is:

```bash
# Extract body starting from the first "##" heading (which is "Architecture Check…")
awk '/^## /{found=1} found' "domains/embedded/CLAUDE.md" > /tmp/embedded-body.md
# Then prepend the frontmatter + H1 + pointer line to the SKILL.md and concatenate
{
  cat <<'EOF'
---
name: ai-sherpa-embedded
description: Use when working on any embedded / firmware / RTOS task — C, C++, Zephyr, FreeRTOS, bare-metal, MCU, microcontroller, board bringup, devicetree, Kconfig, GPIO, sensor, BLE, CAN, USB, flashing, JLink, OpenOCD, MISRA, hardware, peripheral, interrupt. Provides toolchain lookup, hardware constraints, and embedded-specific patterns.
---

# AI Sherpa — Embedded Software Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

EOF
  cat /tmp/embedded-body.md
} > "domains/embedded/SKILL.md"
rm /tmp/embedded-body.md
```

- [ ] **Step 3: Delete the old `domains/embedded/CLAUDE.md`**

```bash
git rm "domains/embedded/CLAUDE.md"
```

- [ ] **Step 4: Run lint and verify it passes**

```bash
node scripts/lint-invocation-tables.js
```

Expected: exits 0. Lint now reads `domains/embedded/SKILL.md`, validates frontmatter, finds the contract heading, and verifies every plugin name from `plugins.json.domains.embedded` (currently `antigravity-bundle-systems-programming`) and `plugins.json.skills.embedded` (currently `beriberikix/zephyr-agent-skills`) is mentioned in the body.

If lint fails with `MISSING: ...`, the body did not preserve the existing invocation contract table — re-check Step 2.

- [ ] **Step 5: Commit the embedded conversion**

```bash
git add "domains/embedded/SKILL.md"
git commit -m "feat(domains): convert embedded to ai-sherpa-embedded skill

Replaces domains/embedded/CLAUDE.md with domains/embedded/SKILL.md
(YAML frontmatter + verbatim body). Setup script changes that wire the
skill into ~/.claude/skills/ land in a later task; for now, lint passes
and the file is in place."
```

---

### Task 4: Convert the remaining 7 domains in batch

Same mechanical conversion as Task 3 for: `ai`, `backend`, `data`, `devops`, `frontend`, `uiux`, `web`. Each conversion is identical in structure — only the frontmatter description and the body content differ. The description for each comes from Task 1's reference table.

**Files (per domain):**
- Create: `domains/<name>/SKILL.md`
- Delete: `domains/<name>/CLAUDE.md`

- [ ] **Step 1: Convert each domain**

For each domain in `ai backend data devops frontend uiux web`, in order:

1. Read `domains/<name>/CLAUDE.md`.
2. Copy the canonical description for `ai-sherpa-<name>` from `docs/superpowers/plans/2026-06-10-domain-skills-descriptions.md` (Task 1).
3. Write `domains/<name>/SKILL.md` using the same template as Task 3 Step 2: YAML frontmatter + the existing H1 + the one-line pointer ("These rules apply in addition to the global guidelines in `core/CLAUDE.md`.") + the body verbatim starting from the first `## ` heading in the original.
4. `git rm "domains/<name>/CLAUDE.md"`.
5. Run `node scripts/lint-invocation-tables.js` and confirm exit 0.

Bash one-liner that applies the pattern to all 7 (assumes the descriptions file from Task 1 is on disk):

```bash
for d in ai backend data devops frontend uiux web; do
  desc=$(grep -E "^\| \`ai-sherpa-$d\`" docs/superpowers/plans/2026-06-10-domain-skills-descriptions.md \
         | sed -E 's/^\| `ai-sherpa-[^`]+` \| //; s/ \|$//')
  # Extract H1 line (preserve original wording)
  h1=$(grep -E '^# ' "domains/$d/CLAUDE.md" | head -1)
  # Body starts from the first ## heading
  awk '/^## /{found=1} found' "domains/$d/CLAUDE.md" > "/tmp/$d-body.md"
  {
    echo "---"
    echo "name: ai-sherpa-$d"
    echo "description: $desc"
    echo "---"
    echo ""
    echo "$h1"
    echo ""
    echo "These rules apply in addition to the global guidelines in \`core/CLAUDE.md\`."
    echo ""
    cat "/tmp/$d-body.md"
  } > "domains/$d/SKILL.md"
  rm "/tmp/$d-body.md"
  git rm "domains/$d/CLAUDE.md"
  echo "Converted $d"
done

node scripts/lint-invocation-tables.js
```

Expected lint output: exit 0. If a domain fails lint with `MISSING: ...`, that domain's original CLAUDE.md didn't have its plugin names in the contract table — investigate that specific domain's body before proceeding.

- [ ] **Step 2: Manually inspect each new SKILL.md**

For each of the 7, open `domains/<name>/SKILL.md` and verify:
- Frontmatter is intact (`---\nname: ai-sherpa-<name>\ndescription: …\n---`).
- The H1 heading is preserved.
- The "These rules apply in addition to..." pointer line is present.
- The body sections (Always Do / Never Do / contract tables / etc.) are present and not truncated.

Eyeball check; no scripted assertion.

- [ ] **Step 3: Confirm no stray domain CLAUDE.md remain among the 8 active ones**

```bash
ls domains/{ai,backend,data,devops,embedded,frontend,uiux,web}/CLAUDE.md 2>/dev/null
```

Expected: empty output (all 8 are gone).

```bash
ls domains/{finance,marketing,procurement,sales,service}/CLAUDE.md
```

Expected: all 5 listed (disabled domains untouched).

- [ ] **Step 4: Commit the batch conversion**

```bash
git add domains/{ai,backend,data,devops,frontend,uiux,web}/SKILL.md
git commit -m "feat(domains): convert remaining 7 active domains to ai-sherpa-<name> skills

ai, backend, data, devops, frontend, uiux, web. Same conversion pattern
as the embedded pilot: frontmatter + verbatim body. The 5 disabled
domains (finance, marketing, procurement, sales, service) keep their
CLAUDE.md files untouched."
```

---

### Task 5: Update `setup.sh` — drop domain concat, add `install_ai_sherpa_skills`, uninstall cleanup

**Files:**
- Modify: `setup.sh:210-237` (function `write_global_claude_md`)
- Modify: `setup.sh:1422-1576` (function `run_uninstall`)
- Modify: `setup.sh:1700-1709` (the install pass in `main`)
- Create new function: `install_ai_sherpa_skills` inside `setup.sh`

- [ ] **Step 1: Replace `write_global_claude_md` (lines 210-237)**

Replace the entire existing function body with this. It now takes no arguments and writes only `core/CLAUDE.md`.

```bash
write_global_claude_md() {
  local core_md="$SCRIPT_DIR/core/CLAUDE.md"
  if [[ ! -f "$core_md" ]]; then
    log_error "core/CLAUDE.md not found at: $core_md"
    exit 1
  fi
  local claude_dir="$EFFECTIVE_HOME/.claude"
  local target="$claude_dir/CLAUDE.md"
  mkdir -p "$claude_dir"
  if [[ -f "$target" ]]; then
    cp "$target" "${target}.bak"
    log_warn "Backed up existing $target to $target.bak"
  fi
  # Global rules only. Domain-specific rules live in ai-sherpa-<domain> skills
  # under ~/.claude/skills/ and load progressively when their description matches.
  cp "$core_md" "$target"
  log_info "core rules written to $target ($(wc -l < "$target") lines)"
}
```

- [ ] **Step 2: Add the new `install_ai_sherpa_skills` function**

Add this new function immediately after `install_skills` (i.e. after line 534, before `print_summary`):

```bash
# Copy each domains/<name>/SKILL.md from the repo into
# ~/.claude/skills/ai-sherpa-<name>/SKILL.md. Skips domains listed in
# plugins.json.disabled_domains. Idempotent; overwrites on re-run.
install_ai_sherpa_skills() {
  local config_file="$SCRIPT_DIR/plugins.json"
  local skills_dir="$EFFECTIVE_HOME/.claude/skills"
  mkdir -p "$skills_dir"

  # Read disabled_domains from plugins.json
  local disabled
  if [[ -f "$config_file" ]]; then
    disabled=$(node -e "
let raw='';process.stdin.setEncoding('utf8');
process.stdin.on('data',d=>raw+=d);
process.stdin.on('end',()=>{
  try{const c=JSON.parse(raw);(c.disabled_domains||[]).forEach(n=>process.stdout.write(n+'\n'))}catch(e){}
});
" < "$config_file")
  fi

  local installed=0
  for dir in "$SCRIPT_DIR/domains"/*/; do
    [[ -d "$dir" ]] || continue
    local name
    name=$(basename "$dir")
    # Skip disabled domains
    if echo "$disabled" | grep -qxF "$name"; then
      log_info "  [SKIP]   ai-sherpa-$name (disabled_domains)"
      continue
    fi
    local src="$dir/SKILL.md"
    if [[ ! -f "$src" ]]; then
      continue
    fi
    local target_dir="$skills_dir/ai-sherpa-$name"
    mkdir -p "$target_dir"
    cp -f "$src" "$target_dir/SKILL.md"
    log_info "  [READY]  ai-sherpa-$name installed to $target_dir/SKILL.md"
    installed=$((installed + 1))
  done
  log_info "AI Sherpa domain skills installed ($installed total) under $skills_dir"
}
```

- [ ] **Step 3: Wire `install_ai_sherpa_skills` into `main` and update the `write_global_claude_md` call site**

Around line 1700, the install pass currently reads:

```bash
  # --- Install ---
  register_marketplaces "$domain"
  install_core_skills
  install_domain_skills "$domain"
  install_skills "$domain"
  write_settings
  write_global_claude_md "$domain"
  install_tools "$domain"
  install_mcp_servers "$domain"
  write_ai_sherpa_state "$domain"
```

Change two lines:

1. `write_global_claude_md "$domain"` → `write_global_claude_md`  (no arg)
2. Add `install_ai_sherpa_skills` directly after `install_skills "$domain"`.

The block becomes:

```bash
  # --- Install ---
  register_marketplaces "$domain"
  install_core_skills
  install_domain_skills "$domain"
  install_skills "$domain"
  install_ai_sherpa_skills
  write_settings
  write_global_claude_md
  install_tools "$domain"
  install_mcp_servers "$domain"
  write_ai_sherpa_state "$domain"
```

- [ ] **Step 4: Update `run_update` to install AI Sherpa skills on update**

Around line 1411, `run_update` already calls `install_skills "$saved_domain"`. Add a line immediately after it:

```bash
  install_ai_sherpa_skills
```

And update the `write_settings` line (around 1417). The current line says `write_settings`; immediately after it, add:

```bash
  write_global_claude_md
```

This ensures `--update` also re-writes `~/.claude/CLAUDE.md` to core-only (fixing stale installs where the old merged version sits on disk). The existing comment "Project CLAUDE.md was NOT modified" (line 1419) is about project-level CLAUDE.md, not the global one — it stays accurate.

- [ ] **Step 5: Update uninstall to remove `ai-sherpa-*` skill directories**

In `run_uninstall` (around line 1499, right after the "Remove raw skills" block ending at line 1527), add this block:

```bash
  # 3b. Remove AI Sherpa domain skills
  log_info "Removing AI Sherpa domain skills from $skills_dir..."
  if [[ -d "$skills_dir" ]]; then
    for d in "$skills_dir"/ai-sherpa-*; do
      [[ -d "$d" ]] || continue
      log_info "  - $(basename "$d")"
      rm -rf "$d"
    done
  fi
```

- [ ] **Step 6: Syntax-check setup.sh**

```bash
bash -n setup.sh
```

Expected: no output, exit 0.

- [ ] **Step 7: Commit**

```bash
git add setup.sh
git commit -m "feat(setup.sh): write core-only CLAUDE.md + install ai-sherpa-<domain> skills

write_global_claude_md now takes no argument and writes only core/CLAUDE.md
to ~/.claude/CLAUDE.md (no more domain concatenation). New
install_ai_sherpa_skills copies every domains/<name>/SKILL.md (excluding
disabled_domains) into ~/.claude/skills/ai-sherpa-<name>/. Wired into
both the install pass and run_update. Uninstall removes ai-sherpa-*
skill dirs."
```

---

### Task 6: Update `setup.ps1` — mirror the setup.sh changes

**Files:**
- Modify: `setup.ps1:1153-1183` (function `Write-GlobalClaudeMd`)
- Modify: `setup.ps1:2426` (the install pass that calls `Write-GlobalClaudeMd $domain`)
- Modify: `setup.ps1` around line 2175 (uninstall: the "Remove raw skills" block) and `setup.ps1` Invoke-Update (find via grep)
- Create new function: `Install-AISherpaSkills` inside `setup.ps1`

- [ ] **Step 1: Replace `Write-GlobalClaudeMd` (lines 1153-1183)**

Replace the entire existing function with this. It now takes no parameter and writes only `core/CLAUDE.md`.

```powershell
function Write-GlobalClaudeMd {
    $core   = "$ScriptDir\core\CLAUDE.md"
    if (-not (Test-Path $core)) {
        Write-Err "core/CLAUDE.md not found at: $core"
        exit 1
    }
    $claudeDir = "$env:USERPROFILE\.claude"
    $target    = "$claudeDir\CLAUDE.md"
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    if (Test-Path $target) {
        Copy-Item $target "$target.bak" -Force
        Write-Warn "Backed up existing ~/.claude/CLAUDE.md to CLAUDE.md.bak"
    }
    # Global rules only. Domain-specific rules live in ai-sherpa-<domain> skills
    # under ~/.claude/skills/ and load progressively when their description matches.
    # -Encoding UTF8 on Get-Content avoids the Windows-1252 default codepage
    # that would mangle em-dashes at read time.
    $coreContent = (Get-Content $core -Raw -Encoding UTF8).TrimEnd()
    Set-Content -Path $target -Value $coreContent -Encoding UTF8
    Write-Info "core rules written to $target (active for all projects)"
}
```

- [ ] **Step 2: Add new `Install-AISherpaSkills` function**

Add this function immediately after `Install-Skills` (search for `function Install-Skills` in setup.ps1 to find its end — it precedes `Print-Summary`). Insert before `Print-Summary`:

```powershell
function Install-AISherpaSkills {
    $configFile = "$ScriptDir\plugins.json"
    $skillsDir  = "$env:USERPROFILE\.claude\skills"
    if (-not (Test-Path $skillsDir)) { New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null }

    $disabled = @()
    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($cfg.disabled_domains) { $disabled = @($cfg.disabled_domains) }
        } catch {}
    }

    $domainsRoot = "$ScriptDir\domains"
    if (-not (Test-Path $domainsRoot)) {
        Write-Warn "No domains/ directory at $domainsRoot - skipping AI Sherpa skill install."
        return
    }

    $installed = 0
    foreach ($d in Get-ChildItem $domainsRoot -Directory) {
        $name = $d.Name
        if ($disabled -contains $name) {
            Write-Info "  [SKIP]   ai-sherpa-$name (disabled_domains)"
            continue
        }
        $src = Join-Path $d.FullName "SKILL.md"
        if (-not (Test-Path $src)) { continue }
        $targetDir = Join-Path $skillsDir "ai-sherpa-$name"
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item $src (Join-Path $targetDir "SKILL.md") -Force
        Write-Info "  [READY]  ai-sherpa-$name installed to $targetDir\SKILL.md"
        $installed++
    }
    Write-Info "AI Sherpa domain skills installed ($installed total) under $skillsDir"
}
```

- [ ] **Step 3: Update the install pass — line ~2426**

The current line `Write-GlobalClaudeMd $domain` at ~line 2426 takes a domain argument. Two changes:

1. Add `Install-AISherpaSkills` directly before `Write-GlobalClaudeMd`.
2. Drop the `$domain` argument from `Write-GlobalClaudeMd`.

Find the block:

```powershell
# Global install: write CLAUDE.md to ~/.claude/ — active for all projects
Write-GlobalClaudeMd $domain
```

Replace with:

```powershell
# Install AI Sherpa domain skills (one ai-sherpa-<name> skill per non-disabled domain)
Install-AISherpaSkills
# Global install: write core rules to ~/.claude/CLAUDE.md — active for all projects
Write-GlobalClaudeMd
```

- [ ] **Step 4: Update `Invoke-Update` so `--update` also runs `Install-AISherpaSkills` + `Write-GlobalClaudeMd`**

Find `Invoke-Update` (likely the function that calls `claude plugin update` in a loop). It already calls `Install-Skills`. Add immediately after that call:

```powershell
Install-AISherpaSkills
Write-GlobalClaudeMd
```

This matches the setup.sh change in Task 5 Step 4.

To locate the exact insertion point:

```bash
grep -n 'function Invoke-Update\|Install-Skills' setup.ps1 | head -10
```

Insert the two lines inside `Invoke-Update`, immediately after `Install-Skills $savedDomain` (or whatever exact form it uses).

- [ ] **Step 5: Update `Invoke-Uninstall` to remove `ai-sherpa-*` skill directories**

Find the "Remove raw skills" block in `Invoke-Uninstall` (around lines 2170-2197). Immediately after that block (right before the "Remove AI Sherpa state file" comment at line 2199), add:

```powershell
    # 3b. Remove AI Sherpa domain skills (ai-sherpa-*/)
    Write-Info "Removing AI Sherpa domain skills from $skillsDir..."
    if (Test-Path $skillsDir) {
        Get-ChildItem $skillsDir -Directory -Filter "ai-sherpa-*" -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Info "  - $($_.Name)"
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
```

- [ ] **Step 6: PowerShell parse-check**

```powershell
powershell -NoProfile -Command "[System.Management.Automation.Language.Parser]::ParseFile('$PWD\setup.ps1', [ref]$null, [ref]$null) | Out-Null; if ($Error.Count -gt 0) { $Error | ForEach-Object { Write-Host $_.Exception.Message }; exit 1 } else { Write-Host 'parse OK' }"
```

Expected: `parse OK`. If errors appear, re-check braces and paren balance in the new functions.

- [ ] **Step 7: Commit**

```bash
git add setup.ps1
git commit -m "feat(setup.ps1): write core-only CLAUDE.md + install ai-sherpa-<domain> skills

Mirrors the setup.sh change. Write-GlobalClaudeMd now takes no parameter
and writes only core/CLAUDE.md to ~/.claude/CLAUDE.md. New
Install-AISherpaSkills copies every domains/<name>/SKILL.md (excluding
disabled_domains) into ~/.claude/skills/ai-sherpa-<name>/. Wired into
both the install pass and Invoke-Update. Uninstall removes ai-sherpa-*
skill dirs."
```

---

### Task 7: Update `scripts/test-setup.sh`

Two changes: (a) the existing `write_global_claude_md` test (lines 172-200) must be revised to assert core-only output, no domain content; (b) add a new test for `install_ai_sherpa_skills`.

**Files:**
- Modify: `scripts/test-setup.sh:172-200` (existing test)
- Modify: `scripts/test-setup.sh` (append new test before the final results print)

- [ ] **Step 1: Replace the existing `write_global_claude_md` test (lines 172-200)**

Find this block (line 172):

```bash
# --- Test: write_global_claude_md merges core + chosen domain ---
echo "=== Test: write_global_claude_md merges core + chosen domain ==="
```

Replace the entire block (lines 172-200) with:

```bash
# --- Test: write_global_claude_md writes core only (no domain concat) ---
echo "=== Test: write_global_claude_md writes core only ==="
TMP=$(mktemp -d)
mkdir -p "$TMP/core" "$TMP/domains/embedded"
echo "__CORE_SENTINEL__"   > "$TMP/core/CLAUDE.md"
# Old-style domain CLAUDE.md is irrelevant now; create one to prove it's NOT read.
echo "__DOMAIN_SENTINEL__" > "$TMP/domains/embedded/CLAUDE.md"
SCRIPT_DIR_BAK="$SCRIPT_DIR"
EFFECTIVE_HOME_BAK="$EFFECTIVE_HOME"
HOME_BAK="$HOME"
SCRIPT_DIR="$TMP"
HOME="$TMP/home"
EFFECTIVE_HOME="$TMP/home"
mkdir -p "$EFFECTIVE_HOME/.claude"

write_global_claude_md

merged="$EFFECTIVE_HOME/.claude/CLAUDE.md"
assert_file_exists "CLAUDE.md written" "$merged"
assert_file_contains "CLAUDE.md contains core sentinel" "$merged" "__CORE_SENTINEL__"
# Negative assertion: no domain content should appear.
if grep -q "__DOMAIN_SENTINEL__" "$merged"; then
  fail "CLAUDE.md does NOT contain domain sentinel" "no domain content" "domain sentinel present"
else
  ok "CLAUDE.md does NOT contain domain sentinel"
fi
# Negative assertion: no '---' separator (former merge marker) at start of a line.
if grep -qE '^---$' "$merged"; then
  fail "CLAUDE.md does NOT contain '---' separator" "no '---' line" "found '---' line"
else
  ok "CLAUDE.md does NOT contain '---' separator"
fi

# Re-run with a pre-existing target → backup must be created
write_global_claude_md
assert_file_exists ".bak created on re-run" "${merged}.bak"

SCRIPT_DIR="$SCRIPT_DIR_BAK"
EFFECTIVE_HOME="$EFFECTIVE_HOME_BAK"
HOME="$HOME_BAK"
rm -rf "$TMP"
```

- [ ] **Step 2: Append a new test for `install_ai_sherpa_skills`**

Insert this block immediately before the final `echo ""` + `echo "Results: $PASS passed, $FAIL failed"` lines (around line 469):

```bash
# --- Test: install_ai_sherpa_skills copies all non-disabled domain SKILL.md ---
echo "=== Test: install_ai_sherpa_skills copies all non-disabled domain SKILL.md ==="
TMP=$(mktemp -d)
mkdir -p "$TMP/domains/embedded" "$TMP/domains/web" "$TMP/domains/marketing"
cat > "$TMP/domains/embedded/SKILL.md" << 'EOF'
---
name: ai-sherpa-embedded
description: test
---
embedded body
EOF
cat > "$TMP/domains/web/SKILL.md" << 'EOF'
---
name: ai-sherpa-web
description: test
---
web body
EOF
cat > "$TMP/domains/marketing/SKILL.md" << 'EOF'
---
name: ai-sherpa-marketing
description: test (should be skipped)
---
marketing body
EOF
cat > "$TMP/plugins.json" << 'EOF'
{
  "disabled_domains": ["marketing"],
  "global": [], "domains": {}, "tools": {}, "skills": {}
}
EOF
SCRIPT_DIR_BAK="$SCRIPT_DIR"
EFFECTIVE_HOME_BAK="$EFFECTIVE_HOME"
HOME_BAK="$HOME"
SCRIPT_DIR="$TMP"
HOME="$TMP/home"
EFFECTIVE_HOME="$TMP/home"
mkdir -p "$EFFECTIVE_HOME/.claude"

install_ai_sherpa_skills

skills_dir="$EFFECTIVE_HOME/.claude/skills"
assert_file_exists "ai-sherpa-embedded SKILL.md installed" "$skills_dir/ai-sherpa-embedded/SKILL.md"
assert_file_exists "ai-sherpa-web SKILL.md installed"      "$skills_dir/ai-sherpa-web/SKILL.md"
assert_no_file    "ai-sherpa-marketing SKIPPED (disabled)" "$skills_dir/ai-sherpa-marketing/SKILL.md"
assert_file_contains "ai-sherpa-embedded preserves body" "$skills_dir/ai-sherpa-embedded/SKILL.md" "embedded body"

# Re-run is idempotent: no error, files still present.
install_ai_sherpa_skills
assert_file_exists "ai-sherpa-embedded still present after re-run" "$skills_dir/ai-sherpa-embedded/SKILL.md"

SCRIPT_DIR="$SCRIPT_DIR_BAK"
EFFECTIVE_HOME="$EFFECTIVE_HOME_BAK"
HOME="$HOME_BAK"
rm -rf "$TMP"
```

- [ ] **Step 3: Run the bash test suite**

```bash
bash scripts/test-setup.sh
```

Expected: every test passes, final line `Results: <N> passed, 0 failed`. If a test fails:
- `write_global_claude_md` test: re-check Task 5 Step 1.
- `install_ai_sherpa_skills` test: re-check Task 5 Step 2.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-setup.sh
git commit -m "test(setup): write_global_claude_md is core-only; add install_ai_sherpa_skills test

Existing merge test rewritten to assert no domain content and no
'---' separator in the global CLAUDE.md. New test covers
install_ai_sherpa_skills: non-disabled domains land at
ai-sherpa-<name>/SKILL.md, disabled domains are skipped,
re-run is idempotent."
```

---

### Task 8: Update `AGENTS.md` — repo layout + namespace reservation

**Files:**
- Modify: `AGENTS.md:45-56` (the `domains/` repo-layout block)
- Modify: `AGENTS.md:100-112` (the "Layer 2 — Domain" row + the "merge at setup time" paragraph)
- Modify: `AGENTS.md:132-135` (the "wc -l domains/<domain>/CLAUDE.md" example)

- [ ] **Step 1: Update the repo-layout block (lines 45-56)**

Replace the existing `domains/` block:

```
├── domains/
│   ├── backend/CLAUDE.md    ← Backend (Node.js / Python) rules
│   ├── data/CLAUDE.md       ← Data Science / ML rules
│   ├── devops/CLAUDE.md     ← DevOps / Platform rules
│   ├── embedded/CLAUDE.md   ← Embedded (C/C++, firmware, RTOS) rules
│   ├── finance/CLAUDE.md    ← Finance / Accounting rules
│   ├── marketing/CLAUDE.md  ← Marketing rules
│   ├── procurement/CLAUDE.md← Procurement / Supply-chain rules
│   ├── sales/CLAUDE.md      ← Sales rules
│   ├── service/CLAUDE.md    ← Customer Service / Support rules
│   ├── uiux/CLAUDE.md       ← UI/UX Design rules
│   └── web/CLAUDE.md        ← Web / Frontend rules
```

with:

```
├── domains/
│   ├── ai/SKILL.md          ← AI / LLM agent rules (loads as ai-sherpa-ai skill)
│   ├── backend/SKILL.md     ← Backend rules (loads as ai-sherpa-backend skill)
│   ├── data/SKILL.md        ← Data engineering rules (loads as ai-sherpa-data skill)
│   ├── devops/SKILL.md      ← DevOps rules (loads as ai-sherpa-devops skill)
│   ├── embedded/SKILL.md    ← Embedded rules (loads as ai-sherpa-embedded skill)
│   ├── finance/CLAUDE.md    ← Finance rules (disabled, untouched)
│   ├── frontend/SKILL.md    ← Frontend rules (loads as ai-sherpa-frontend skill)
│   ├── marketing/CLAUDE.md  ← Marketing rules (disabled, untouched)
│   ├── procurement/CLAUDE.md← Procurement rules (disabled, untouched)
│   ├── sales/CLAUDE.md      ← Sales rules (disabled, untouched)
│   ├── service/CLAUDE.md    ← Customer Service rules (disabled, untouched)
│   ├── uiux/SKILL.md        ← UI/UX rules (loads as ai-sherpa-uiux skill)
│   └── web/SKILL.md         ← Web full-stack rules (loads as ai-sherpa-web skill)
```

- [ ] **Step 2: Update Layer 2 description (line ~107)**

Find the row:

```
| 2 — Domain | `domains/<domain>/CLAUDE.md` | ~275 | Domain-specific rules ...
```

Replace with:

```
| 2 — Domain | `domains/<domain>/SKILL.md` (8 active domains) or `CLAUDE.md` (5 disabled) | ~275 | Domain-specific rules (embedded, web, backend, data, devops, ai, frontend, uiux), loaded progressively as `ai-sherpa-<domain>` skills under `~/.claude/skills/` |
```

- [ ] **Step 3: Update the merge-at-setup paragraph (line ~112)**

Find:

```
**Layer 1 + Layer 2 merge at setup time.** `setup.ps1` and `setup.sh` concatenate `core/CLAUDE.md` + `domains/<chosen>/CLAUDE.md` (with a `---` separator) and write the result to `~/.claude/CLAUDE.md`. The user's installed file is the merge, not a single layer.
```

Replace with:

```
**Layer 1 = core only at setup time.** `setup.ps1` and `setup.sh` write `core/CLAUDE.md` verbatim to `~/.claude/CLAUDE.md` (no domain concatenation). Layer 2 is delivered as one `ai-sherpa-<domain>` skill per active domain, installed under `~/.claude/skills/ai-sherpa-<name>/SKILL.md` and activated by Claude when a task matches the skill's description. Domains listed in `plugins.json.disabled_domains` keep their CLAUDE.md files in the repo but are not installed.
```

- [ ] **Step 4: Update the `wc -l` example (line ~132)**

Find:

```
4. If you add or modify a domain's `CLAUDE.md`, check the line count stays under the limit:
   ```bash
   wc -l domains/<domain>/CLAUDE.md
   ```
```

Replace with:

```
4. If you add or modify a domain's `SKILL.md` (or one of the disabled-domain `CLAUDE.md` files), check the line count stays under the limit:
   ```bash
   wc -l domains/<domain>/SKILL.md
   ```
```

- [ ] **Step 5: Update the file-changes table (line ~193)**

Find:

```
| `domains/<domain>/CLAUDE.md` | Domain-specific rules | When refining domain guidance |
```

Replace with:

```
| `domains/<domain>/SKILL.md`  | Domain-specific rules (active domains) | When refining domain guidance |
```

- [ ] **Step 6: Add namespace-reservation note**

In the "Repository Layout" section, immediately after the `└── .github/CODEOWNERS` line (line ~71), add a new paragraph:

```
**Namespace reservation:** `~/.claude/skills/ai-sherpa-*/` is reserved for AI Sherpa-authored domain skills installed by setup. Do not name third-party skills with this prefix to avoid collision on `Install-AISherpaSkills` overwrites.
```

- [ ] **Step 7: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): document SKILL.md model + ai-sherpa-* namespace reservation

Repo layout reflects the 8 active domains as SKILL.md and the 5
disabled as CLAUDE.md. Layer 2 description updated: skill bodies
load progressively, no domain concat in ~/.claude/CLAUDE.md.
Adds explicit namespace reservation for ai-sherpa-*/ skill dirs."
```

---

### Task 9: Add the one-line pointer in `core/CLAUDE.md`

**Files:**
- Modify: `core/CLAUDE.md` (Plugin & Skill Invocation Contract section)

- [ ] **Step 1: Add the pointer line under "Plugin & Skill Invocation Contract — Global"**

Open `core/CLAUDE.md`. Find the line `### Self-described — auto-fires for its listed use cases, no override needed` (around line 152). Immediately BEFORE that subsection, add a new line:

```

> **Domain-specific contracts** live in `ai-sherpa-<domain>` skills installed under `~/.claude/skills/`. Each fires when a task matches its domain (e.g. `ai-sherpa-embedded` for Zephyr/firmware tasks). Domain MANDATORY tables, Always-Do / Never-Do rules, and toolchain lookups are inside those skill bodies, not in this file.

```

- [ ] **Step 2: Commit**

```bash
git add core/CLAUDE.md
git commit -m "docs(core): point to ai-sherpa-<domain> skills for domain-specific rules

One-line informational note in the Plugin & Skill Invocation Contract
section. Domain MANDATORY tables, Always-Do / Never-Do rules, and
toolchain lookups now live in per-domain skill bodies."
```

---

### Task 10: Local smoke test (manual)

This task validates the full install pipeline end-to-end on the local machine. It is manual because it touches `~/.claude/` and requires Claude Code running.

**Files:**
- (No file edits — runtime validation only.)

- [ ] **Step 1: Back up existing `~/.claude/CLAUDE.md` and `~/.claude/skills/`**

```powershell
$ts = Get-Date -Format 'yyyyMMddHHmmss'
if (Test-Path "$env:USERPROFILE\.claude\CLAUDE.md") {
    Copy-Item "$env:USERPROFILE\.claude\CLAUDE.md" "$env:USERPROFILE\.claude\CLAUDE.md.pre-test-$ts" -Force
}
if (Test-Path "$env:USERPROFILE\.claude\skills") {
    Copy-Item "$env:USERPROFILE\.claude\skills" "$env:USERPROFILE\.claude\skills.pre-test-$ts" -Recurse -Force
}
```

- [ ] **Step 2: Run setup in update mode (fastest path that exercises the new code)**

```powershell
.\setup.ps1 -Update
```

Expected log lines (in order, among others):
- `[READY]  ai-sherpa-ai installed to <skillsDir>\ai-sherpa-ai\SKILL.md`
- `[READY]  ai-sherpa-backend installed to <skillsDir>\ai-sherpa-backend\SKILL.md`
- … one line per active domain (8 total) …
- `[SKIP]   ai-sherpa-finance (disabled_domains)` (and 4 other disabled)
- `AI Sherpa domain skills installed (8 total) under <skillsDir>`
- `core rules written to <USERPROFILE>\.claude\CLAUDE.md`

- [ ] **Step 3: Verify `~/.claude/CLAUDE.md` is core-only**

```powershell
$claudeMd = "$env:USERPROFILE\.claude\CLAUDE.md"
# Should NOT contain the embedded-specific "Toolchain & Flasher Paths" heading
if ((Get-Content $claudeMd -Raw) -match 'Toolchain & Flasher Paths') {
    Write-Host "FAIL: domain content leaked into ~/.claude/CLAUDE.md"
} else {
    Write-Host "PASS: core-only ~/.claude/CLAUDE.md"
}
# Line count check (core/CLAUDE.md is ~164 lines)
"$(Get-Content $claudeMd | Measure-Object -Line | Select-Object -ExpandProperty Lines) lines"
```

Expected: PASS line, ~160-170 lines.

- [ ] **Step 4: Verify all 8 domain skills landed**

```powershell
$skillsDir = "$env:USERPROFILE\.claude\skills"
foreach ($name in @('ai','backend','data','devops','embedded','frontend','uiux','web')) {
    $f = Join-Path $skillsDir "ai-sherpa-$name\SKILL.md"
    if (Test-Path $f) {
        Write-Host "PASS: ai-sherpa-$name installed"
    } else {
        Write-Host "FAIL: ai-sherpa-$name MISSING at $f"
    }
}
```

Expected: 8 PASS lines.

- [ ] **Step 5: Verify disabled domains are NOT installed as skills**

```powershell
foreach ($name in @('finance','marketing','procurement','sales','service')) {
    $f = Join-Path $skillsDir "ai-sherpa-$name"
    if (Test-Path $f) {
        Write-Host "FAIL: ai-sherpa-$name was installed (should be skipped)"
    } else {
        Write-Host "PASS: ai-sherpa-$name correctly skipped"
    }
}
```

Expected: 5 PASS lines.

- [ ] **Step 6: Spot-check skill firing in Claude Code (manual)**

Open Claude Code (`claude`) in any project directory. Run these three prompts in separate sessions and observe which skills auto-activate:

1. `Review this React component for accessibility issues` → expect `ai-sherpa-web` and/or `ai-sherpa-frontend` to appear in the skill list.
2. `Help me configure a Zephyr custom board` → expect `ai-sherpa-embedded` to appear.
3. `Design a Postgres schema for a multi-tenant app` → expect `ai-sherpa-data` and/or `ai-sherpa-backend` to appear.

If any expected skill does NOT fire, the corresponding description is too narrow. Fix in a follow-up commit by widening the description in `domains/<name>/SKILL.md` (Risk #1 mitigation per the spec). Mark this step as done either way — under-firing is a follow-up, not a blocker.

- [ ] **Step 7: Restore backups if anything went wrong**

If the smoke test exposed a real problem and you want to roll back the local `~/.claude/` state before debugging:

```powershell
$backup = Get-ChildItem "$env:USERPROFILE\.claude\" -Filter "CLAUDE.md.pre-test-*" | Sort-Object Name -Descending | Select-Object -First 1
if ($backup) {
    Copy-Item $backup.FullName "$env:USERPROFILE\.claude\CLAUDE.md" -Force
    Write-Host "Restored CLAUDE.md from $($backup.Name)"
}
```

(No git commit for this task; it's runtime validation only.)

---

### Task 11: Final lint + push

**Files:**
- (No file edits — verification and push only.)

- [ ] **Step 1: Run lint one final time**

```bash
node scripts/lint-invocation-tables.js
```

Expected: exit 0. If it fails, fix the offending domain SKILL.md and amend the relevant commit.

- [ ] **Step 2: Run bash tests one final time**

```bash
bash scripts/test-setup.sh
```

Expected: `Results: <N> passed, 0 failed`.

- [ ] **Step 3: Review the commit log**

```bash
git log --oneline origin/master..HEAD
```

Expected: commits from Tasks 1–9 (descriptions reference, lint update, embedded pilot, batch conversion, setup.sh, setup.ps1, test-setup.sh, AGENTS.md, core/CLAUDE.md). Approximately 9 commits.

- [ ] **Step 4: Push the branch**

```bash
git push origin feat/version-pinning
```

(Per the spec, this is one-shot rollout on the existing feature branch `feat/version-pinning`. Open a PR for review afterwards via your usual flow.)

- [ ] **Step 5: Update Notion**

Once a PR URL exists, populate the "Spec / PR" property on the `Optimize Token Utilization` Notion page (`https://app.notion.com/p/3790eb66b6548069b31ece35b01f1265`) with the PR URL.

---

## Self-Review Notes (post-write)

- **Spec coverage:** Every section of the spec is covered.
  - Architecture & Scope → Tasks 3, 4, plus the 8 active / 5 disabled scoping inside Tasks 2 (lint) and 5/6 (setup).
  - SKILL.md File Format → Tasks 1, 3, 4 (frontmatter + body + pointer line).
  - Distribution Mechanism → Tasks 5, 6.
  - Lint Script Changes → Task 2.
  - Rollout (One-Shot) → all tasks chained.
  - Risks & Mitigations → Risk #1 (under-firing) flagged in Task 10 Step 6.
  - Files Changed → Tasks 5, 6, 7, 8, 9 (modifications); Tasks 3, 4 (creates + deletes).
  - Verification → Task 10.
  - Out of Scope → not touched anywhere.
- **Placeholder scan:** No "TBD" / "implement later" / generic "add error handling" lines. The one notational placeholder in Task 3 Step 2 (`<-- ... -->`) is immediately replaced by an exact bash recipe in the same step.
- **Type/name consistency:** `install_ai_sherpa_skills` (bash) and `Install-AISherpaSkills` (PowerShell) used consistently across Tasks 5, 6, 7. `ai-sherpa-<domain>` prefix consistent. `disabled_domains` (the plugins.json field name) referenced consistently.
