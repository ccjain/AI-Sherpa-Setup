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

# Convert a POSIX path to the form Node.js (Windows binary) can open.
# On Git-for-Windows/Cygwin: cygpath -w; on Linux/macOS: identity.
node_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

# --- Test 1: clean repo state should pass ---
# In Phase 1, files without a contract section are SKIPPED (permissive),
# so lint exits 0 even before core/CLAUDE.md gets its contract in Task 4.
echo "Test 1: lint on current repo state"
if node "$LINT" >/tmp/lint-out 2>&1; then pass "exit 0 on clean repo"
else oops "exit non-zero on clean repo; output:"; cat /tmp/lint-out
fi

# --- Test 2: missing plugin entry should fail (when the contract section exists) ---
# This test gives core/CLAUDE.md a contract heading in the temp copy so
# lint actually checks it, then injects a fake plugin that isn't listed.
echo "Test 2: lint with missing plugin entry (contract section present)"
TMP_REPO=$(mktemp -d)
cp -r "$REPO_ROOT/core" "$REPO_ROOT/domains" "$REPO_ROOT/plugins.json" "$REPO_ROOT/scripts" "$TMP_REPO/"
# Inject a fake plugin into the test copy's plugins.json (routes to global -> core/CLAUDE.md).
# Pass the dir via env var so Node.js (Windows binary) receives a native path without
# quoting/escape hazards (cygpath converts POSIX->Windows on Git-for-Windows).
WIN_TMP="$(node_path "$TMP_REPO")" node -e "
const fs = require('fs');
const path = require('path');
const dir = process.env.WIN_TMP;
const cfg = JSON.parse(fs.readFileSync(path.join(dir, 'plugins.json'), 'utf8'));
cfg.global = cfg.global || [];
cfg.global.push({ name: 'definitely-not-a-real-plugin', marketplace: 'fake' });
fs.writeFileSync(path.join(dir, 'plugins.json'), JSON.stringify(cfg, null, 2));
"
# Give core/CLAUDE.md a contract heading so lint actually checks it.
# The heading mentions the real global plugins (so they pass) but NOT
# the fake one, so the fake one should be flagged.
cat >> "$TMP_REPO/core/CLAUDE.md" <<'STUB'

## Plugin & Skill Invocation Contract — Global

Stub for test purposes. Acknowledges real global plugins so they pass,
but deliberately omits 'definitely-not-a-real-plugin' so lint flags it.

- `superpowers` — workflow skills
- `fullstack-dev-skills` — framework skills
- `claude-mem` — persistent memory
- `agent-browser` — browser automation
STUB
# Run lint against the tampered repo
node "$TMP_REPO/scripts/lint-invocation-tables.js" >/tmp/lint-out 2>&1
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
# 'web' (and every other domain) has no contract section in Phase 1 — lint should skip, not flag
node "$TMP_REPO/scripts/lint-invocation-tables.js" >/tmp/lint-out 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  pass "exit 0 — domains without contract section are skipped"
else
  oops "expected exit 0 in permissive mode; got rc=$rc, output:"
  cat /tmp/lint-out
fi
rm -rf "$TMP_REPO"

exit $fail
