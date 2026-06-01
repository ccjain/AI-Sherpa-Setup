---
name: ai-sherpa-domains
description: Use this skill when the user types /ai-sherpa-domains, says "change domains", "switch domain", "switch domains", "reconfigure ai sherpa", or asks to add/remove a domain for AI Sherpa. INVOKE — do not paraphrase. Re-runs the AI Sherpa per-project domain selector, writes the project's selection file, and activates the new rules in the current conversation.
---

# AI Sherpa — Re-select per-project domain(s)

This skill changes which AI Sherpa domain rule sets are active for the current
project. It updates one file (`<cwd>/.claude/ai-sherpa-domains.json`) and loads
the new domain rules into the current conversation without requiring a restart.

## When this skill applies

- User types `/ai-sherpa-domains`.
- User says "change domains", "switch domains", "reconfigure ai sherpa",
  "set the AI Sherpa domain to X", "this project is X and Y", or any similar
  request to modify the active domain set.

If the user is just asking which domains are *currently* active (informational,
not changing them), you can read `<cwd>/.claude/ai-sherpa-domains.json` directly
without invoking this skill.

## Procedure — follow exactly

### 1. Show the user their current selection

Read `<cwd>/.claude/ai-sherpa-domains.json` if it exists. Print a short status:

```
Current AI Sherpa domains for this project: web, ai
Detected from: package.json:next, package.json:langchain
Confirmed by you: no
```

If the file doesn't exist, say: "No domain selection on file for this project
yet — let's pick now."

### 2. List the available domains

Read `~/.claude/ai-sherpa/state.json` and use its `domains_installed` array to
build the menu. If that file is unreadable, fall back to the canonical 11:

  `embedded, web, frontend, ai, data, devops, marketing, sales, finance, service, procurement`

### 3. Ask the user via AskUserQuestion (multi-select)

Use the `AskUserQuestion` tool with `multiSelect: true` and one question. Each
domain is one option. Add an extra option:

- `"none — opt out (no AI Sherpa domain rules for this project)"`

Mark the user's current picks in the option labels so they can keep them.

If `AskUserQuestion` is not available in the runtime, fall back to listing the
options numerically and asking the user to reply with a comma-separated list.

### 4. Write the selection file

If the user chose at least one real domain:

```json
{
  "version": 1,
  "domains": [<picks, sorted>],
  "detected": false,
  "user_confirmed": true,
  "updated_at": "<ISO 8601 UTC timestamp>"
}
```

If the user chose "none — opt out":

```json
{
  "version": 1,
  "domains": [],
  "detected": false,
  "user_confirmed": true,
  "updated_at": "<ISO 8601 UTC timestamp>"
}
```

Create the `.claude/` directory in the project root if it doesn't exist. Write
the file with UTF-8 encoding and a trailing newline. **Use the absolute path**
`<cwd>/.claude/ai-sherpa-domains.json` so the file lands in the conversation's
working directory, not somewhere else.

If the write fails (read-only filesystem, permission denied, no project root),
print the JSON to the user, tell them the location it should go, and add:
*"Rules below are active for this conversation only — they won't persist."*
Then continue with step 5 anyway so the user gets value from the session.

### 5. Activate the new rules in this conversation

For each chosen domain, read its runtime CLAUDE.md from
`~/.claude/ai-sherpa/domains/<domain>/CLAUDE.md` and emit the contents inline
inside a single `<system-reminder>` block so they become active immediately.
Wrap each domain with `--- BEGIN domain rules: <name> ---` / `--- END domain
rules: <name> ---` delimiters. If a domain's runtime file is missing, log a
note (`Skipping <domain> — not in runtime cache; re-run setup.bat --update`)
and continue with the others.

If the user opted out (no domains), skip this step. Tell the user: *"AI Sherpa
is now opted out for this project. No domain rules will load on session
start."*

### 6. Confirm and exit the skill

Tell the user, in one or two lines:

```
Updated AI Sherpa domains for this project to: <list>
Active in this conversation. New sessions in this project will load the same
rules automatically via the SessionStart hook.
```

Return control to the main conversation flow.

## What this skill explicitly does NOT do

- It does **not** install or uninstall plugins. All AI Sherpa plugins are
  already installed at setup time across every domain. Domain selection only
  determines which rule sets are *active*, not what's on disk.
- It does **not** shell out to `setup.ps1` or `setup.sh`.
- It does **not** modify `~/.claude/CLAUDE.md`, `~/.claude/settings.json`, or
  `~/.claude/ai-sherpa/state.json`. Only the per-project selection file.
- It does **not** modify domain rule contents themselves. The runtime cache at
  `~/.claude/ai-sherpa/domains/<X>/CLAUDE.md` is owned by setup; if a user
  wants to edit a domain's rules, they edit `domains/<X>/CLAUDE.md` in the
  AI Sherpa repo and re-run `setup.bat --update`.

## Diagnostic notes

- The `user_confirmed: true` field marks that this selection is the user's
  explicit choice rather than an auto-detection. The SessionStart hook does
  not currently gate behavior on this field (it only looks at `domains.length`)
  but the field is surfaced in the status line shown in step 1 above.
- The `updated_at` timestamp uses ISO 8601 UTC. If JS `Date.now()` is
  unavailable in the runtime, ask the user for an approximate date or skip the
  field — the schema treats it as informational only.
