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

write_settings
assert_file_exists "global settings.json created" "$TMP/.claude/settings.json"
assert_file_contains "global settings has Read .env rule" "$TMP/.claude/settings.json" '"Read'
assert_file_contains "global settings has Write .env rule" "$TMP/.claude/settings.json" '"Write'
assert_no_file "no .bak on first run" "$TMP/.claude/settings.json.bak"

# Second call creates backup
write_settings
assert_file_exists "settings.json.bak created on second run" "$TMP/.claude/settings.json.bak"

HOME="$HOME_BAK"; rm -rf "$TMP"

# --- Test write_project_settings ---
echo "=== Test: write_project_settings ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

write_project_settings
assert_file_exists "project .claude/settings.json created" "$TMP/.claude/settings.json"
assert_file_contains "project settings has Read .env rule" "$TMP/.claude/settings.json" '"Read'

popd > /dev/null; rm -rf "$TMP"

# --- Test copy_claude_md — new project ---
echo "=== Test: copy_claude_md (new project) ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

copy_claude_md "web" "new"
assert_file_exists "CLAUDE.md created" "$TMP/CLAUDE.md"
assert_file_contains "CLAUDE.md has web rules" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"

# --- Test copy_claude_md — existing project (append) ---
echo "=== Test: copy_claude_md (existing project — appends) ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

echo "# My existing project rules" > CLAUDE.md
copy_claude_md "web" "existing"
assert_file_contains "original content preserved" "$TMP/CLAUDE.md" "My existing project rules"
assert_file_contains "domain rules appended" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"

# --- Test copy_claude_md — existing project type but no pre-existing CLAUDE.md ---
echo "=== Test: copy_claude_md (existing project type, no prior CLAUDE.md) ==="
TMP=$(mktemp -d)
pushd "$TMP" > /dev/null

copy_claude_md "web" "existing"
assert_file_exists "CLAUDE.md created even with existing type" "$TMP/CLAUDE.md"
assert_file_contains "CLAUDE.md has web rules" "$TMP/CLAUDE.md" "Web / Frontend"

popd > /dev/null; rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
