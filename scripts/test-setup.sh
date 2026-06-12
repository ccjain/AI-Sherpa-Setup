#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1"; echo "        Expected: $2"; echo "        Got: $3"; ((FAIL++)) || true; }

assert_file_exists() {
  [[ -f "$2" ]] && ok "$1" || fail "$1" "file at $2" "not found"
}
assert_file_contains() {
  grep -q "$3" "$2" 2>/dev/null && ok "$1" || fail "$1" "pattern '$3' in $2" "not found"
}
assert_no_file() {
  [[ ! -f "$2" ]] && ok "$1" || fail "$1" "no file at $2" "file exists"
}
assert_true() {
  [[ "$2" == "0" ]] && ok "$1" || fail "$1" "exit 0" "exit $2"
}
assert_false() {
  [[ "$2" != "0" ]] && ok "$1" || fail "$1" "exit non-zero" "exit 0"
}

# Source helper functions from setup.sh (main() is guarded so it won't run)
source "$REPO_DIR/setup.sh"

# --- Test check_command ---
echo "=== Test: check_command ==="
check_command "bash"; assert_true "check_command true for bash" "$?"
check_command "nonexistent_cmd_xyz_999" 2>/dev/null && RC=0 || RC=$?; assert_false "check_command false for missing cmd" "$RC"

# --- Test write_settings ---
echo "=== Test: write_settings ==="
TMP=$(mktemp -d)
HOME_BAK="$HOME"; HOME="$TMP"
# write_settings writes to $EFFECTIVE_HOME/.claude, not $HOME/.claude.
# EFFECTIVE_HOME was captured at setup.sh source time (line 150) and points
# at the REAL home dir — without this override the test silently writes to
# /c/Users/Admin/.claude on every run and the TMP assertions all fail.
EFFECTIVE_HOME_BAK="$EFFECTIVE_HOME"; EFFECTIVE_HOME="$TMP"

write_settings
assert_file_exists "global settings.json created" "$TMP/.claude/settings.json"
assert_file_contains "global settings has Read .env rule" "$TMP/.claude/settings.json" '"Read'
assert_file_contains "global settings has Write .env rule" "$TMP/.claude/settings.json" '"Write'
assert_no_file "no .bak on first run" "$TMP/.claude/settings.json.bak"

# Second call creates backup
write_settings
assert_file_exists "settings.json.bak created on second run" "$TMP/.claude/settings.json.bak"

HOME="$HOME_BAK"
EFFECTIVE_HOME="$EFFECTIVE_HOME_BAK"
rm -rf "$TMP"

# --- Test: project-level helpers are gone (regression guard) ---
echo "=== Test: project-level helpers are not defined ==="
declare -F write_project_settings > /dev/null \
  && fail "write_project_settings should not be defined" "no function" "function exists" \
  || ok "write_project_settings is not defined"
declare -F copy_claude_md > /dev/null \
  && fail "copy_claude_md should not be defined" "no function" "function exists" \
  || ok "copy_claude_md is not defined"

# --- Test install_core_skills reads global plugins from plugins.json ---
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

# --- Test install_domain_skills reads domain plugins from plugins.json ---
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

# --- Test install_domain_skills handles github entries ---
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
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
(SCRIPT_DIR="$TMP"; install_core_skills 2>/dev/null) && RC=0 || RC=$?
assert_false "exits non-zero when plugins.json missing" "$RC"
SCRIPT_DIR="$SCRIPT_DIR_BAK"; rm -rf "$TMP"

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
mkdir -p "$TMP/settings"
cat > "$TMP/settings/settings-template.json" << 'EOF'
{ "permissions": {} }
EOF
# Provide a core/CLAUDE.md stub so write_global_claude_md does not exit 1
mkdir -p "$TMP/core"
echo "# stub" > "$TMP/core/CLAUDE.md"
HOME_BAK="$HOME"; HOME="$TMP"
EFFECTIVE_HOME_BAK="$EFFECTIVE_HOME"; EFFECTIVE_HOME="$TMP"
SCRIPT_DIR_BAK="$SCRIPT_DIR"; SCRIPT_DIR="$TMP"
mkdir -p "$TMP/.claude"
claude() { echo "claude $*" >> "$MOCK_LOG"; }
export -f claude
run_update
assert_file_contains "run_update calls plugin update" "$MOCK_LOG" \
  "plugin update superpowers"
HOME="$HOME_BAK"; EFFECTIVE_HOME="$EFFECTIVE_HOME_BAK"; SCRIPT_DIR="$SCRIPT_DIR_BAK"; unset -f claude; rm -rf "$TMP"


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

# --- Test: platform_arch_key ---
echo "=== Test: platform_arch_key ==="
key=$(platform_arch_key)
if [[ "$key" =~ ^(windows|linux|macos)-(x64|arm64)$ ]]; then
  ok "platform_arch_key returns <os>-<arch>"
else
  fail "platform_arch_key returns <os>-<arch>" "<os>-<arch>" "$key"
fi

# --- Test: install_github_release_tool skip-if-installed ---
echo "=== Test: install_github_release_tool skip-if-installed ==="
# Override check_command so "alreadyinstalledtool" looks installed
check_command() {
  [[ "$1" == "alreadyinstalledtool" ]] && return 0 || return 1
}
# Capture log output
captured_info=()
log_info() { captured_info+=("$*"); }

# Disable set -e for the call; install_github_release_tool may have benign
# non-zero exits internally (e.g. `command -v` for a fake tool name)
set +e
fake_entry='{"name":"alreadyinstalledtool","repo":"fake/repo","asset":{"linux-x64":"fake.tar.gz"},"binary":"alreadyinstalledtool","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry" "false"
set -e

found=false
for line in "${captured_info[@]}"; do
  if [[ "$line" == *"[SKIP]"*"alreadyinstalledtool already installed"* ]]; then
    found=true
    break
  fi
done
if $found; then ok "install_github_release_tool logs SKIP when already installed"
else fail "install_github_release_tool logs SKIP" "[SKIP] line in output" "no SKIP line"
fi

# Restore originals
unset -f check_command log_info

# --- Test: install_github_release_tool surfaces API failure as ACTION REQUIRED ---
echo "=== Test: install_github_release_tool API failure (CASE C) ==="
check_command() { return 1; }
curl() { return 22; }
captured_action=()
captured_user_actions=()
log_info() { :; }  # silence the "Installing..." line; we only check log_action here
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

set +e
fake_entry='{"name":"rtk","repo":"rtk-ai/rtk","asset":{"linux-x64":"rtk-x86_64-unknown-linux-musl.tar.gz"},"binary":"rtk","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry" "false"
set -e

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE C: API failure emits log_action"
else fail "CASE C: API failure emits log_action" "non-empty captured_action" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then
  ok "CASE C: API failure adds a user_action"
  if [[ "${captured_user_actions[0]}" == *"releases"* ]]; then
    ok "CASE C: user_action command mentions releases page"
  else
    fail "CASE C: user_action command mentions releases page" "releases in command" "${captured_user_actions[0]}"
  fi
else
  fail "CASE C: API failure adds a user_action" "non-empty captured_user_actions" "empty"
fi

unset -f check_command curl log_action add_user_action log_info

# --- Test: install_github_release_tool platform missing (CASE B) ---
echo "=== Test: install_github_release_tool platform missing (CASE B) ==="
check_command() { return 1; }
# curl returns a manifest with an asset that doesn't match our platform
curl() {
  cat <<'JSON'
{"assets":[{"name":"something-else.tar.gz","browser_download_url":"https://example.invalid/x"}]}
JSON
  return 0
}
captured_action=()
captured_user_actions=()
log_info() { :; }
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

set +e
fake_entry_b='{"name":"rtk","repo":"rtk-ai/rtk","asset":{"freebsd-x64":"fake.zip"},"binary":"rtk","destination":"/tmp/test-dest"}'
install_github_release_tool "$fake_entry_b" "false"
set -e

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE B emits log_action"
else fail "CASE B emits log_action" "non-empty" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then ok "CASE B adds user_action"
else fail "CASE B adds user_action" "non-empty" "empty"
fi

# --- Test: install_github_release_tool asset rename (CASE D) ---
echo "=== Test: install_github_release_tool asset rename (CASE D) ==="
captured_action=()
captured_user_actions=()

current_key=$(platform_arch_key)
fake_entry_d="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"expected-name-not-in-manifest.zip\"},\"binary\":\"rtk\",\"destination\":\"/tmp/test-dest\"}"
set +e
install_github_release_tool "$fake_entry_d" "false"
set -e

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE D emits log_action"
else fail "CASE D emits log_action" "non-empty" "empty"
fi
if [[ ${#captured_user_actions[@]} -gt 0 ]]; then
  ok "CASE D adds user_action"
  if [[ "${captured_user_actions[0]}" == *"something-else.tar.gz"* ]]; then
    ok "CASE D user_action lists actual asset names"
  else
    fail "CASE D user_action lists actual asset names" "something-else.tar.gz in why" "${captured_user_actions[0]}"
  fi
else
  fail "CASE D adds user_action" "non-empty" "empty"
fi

unset -f check_command curl log_action add_user_action log_info

# --- Test: install_github_release_tool download failure (CASE E) ---
echo "=== Test: install_github_release_tool CASE E ==="
check_command() { return 1; }
current_key=$(platform_arch_key)
_curl_count=0
curl() {
  _curl_count=$((_curl_count + 1))
  if [[ $_curl_count -eq 1 ]]; then
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  return 22
}
captured_action=()
captured_user_actions=()
log_info() { :; }
log_action() { captured_action+=("$*"); }
add_user_action() { captured_user_actions+=("title=$1; why=$2; cmd=$3"); }

set +e
fake_entry_e="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk\",\"destination\":\"/tmp/test-dest\"}"
install_github_release_tool "$fake_entry_e" "false"
set -e

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE E emits log_action"
else fail "CASE E emits log_action" "non-empty" "empty"
fi

# --- Test: install_github_release_tool binary missing in archive (CASE G) ---
echo "=== Test: install_github_release_tool CASE G ==="
captured_action=()
captured_user_actions=()
_curl_count=0
curl() {
  _curl_count=$((_curl_count + 1))
  if [[ $_curl_count -eq 1 ]]; then
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  local out_path=""
  local prev=""
  for a in "$@"; do
    if [[ "$prev" == "--output" || "$prev" == "-o" ]]; then out_path="$a"; break; fi
    prev="$a"
  done
  [[ -z "$out_path" ]] && return 22
  local empty_dir
  empty_dir=$(mktemp -d)
  echo placeholder > "$empty_dir/something-else.txt"
  (cd "$empty_dir" && zip -q -r "$out_path" .)
  rm -rf "$empty_dir"
  return 0
}

set +e
fake_entry_g="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk-not-in-archive\",\"destination\":\"/tmp/test-dest\"}"
install_github_release_tool "$fake_entry_g" "false"
set -e

if [[ ${#captured_action[@]} -gt 0 ]]; then ok "CASE G emits log_action"
else fail "CASE G emits log_action" "non-empty" "empty"
fi

unset -f check_command curl log_action add_user_action log_info

# --- Test: install_github_release_tool happy path (CASE H) ---
echo "=== Test: install_github_release_tool CASE H ==="
check_command() { return 1; }
current_key=$(platform_arch_key)
# Use --output flag presence to distinguish download from manifest call,
# instead of a counter (subshell-affected and unreliable across $() boundaries).
curl() {
  local out_path=""
  local prev=""
  for a in "$@"; do
    if [[ "$prev" == "--output" || "$prev" == "-o" ]]; then out_path="$a"; break; fi
    prev="$a"
  done
  if [[ -z "$out_path" ]]; then
    # Manifest fetch (no --output)
    echo "{\"assets\":[{\"name\":\"rtk-test.zip\",\"browser_download_url\":\"https://example.invalid/rtk.zip\"}]}"
    return 0
  fi
  # Download: create a real zip at out_path
  local staging; staging=$(mktemp -d)
  local bin_name="rtk"
  [[ "$current_key" == windows-* ]] && bin_name="rtk.exe"
  echo fake-binary-contents > "$staging/$bin_name"
  # Use Python's zipfile (cross-platform; `zip` isn't in Git Bash on Windows).
  # `py` is the Windows launcher; on Linux/macOS `python3` ships pre-installed.
  local pybin=""
  if command -v py >/dev/null 2>&1; then pybin="py"
  elif command -v python3 >/dev/null 2>&1 && python3 -c "" 2>/dev/null; then pybin="python3"
  elif command -v python >/dev/null 2>&1 && python -c "" 2>/dev/null; then pybin="python"
  fi
  if [[ -z "$pybin" ]]; then
    echo "[CASE H TEST SKIP] no working python found to create test zip" >&2
    rm -rf "$staging"
    return 1
  fi
  $pybin -c "
import zipfile, os, sys
src, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dest, 'w') as z:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, src))
" "$staging" "$out_path" 2>/dev/null || return 1
  rm -rf "$staging"
  return 0
}
captured_info=()
log_info() { captured_info+=("$*"); }
log_action() { :; }
add_user_action() { :; }

dest_dir=$(mktemp -d -t ghrt-test-dest-XXXXXXXX)
fake_entry_h="{\"name\":\"rtk\",\"repo\":\"rtk-ai/rtk\",\"asset\":{\"${current_key}\":\"rtk-test.zip\"},\"binary\":\"rtk\",\"destination\":\"$dest_dir\"}"
set +e
install_github_release_tool "$fake_entry_h" "false"
set -e

expected_bin="$dest_dir/rtk"
[[ "$current_key" == windows-* ]] && expected_bin="$dest_dir/rtk.exe"

if [[ -f "$expected_bin" ]]; then ok "CASE H: binary moved to destination"
else fail "CASE H: binary moved to destination" "file at $expected_bin" "not found"
fi

got_ready=false
for line in "${captured_info[@]}"; do
  if [[ "$line" == *"[READY]"*"rtk"* ]]; then got_ready=true; break; fi
done
if $got_ready; then ok "CASE H: [READY] log line emitted"
else fail "CASE H: [READY] log line emitted" "[READY] rtk in log" "not found"
fi

rm -rf "$dest_dir"
unset -f check_command curl log_action add_user_action
# Restore log_info to its original definition (was overridden for capture above)
log_info() { echo -e "${GREEN}[AI Sherpa]${NC} $1"; }

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
