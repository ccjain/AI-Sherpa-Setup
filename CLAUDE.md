\# Environment Rules



\- NEVER assume shortcuts or alternate approaches unless explicitly asked

\- ALWAYS follow the requested environment (WSL/Linux/Windows) strictly

\- DO NOT use Windows interop (powershell.exe, cmd.exe) unless explicitly requested

\- If unsure, ASK before taking action

\- Prefer native Linux tools inside WSL


<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
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
core. Domain-level rules are loaded **per-session** at conversation start by
the SessionStart hook (see "Per-session domain selection" below), not merged
into `~/.claude/CLAUDE.md` at install time anymore.

See `docs/superpowers/specs/2026-05-29-plugin-invocation-contracts-design.md`
for the invocation contracts design.

---

## Per-session domain selection — runtime layout

As of `docs/superpowers/specs/2026-06-01-per-session-domain-selection-design.md`,
the install-time domain prompt is gone. Setup installs every domain's plugins
unconditionally, and a SessionStart hook activates the relevant domain rules
for each conversation based on per-project state.

Runtime artifacts that setup writes:

- `~/.claude/ai-sherpa/state.json` — install manifest (domains installed,
  marketplaces registered, hook path, version). New schema; the old
  `~/.claude/.ai-sherpa-state.json` with a top-level `domain` field is
  deprecated and renamed to `.legacy` on first run.
- `~/.claude/ai-sherpa/domains/<X>/CLAUDE.md` — runtime cache of each
  declared domain's rules. The hook concatenates the ones the project picked.
- `~/.claude/ai-sherpa/hooks/sessionstart.js` — the Node hook script that
  reads `<cwd>/.claude/ai-sherpa-domains.json` (per-project selection),
  falls back to file-fingerprint detection, and emits the chosen domains'
  rules as a system reminder. Source of truth: `hooks/sessionstart.js` in
  this repo.
- `~/.claude/skills/ai-sherpa-domains/SKILL.md` — slash command for
  re-selecting domains mid-conversation. Source: `skills/ai-sherpa-domains/`.

The hook entry in `~/.claude/settings.json` lives alongside the existing
code-review-graph hook entry; setup's `Register-SessionStartHook-Settings` /
`register_session_start_hook_settings` merges it in idempotently.

When editing the hook or the slash-command skill, edit the repo source
(`hooks/sessionstart.js` / `skills/ai-sherpa-domains/SKILL.md`) and re-run
`setup.bat --update` (or `setup.sh --update`) — setup copies them into
`~/.claude/ai-sherpa/` and `~/.claude/skills/` on every install/update pass.
