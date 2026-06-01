#!/usr/bin/env bash
# Test scripts/fixtures/detection/<scenario>/ against hooks/sessionstart.js.
#
# The hook is read-only and self-contained: given a cwd, it either reads the
# project's .claude/ai-sherpa-domains.json or runs file-fingerprint detection,
# and emits a system-reminder block to stdout. We verify each fixture produces
# the expected shape.
#
# Run: bash scripts/test-hook.sh
# Exit: 0 if all assertions pass, 1 if any fail.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_DIR/hooks/sessionstart.js"
FIXTURES="$REPO_DIR/scripts/fixtures/detection"

if [[ ! -f "$HOOK" ]]; then
  echo "FATAL: hook not found at $HOOK"
  exit 1
fi
if [[ ! -d "$FIXTURES" ]]; then
  echo "FATAL: fixtures dir not found at $FIXTURES"
  exit 1
fi

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
nope() { echo "  FAIL: $1"; echo "        $2"; FAIL=$((FAIL+1)); }

# Stub a fake home directory with empty runtime CLAUDE.md files for every
# domain the hook might list. The hook's emit-domain-rules path reads
# ~/.claude/ai-sherpa/domains/<X>/CLAUDE.md and we need them to exist so the
# hook doesn't log "domain not in runtime cache" warnings.
FAKE_HOME=$(mktemp -d)
mkdir -p "$FAKE_HOME/.claude/ai-sherpa/domains"
for d in embedded web frontend ai data devops marketing sales finance service procurement; do
  mkdir -p "$FAKE_HOME/.claude/ai-sherpa/domains/$d"
  echo "# Stub rules for $d" > "$FAKE_HOME/.claude/ai-sherpa/domains/$d/CLAUDE.md"
done

run_hook() {
  # Run hook with cwd = $1, fake home pointing at the stub. Capture stdout.
  local cwd="$1"
  (cd "$cwd" && HOME="$FAKE_HOME" USERPROFILE="$FAKE_HOME" node "$HOOK") 2>/dev/null
}

assert_contains() {
  # $1=label, $2=text, $3=needle
  if echo "$2" | grep -qF -- "$3"; then ok "$1"
  else nope "$1" "expected to find: '$3'"
  fi
}
assert_not_contains() {
  if echo "$2" | grep -qF -- "$3"; then nope "$1" "did NOT expect to find: '$3'"
  else ok "$1"
  fi
}
assert_empty() {
  if [[ -z "$2" ]]; then ok "$1"
  else nope "$1" "expected empty output, got $(echo "$2" | wc -c) bytes"
  fi
}

# ---------- Scenario: empty/ ----------
echo "=== empty directory ==="
out=$(run_hook "$FIXTURES/empty")
assert_contains "emits ask-user banner when no signals" "$out" "no domain selected"
assert_contains "lists all 11 domains in the prompt"  "$out" "embedded, web, frontend, ai, data, devops"
assert_not_contains "no rule blocks emitted"          "$out" "BEGIN domain rules"

# ---------- Scenario: nextjs/ ----------
echo "=== nextjs (web + frontend detection) ==="
out=$(run_hook "$FIXTURES/nextjs")
assert_contains "detects web"      "$out" "Detected domain(s) for this project:"
assert_contains "names 'web'"      "$out" "web"
assert_contains "names 'frontend'" "$out" "frontend"
assert_contains "cites package.json:next" "$out" "package.json:next"
assert_contains "tells Claude to write selection file" "$out" "ai-sherpa-domains.json"
assert_contains "instructs '/ai-sherpa-domains' tip"   "$out" "/ai-sherpa-domains"
assert_contains "embeds web rules block"               "$out" "BEGIN domain rules: web"
assert_contains "embeds frontend rules block"          "$out" "BEGIN domain rules: frontend"
assert_not_contains "does NOT detect ai"               "$out" "BEGIN domain rules: ai"

# ---------- Scenario: python-ai/ ----------
echo "=== python-ai (ai + data detection) ==="
out=$(run_hook "$FIXTURES/python-ai")
assert_contains "detects ai"        "$out" "BEGIN domain rules: ai"
assert_contains "detects data"      "$out" "BEGIN domain rules: data"
assert_contains "cites langchain"   "$out" "python:langchain"
assert_contains "cites pandas"      "$out" "python:pandas"
assert_not_contains "no web detection from python project" "$out" "BEGIN domain rules: web"

# ---------- Scenario: embedded-c/ ----------
echo "=== embedded-c (C source + cross-compile Makefile) ==="
out=$(run_hook "$FIXTURES/embedded-c")
assert_contains "detects embedded"           "$out" "BEGIN domain rules: embedded"
assert_contains "cites C/C++ source"         "$out" "C/C++"
assert_contains "cites cross-compile Makefile" "$out" "Makefile:cross-compile"

# ---------- Scenario: devops/ ----------
echo "=== devops (Dockerfile + .github/workflows) ==="
out=$(run_hook "$FIXTURES/devops")
assert_contains "detects devops"             "$out" "BEGIN domain rules: devops"
assert_contains "cites Dockerfile"           "$out" "Dockerfile:container"
assert_contains "cites .github/workflows"    "$out" ".github/workflows"

# ---------- Scenario: has-selection/ (Case A, silent) ----------
echo "=== has-selection (file present, web only) ==="
out=$(run_hook "$FIXTURES/has-selection")
assert_contains "emits web rules"            "$out" "BEGIN domain rules: web"
assert_not_contains "no detection banner"    "$out" "Detected domain(s) for this project:"
assert_not_contains "no ask-user banner"     "$out" "no domain selected"

# ---------- Scenario: opted-out/ (Case C, silent) ----------
echo "=== opted-out (domains: []) ==="
out=$(run_hook "$FIXTURES/opted-out")
assert_empty "emits nothing for opt-out" "$out"

# ---------- Scenario: malformed-json/ (graceful degrade) ----------
echo "=== malformed-json (graceful degrade → detection) ==="
out=$(run_hook "$FIXTURES/malformed-json")
# Falls through to detection. There's no signal in the fixture, so we expect
# the ask-user banner. (We don't assert on stderr — the hook logs the parse
# error to stderr but we discarded it in run_hook.)
assert_contains "falls through to ask-user banner on malformed JSON" "$out" "no domain selected"

# ---------- Summary ----------
rm -rf "$FAKE_HOME"

echo ""
echo "Result: ${PASS} passed, ${FAIL} failed"
if (( FAIL > 0 )); then exit 1; fi
exit 0
