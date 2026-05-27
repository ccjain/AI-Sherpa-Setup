# Plugin Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded plugin lists in setup scripts with a `plugins.json` config file that both `setup.sh` and `setup.ps1` read at install time — admin adds or removes plugins by editing the file, no script changes needed.

**Architecture:** Single `plugins.json` at the repo root declares `global` plugins (all domains) and per-domain arrays. Both scripts parse the file using native JSON tools (PowerShell's `ConvertFrom-Json`; Node.js `JSON.parse` in bash) and loop over entries to call `claude plugin install` or `claude plugin marketplace add` + install.

**Tech Stack:** Bash, PowerShell 5.1, Node.js (already a prerequisite), Claude Code CLI (`claude plugin` subcommand).

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `plugins.json` | Create | Declares global and per-domain plugin lists |
| `setup.sh` | Modify lines 51–72, 93–99 | Replace hardcoded installs with config-driven loop |
| `setup.ps1` | Modify lines 55–87, 140–143 | Replace hardcoded installs with config-driven loop |
| `scripts/test-setup.sh` | Modify (add tests at end) | Tests for new config-driven install functions |

---

## Task 1: Create plugins.json

**Files:**
- Create: `plugins.json`

- [ ] **Step 1: Create `plugins.json` at the repo root**

```json
{
  "global": [
    { "name": "superpowers", "marketplace": "claude-plugins-official" }
  ],
  "domains": {
    "embedded": [],
    "web": [
      { "name": "vercel",     "marketplace": "claude-plugins-official" },
      { "name": "playwright", "marketplace": "claude-plugins-official" }
    ],
    "backend": [],
    "data":    [],
    "devops":  []
  }
}
```

- [ ] **Step 2: Verify the JSON is valid**

Run:
```bash
node -e "JSON.parse(require('fs').readFileSync('plugins.json','utf8')); console.log('OK')"
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add plugins.json
git commit -m "feat: add plugins.json config file"
```

---

## Task 2: Update setup.sh — config-driven installs (TDD)

**Files:**
- Modify: `setup.sh` lines 51–72
- Modify: `scripts/test-setup.sh` (add tests at end)

- [ ] **Step 1: Add tests to `scripts/test-setup.sh`**

Append to the end of `scripts/test-setup.sh` (before the final `echo "Results..."` block):

```bash
# --- Test _read_plugins + install_core_skills ---
echo "=== Test: install_core_skills reads global plugins from plugins.json ==="
TMP=$(mktemp -d)
MOCK_LOG="$TMP/claude_calls.log"
cat > "$TMP/plugins.json" << 'EOF'
{
  "global": [
    { "name": "superpowers", "marketplace": "claude-plugins-official" }
  ],
  "domains": { "web": [], "embedded": [], "backend": [], "data": [], "devops": [] }
}
EOF
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
install_core_skills
assert_file_contains "installs superpowers from config" "$MOCK_LOG" \
  "plugin install superpowers@claude-plugins-official --scope user"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"

# --- Test install_domain_skills with marketplace entry ---
echo "=== Test: install_domain_skills reads domain plugins from plugins.json ==="
TMP=$(mktemp -d)
MOCK_LOG="$TMP/claude_calls.log"
cat > "$TMP/plugins.json" << 'EOF'
{
  "global": [],
  "domains": {
    "web": [{ "name": "vercel", "marketplace": "claude-plugins-official" }],
    "embedded": []
  }
}
EOF
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
install_domain_skills "web"
assert_file_contains "installs vercel for web domain" "$MOCK_LOG" \
  "plugin install vercel@claude-plugins-official --scope user"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"

# --- Test install_domain_skills with empty domain ---
echo "=== Test: install_domain_skills — no plugins for embedded ==="
TMP=$(mktemp -d)
MOCK_LOG="$TMP/claude_calls.log"
cat > "$TMP/plugins.json" << 'EOF'
{ "global": [], "domains": { "embedded": [] } }
EOF
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
install_domain_skills "embedded"
assert_no_file "no claude calls for empty domain" "$MOCK_LOG"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"

# --- Test install_domain_skills with github entry ---
echo "=== Test: install_domain_skills handles github entries ==="
TMP=$(mktemp -d)
MOCK_LOG="$TMP/claude_calls.log"
cat > "$TMP/plugins.json" << 'EOF'
{
  "global": [],
  "domains": {
    "web": [{ "name": "graphify", "github": "safishamsi/graphify" }]
  }
}
EOF
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
install_domain_skills "web"
assert_file_contains "adds github marketplace" "$MOCK_LOG" \
  "plugin marketplace add https://github.com/safishamsi/graphify"
assert_file_contains "installs github plugin" "$MOCK_LOG" \
  "plugin install graphify"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"

# --- Test missing plugins.json exits non-zero ---
echo "=== Test: install_core_skills exits on missing plugins.json ==="
TMP=$(mktemp -d)
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"   # no plugins.json here
(SCRIPT_DIR="$TMP"; install_core_skills 2>/dev/null) && RC=0 || RC=$?
assert_false "exits non-zero when plugins.json missing" "$RC"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; rm -rf "$TMP"
```

- [ ] **Step 2: Run tests — verify they FAIL**

```bash
bash scripts/test-setup.sh
```

Expected: tests for `install_core_skills reads global plugins` and others **FAIL** (functions not yet updated).

- [ ] **Step 3: Replace `install_core_skills` and `install_domain_skills` in `setup.sh`**

Replace lines 51–72 with:

```bash
# Parse plugins.json for a given section ("global" or domain name).
# Outputs pipe-delimited lines: type|name|source
_read_plugins() {
  local section="$1"
  local config_file="$SCRIPT_DIR/plugins.json"
  if [[ ! -f "$config_file" ]]; then
    log_error "plugins.json not found at $config_file"
    exit 1
  fi
  node -e "
const fs = require('fs');
let config;
try { config = JSON.parse(fs.readFileSync('$config_file', 'utf8')); }
catch (e) { process.stderr.write('Failed to parse plugins.json: ' + e.message + '\n'); process.exit(1); }
const section = '$section';
const plugins = section === 'global'
  ? (config.global || [])
  : ((config.domains && config.domains[section]) || []);
plugins.forEach(p => {
  if (p.marketplace) process.stdout.write('marketplace|' + p.name + '|' + p.marketplace + '\n');
  else if (p.github)  process.stdout.write('github|'      + p.name + '|' + p.github      + '\n');
});
" || { log_error "Failed to parse plugins.json"; exit 1; }
}

# Install one plugin entry (args: type name source)
_install_plugin() {
  local type="$1" name="$2" source="$3"
  if [[ "$type" == "marketplace" ]]; then
    claude plugin install "$name@$source" --scope user \
      || log_warn "$name install may have failed — re-run setup to retry."
  elif [[ "$type" == "github" ]]; then
    claude plugin marketplace add "https://github.com/$source" --scope user 2>/dev/null || true
    claude plugin install "$name" --scope user \
      || log_warn "$name install may have failed — re-run setup to retry."
  fi
}

install_core_skills() {
  log_info "Installing core skills (this may take 1-2 minutes)..."
  local plugin_list
  plugin_list=$(_read_plugins "global")
  if [[ -z "$plugin_list" ]]; then
    log_warn "No global plugins defined in plugins.json"
    return
  fi
  while IFS='|' read -r type name source; do
    [[ -z "$type" ]] && continue
    _install_plugin "$type" "$name" "$source"
  done <<< "$plugin_list"
  log_info "Core skills installed."
}

install_domain_skills() {
  local domain="$1"
  local plugin_list
  plugin_list=$(_read_plugins "$domain")
  if [[ -z "$plugin_list" ]]; then
    log_info "No additional skills for $domain — core skills + CLAUDE.md rules apply."
    return
  fi
  log_info "Installing $domain skills..."
  while IFS='|' read -r type name source; do
    [[ -z "$type" ]] && continue
    _install_plugin "$type" "$name" "$source"
  done <<< "$plugin_list"
}
```

- [ ] **Step 4: Run tests — verify they PASS**

```bash
bash scripts/test-setup.sh
```

Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add setup.sh scripts/test-setup.sh
git commit -m "feat: setup.sh reads plugin list from plugins.json"
```

---

## Task 3: Update setup.sh — run_update reads plugins.json (TDD)

**Files:**
- Modify: `setup.sh` lines 93–99
- Modify: `scripts/test-setup.sh` (add one more test)

- [ ] **Step 1: Add test for run_update to `scripts/test-setup.sh`**

Append before the final `echo "Results..."` line:

```bash
# --- Test run_update reads global plugins from plugins.json ---
echo "=== Test: run_update updates plugins from plugins.json ==="
TMP=$(mktemp -d)
MOCK_LOG="$TMP/claude_calls.log"
cat > "$TMP/plugins.json" << 'EOF'
{
  "global": [
    { "name": "superpowers", "marketplace": "claude-plugins-official" }
  ],
  "domains": {}
}
EOF
HOME_BAK="$HOME"; HOME="$TMP"
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
run_update
assert_file_contains "run_update calls plugin update" "$MOCK_LOG" \
  "plugin update superpowers"
HOME="$HOME_BAK"; SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"
```

- [ ] **Step 2: Run tests — verify new test FAILS**

```bash
bash scripts/test-setup.sh
```

Expected: `run_update calls plugin update` **FAIL**.

- [ ] **Step 3: Replace `run_update` in `setup.sh`**

Replace lines 93–99 with:

```bash
run_update() {
  log_info "Updating AI Sherpa core skills..."
  local plugin_list
  plugin_list=$(_read_plugins "global")
  if [[ -n "$plugin_list" ]]; then
    while IFS='|' read -r type name source; do
      [[ -z "$type" ]] && continue
      claude plugin update "$name" \
        || log_warn "$name update may have failed — re-run --update to retry."
    done <<< "$plugin_list"
  fi
  write_settings
  log_info "Core skills and settings updated. Project CLAUDE.md was NOT modified."
}
```

- [ ] **Step 4: Run tests — verify all pass**

```bash
bash scripts/test-setup.sh
```

Expected: `Results: N passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add setup.sh scripts/test-setup.sh
git commit -m "feat: run_update reads global plugins from plugins.json"
```

---

## Task 4: Update setup.ps1 — config-driven installs

**Files:**
- Modify: `setup.ps1` lines 55–87, 140–143

No automated test suite for PS1 — verify manually at the end.

- [ ] **Step 1: Replace `Install-CoreSkills`, `Install-DomainSkills`, and `Invoke-Update` in `setup.ps1`**

Replace the existing three functions (lines 55–87 and 140–143) with:

```powershell
function Read-PluginConfig {
    param([string]$Section)
    $configFile = "$ScriptDir\plugins.json"
    if (-not (Test-Path $configFile)) {
        Write-Err "plugins.json not found at $configFile"
        exit 1
    }
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        Write-Err "Failed to parse plugins.json: $_"
        exit 1
    }
    if ($Section -eq "global") {
        return $config.global
    }
    if ($config.domains.PSObject.Properties[$Section]) {
        return $config.domains.$Section
    }
    return @()
}

function Install-Plugin {
    param($Entry)
    if ($Entry.marketplace) {
        claude plugin install "$($Entry.name)@$($Entry.marketplace)" --scope user
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($Entry.name) install may have failed - re-run setup to retry." }
    } elseif ($Entry.github) {
        claude plugin marketplace add "https://github.com/$($Entry.github)" --scope user 2>$null
        claude plugin install $Entry.name --scope user
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($Entry.name) install may have failed - re-run setup to retry." }
    }
}

function Install-CoreSkills {
    Write-Info "Installing core skills (this may take 1-2 minutes)..."
    $plugins = Read-PluginConfig -Section "global"
    if (-not $plugins -or @($plugins).Count -eq 0) {
        Write-Warn "No global plugins defined in plugins.json"
        return
    }
    foreach ($entry in $plugins) { Install-Plugin $entry }
    Write-Info "Core skills installed."
}

function Install-DomainSkills {
    param([string]$Domain)
    $plugins = Read-PluginConfig -Section $Domain
    if (-not $plugins -or @($plugins).Count -eq 0) {
        Write-Info "No additional skills for $Domain - core skills + CLAUDE.md rules apply."
        return
    }
    Write-Info "Installing $Domain skills..."
    foreach ($entry in $plugins) { Install-Plugin $entry }
}

function Invoke-Update {
    Write-Info "Updating AI Sherpa core skills..."
    $plugins = Read-PluginConfig -Section "global"
    foreach ($entry in $plugins) {
        claude plugin update $entry.name
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($entry.name) update may have failed - re-run --update to retry." }
    }
    Write-GlobalSettings
    Write-Info "Core skills and settings updated. Project CLAUDE.md was NOT modified."
}
```

- [ ] **Step 2: Verify JSON read works in PS1**

```powershell
Set-Location "E:\cjain\AI sherpa"
$config = Get-Content "plugins.json" -Raw | ConvertFrom-Json
$config.global
$config.domains.web
```

Expected: shows superpowers in global, vercel + playwright in web.

- [ ] **Step 3: Commit**

```bash
git add setup.ps1
git commit -m "feat: setup.ps1 reads plugin list from plugins.json"
```

---

## Task 5: Verification Pass

- [ ] **Step 1: Run the full test suite**

```bash
bash scripts/test-setup.sh
```

Expected: `Results: N passed, 0 failed` (N ≥ 20)

- [ ] **Step 2: Verify plugins.json is valid and all domains present**

```bash
node -e "
const c = JSON.parse(require('fs').readFileSync('plugins.json','utf8'));
const domains = ['embedded','web','backend','data','devops'];
domains.forEach(d => console.log(d + ': ' + (c.domains[d] !== undefined ? 'OK' : 'MISSING')));
console.log('global: ' + c.global.length + ' plugin(s)');
"
```

Expected:
```
embedded: OK
web: OK
backend: OK
data: OK
devops: OK
global: 1 plugin(s)
```

- [ ] **Step 3: Confirm setup.sh no longer has any `npx skillsadd` calls**

```bash
grep -n "npx skillsadd" setup.sh setup.ps1 && echo "FOUND — must remove" || echo "Clean"
```

Expected: `Clean`

- [ ] **Step 4: Add a test plugin to plugins.json, verify setup would pick it up**

Temporarily add to `plugins.json` global:
```json
{ "name": "test-plugin", "marketplace": "claude-plugins-official" }
```

Then simulate what setup would do:
```bash
node -e "
const c = JSON.parse(require('fs').readFileSync('plugins.json','utf8'));
c.global.forEach(p => console.log('Would install: ' + p.name + '@' + (p.marketplace || p.github)));
"
```

Expected: shows both `superpowers@claude-plugins-official` and `test-plugin@claude-plugins-official`.

Remove the test entry before committing.

- [ ] **Step 5: Final commit and tag**

```bash
git add .
git commit -m "chore: plan 4 verification pass — plugin config complete"
git tag v0.4.0
git push && git push --tags
```

---

## Self-Review: Spec Coverage Check

| Spec Requirement | Covered by Task |
|---|---|
| Single `plugins.json` at repo root | Task 1 |
| `global` array for all-domain plugins | Task 1 + Task 2 |
| Per-domain arrays | Task 1 + Task 2 |
| `"marketplace"` entry type → `claude plugin install` | Task 2 + Task 4 |
| `"github"` entry type → marketplace add + install | Task 2 + Task 4 |
| `setup.sh` reads config | Task 2 |
| `setup.sh --update` reads config | Task 3 |
| `setup.ps1` reads config | Task 4 |
| `setup.ps1 --update` reads config | Task 4 |
| Missing plugins.json exits with error | Task 2 (test) |
| Failed install is warning not fatal | Task 2 `|| log_warn` pattern |
| Admin adds plugin by editing file only | Task 5 Step 4 verifies |
