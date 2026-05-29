# Phase 1 Feedback & Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Phase 1 of AI Sherpa's feedback & release program — the `/ai-sherpa-feedback` slash command, GitHub-based triage workflow, weekly automated release with auto-generated notes, and Google Apps Script email notification.

**Architecture:** A new on-device skill (`ai-sherpa-feedback`) collects environment context and four short answers, then files a structured GitHub Issue via `gh`. Labels + a Projects v2 board drive triage. PRs that close those Issues and carry a `release-note` label feed a weekly cron-triggered GitHub Action that tags a CalVer release, generates Markdown notes, creates a GitHub Release, and POSTs the notes to a Google Apps Script Web App which sends the announcement email to a Google Group. Pure GitHub + one external Apps Script for email — no custom servers in Phase 1.

**Tech Stack:** Bash + `jq` (release-notes generator), GitHub Actions (release workflow + label sync + auto-relabel-on-close), PowerShell 5.1+ (Windows feedback skill helper), Bash (Linux/Mac feedback helper), Google Apps Script (mailer), `gh` CLI (auth + Issue creation + Release publishing).

**Spec:** `docs/superpowers/specs/2026-05-28-feedback-release-pipeline-design.md` (commit `181da4e`).
**Program roadmap:** `docs/superpowers/specs/2026-05-28-feedback-program-roadmap.md` (commit `ae2acc5`).

---

## Phase 0 — One-time manual setup (outside the repo)

These cannot be automated; the AI Sherpa team must do them once. The per-task work below assumes Phase 0 is complete. Track as a checklist.

- [ ] **0.1 Pick the release cron time and timezone.** Default: every Monday 16:00 UTC (≈ 09:00 PT). Used in Task 8 (release workflow).
- [ ] **0.2 Pick the Workspace account that will own the Apps Script mailer.** Default: a shared `ai-sherpa@<org>` account if available; otherwise the team lead's account. Used in Task 11 (mailer deploy).
- [ ] **0.3 Create the Google Group `ai-sherpa-announce@<org>`** in announce-only mode (only the sender can post; members read-only). Capture the self-subscribe URL. Used in Task 14 (email body template).
- [ ] **0.4 Decide whether to restrict feedback Issue creation to org members.** GitHub repo → Settings → General → Features → "Issue creation: Limit to existing collaborators" if desired. Affects spam likelihood but not the plan structure.
- [ ] **0.5 Confirm the AI Sherpa GitHub repo is public** (per the decision recorded in roadmap §9). Settings → Danger Zone.
- [ ] **0.6 Create a GitHub Project (v2) for the repo** with one kanban view; manually add columns: `Inbox`, `Approved`, `In Progress`, `Released`, `Rejected`, `Duplicate`. The label-to-column auto-rules are configured **in the Project's web UI**, not in repo files. Used in Task 5 (label taxonomy).

---

## File structure (every new or modified file in this plan)

| Path | Type | Responsibility | First touched in |
|---|---|---|---|
| `VERSION` | new | Single-line CalVer tag of the current release | Task 1 |
| `.github/labels.yml` | new | Label taxonomy (status, domain, type, severity, source, confidence, release-note, feedback) | Task 4 |
| `.github/workflows/labels-sync.yml` | new | Apply `labels.yml` to the repo whenever it changes | Task 5 |
| `.github/ISSUE_TEMPLATE/feedback.yml` | new | Structured feedback Issue form | Task 6 |
| `.github/pull_request_template.md` | new | PR template enforcing the release-note convention | Task 2 |
| `CONTRIBUTING.md` | new | Short doc describing the PR convention (Closes #N, release-note label, blockquote line) | Task 3 |
| `scripts/generate-release-notes.sh` | new | Take prev tag + new tag + PR JSON, emit Markdown notes grouped by domain | Tasks 7–8 |
| `scripts/test-generate-release-notes.sh` | new | Fixture-based test for the notes generator | Task 7 |
| `scripts/fixtures/prs-sample.json` | new | Sample `gh pr list` output for the test | Task 7 |
| `scripts/fixtures/notes-expected.md` | new | Expected Markdown output for the test fixture | Task 7 |
| `.github/workflows/release.yml` | new | Weekly cron + manual dispatch; tag + release + email | Tasks 9–14 |
| `.github/workflows/auto-label-released.yml` | new | Listen for `issues.closed`, replace status/* with `status/released` | Task 10 |
| `tools/mailer/mailer.gs` | new | Checked-in copy of the Apps Script Web App source | Task 11 |
| `tools/mailer/README.md` | new | One-time deploy + secret-rotation instructions | Task 12 |
| `tools/release-dry-run.sh` | new | Run the release pipeline locally without tagging or emailing | Task 15 |
| `skills/ai-sherpa-feedback/SKILL.md` | new | The slash command + trigger metadata | Task 16 |
| `skills/ai-sherpa-feedback/lib/submit-feedback.ps1` | new | Windows helper: collect env, ask 4 questions, file via `gh` | Task 17 |
| `skills/ai-sherpa-feedback/lib/submit-feedback.sh` | new | Linux/Mac helper: same logic in bash | Task 18 |
| `setup.sh` | modify | Add Was→Now print + change-summary tail to `--update`; install feedback skill | Task 19 |
| `setup.bat` | modify | Same | Task 20 |
| `setup.ps1` | modify | Same | Task 20 |
| `docs/feedback-guide.md` | modify | Replace v1 "open a GitHub Issue manually" with the slash-command flow | Task 21 |
| `docs/user-guide.md` | modify | Mention `/ai-sherpa-feedback` and the weekly release email | Task 22 |
| `docs/phase1-fork-runbook.md` | new | Step-by-step end-to-end test runbook | Task 23 |

---

## Section 1 — Repo skeleton

### Task 1: Add the `VERSION` file

`VERSION` lives at repo root. The release workflow (Task 9) overwrites it on every successful release. Initial value is "v0.0.0" so the very first release workflow run can detect "no prior tag" cleanly via `git describe --tags --abbrev=0` (which falls back to the initial commit if no tags exist).

**Files:**
- Create: `VERSION`

- [ ] **Step 1: Create the file**

Run:
```bash
printf 'v0.0.0\n' > VERSION
```

- [ ] **Step 2: Verify content**

Run: `cat VERSION`
Expected output:
```
v0.0.0
```

- [ ] **Step 3: Commit**

```bash
git add VERSION
git commit -m "feat: add VERSION file as release-tag marker"
```

---

### Task 2: Add the PR template

The PR template enforces three things the release workflow depends on (per spec §7.1): a `Closes #N` line, a `release-note` label, and a blockquote release-note line.

**Files:**
- Create: `.github/pull_request_template.md`

- [ ] **Step 1: Verify `.github/` exists or create it**

Run: `mkdir -p .github`
Expected: no error (directory created if missing).

- [ ] **Step 2: Write the template**

Create `.github/pull_request_template.md` with this exact content:

```markdown
## What this changes
<one or two sentences>

## Source feedback
Closes #<issue-number>

## Release-note line (shown in the weekly email — keep it crisp, user-facing)
> e.g. "Embedded: warn before suggesting malloc in ISRs"

## Domain
<embedded | web | data | devops | marketing | sales | finance | service | procurement | uiux | core | tooling>

## Verification
- [ ] Manually tested the rule change with a Claude session
- [ ] Updated relevant docs (`docs/feedback-guide.md`, `docs/user-guide.md`) if process changed
- [ ] PR has the `release-note` label (applied by reviewer before merge)
```

- [ ] **Step 3: Verify it renders**

Run: `head -5 .github/pull_request_template.md`
Expected: the first five lines printed without errors.

- [ ] **Step 4: Commit**

```bash
git add .github/pull_request_template.md
git commit -m "feat(.github): add PR template enforcing release-note convention"
```

---

### Task 3: Add `CONTRIBUTING.md`

Short doc anchoring the PR convention so external readers and Claude both can find it.

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Write the file**

Create `CONTRIBUTING.md` with this content:

````markdown
# Contributing to AI Sherpa

This repo is the source of truth for the company's Claude Code configuration:
domain CLAUDE.md rules, plugins.json, setup scripts, and the
`ai-sherpa-feedback` skill.

## Reporting issues

End users (developers using AI Sherpa) should report problems via the
**`/ai-sherpa-feedback`** slash command inside Claude Code. The skill
collects environment context, asks four short questions, and files a
structured Issue with the `feedback` and `status/needs-review` labels.

If you can't use the slash command (e.g., reporting from a phone), use the
**"AI Sherpa Feedback"** template under
[New Issue](../../issues/new/choose). It collects the same fields.

## Pull requests

Every PR that changes rules, skills, plugins, or setup behavior must:

1. **Link to a feedback Issue.** Use `Closes #<N>` in the PR body so
   merging the PR auto-closes the source Issue.
2. **Carry the `release-note` label.** Added by a reviewer once the
   release-note line is acceptable.
3. **Include a `release-note` blockquote line.** The release workflow
   extracts the first `> `-prefixed line from the "Release-note line"
   section of your PR body. Example:

   ```
   ## Release-note line
   > Embedded: warn before suggesting malloc in ISRs
   ```

If any of the three are missing, the PR can still merge — it just won't
appear in the next weekly release notes or email.

## Triage labels

Reviewers apply these labels to incoming feedback Issues. See
`.github/labels.yml` for the full taxonomy and colors.

| Prefix | Examples |
|---|---|
| `status/` | `needs-review`, `approved`, `in-progress`, `released`, `rejected`, `duplicate` |
| `domain/` | `embedded`, `web`, `data`, `devops`, `marketing`, `sales`, `finance`, `service`, `procurement`, `uiux`, `core` |
| `type/` | `rule-violation`, `enhancement`, `bug`, `docs`, `add-rule`, `refine-rule`, `skill-fix`, `plugin-change`, `setup-fix` |
| `severity/` | `critical`, `high`, `normal`, `low` |
| `source/` | `manual` (the slash command), `telemetry` (Phase 2 analyzer auto-files) |

Exactly one `status/*` label is applied at any time.
````

- [ ] **Step 2: Verify file renders**

Run: `wc -l CONTRIBUTING.md`
Expected: a positive line count (file written).

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add CONTRIBUTING.md with PR + triage conventions"
```

---

### Task 4: Define the label taxonomy

YAML for [EndBug/label-sync@v2](https://github.com/EndBug/label-sync). The Task 5 workflow applies this to the repo.

**Files:**
- Create: `.github/labels.yml`

- [ ] **Step 1: Write the file**

Create `.github/labels.yml`:

```yaml
# Status — exactly one applied at any time. Drives the Project board columns.
- name: status/needs-review
  color: f9c513
  description: New feedback awaiting triage
- name: status/approved
  color: 0e8a16
  description: Triaged; ready to implement
- name: status/in-progress
  color: 1d76db
  description: Implementation in flight
- name: status/released
  color: 5319e7
  description: Shipped in a release; closed
- name: status/rejected
  color: e11d21
  description: Triaged and rejected; closed
- name: status/duplicate
  color: cfd3d7
  description: Duplicate of another Issue; closed

# Domain — matches domains/* folders in the repo, plus core/tooling.
- name: domain/embedded
  color: 0052cc
  description: Embedded software domain
- name: domain/web
  color: 0052cc
  description: Web (frontend + backend) domain
- name: domain/data
  color: 0052cc
  description: Data science / ML domain
- name: domain/devops
  color: 0052cc
  description: DevOps / platform domain
- name: domain/marketing
  color: 0052cc
  description: Marketing domain
- name: domain/sales
  color: 0052cc
  description: Sales domain
- name: domain/finance
  color: 0052cc
  description: Finance / accounting domain
- name: domain/service
  color: 0052cc
  description: Customer service / support domain
- name: domain/procurement
  color: 0052cc
  description: Procurement / operations domain
- name: domain/uiux
  color: 0052cc
  description: UI/UX domain
- name: domain/core
  color: 0052cc
  description: Core rules (apply to all domains)
- name: domain/tooling
  color: 0052cc
  description: Setup scripts, CI, plugins.json

# Type — what kind of change the Issue represents.
- name: type/rule-violation
  color: d93f0b
  description: Claude broke an existing rule
- name: type/enhancement
  color: a2eeef
  description: New rule, skill, or capability proposed
- name: type/bug
  color: d73a4a
  description: Setup / tooling bug
- name: type/docs
  color: 0075ca
  description: Documentation fix
- name: type/add-rule
  color: a2eeef
  description: Analyzer-suggested rule addition
- name: type/refine-rule
  color: a2eeef
  description: Analyzer-suggested rule refinement
- name: type/skill-fix
  color: a2eeef
  description: Skill description update
- name: type/plugin-change
  color: a2eeef
  description: Plugin add / remove / config change
- name: type/setup-fix
  color: a2eeef
  description: setup.bat / setup.sh / setup.ps1 fix

# Severity — triage priority.
- name: severity/critical
  color: b60205
  description: Hard blocker or safety-critical
- name: severity/high
  color: d93f0b
  description: Multiple devs affected; significant friction
- name: severity/normal
  color: fbca04
  description: Single dev affected; minor friction
- name: severity/low
  color: 0e8a16
  description: Nice-to-have

# Source — which channel filed the Issue.
- name: source/manual
  color: ededed
  description: Filed by /ai-sherpa-feedback or web UI by a developer
- name: source/telemetry
  color: ededed
  description: Auto-filed by the Phase 2 analyzer (future)

# Confidence — set by the Phase 2 analyzer.
- name: confidence/high
  color: ededed
  description: Strong corroborating evidence
- name: confidence/medium
  color: ededed
  description: Plausible; review before triage
- name: confidence/low
  color: ededed
  description: Speculative; human review required

# The umbrella label — every feedback Issue carries this.
- name: feedback
  color: 0e8a16
  description: A feedback Issue (from either source)

# Applied to PRs whose changes should appear in release notes.
- name: release-note
  color: 5319e7
  description: This PR's release-note line will appear in the next weekly release
```

- [ ] **Step 2: Verify YAML is syntactically valid**

Run:
```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/labels.yml'))"
```
Expected: exit 0, no output. (Any YAML error will print a traceback.)

- [ ] **Step 3: Commit**

```bash
git add .github/labels.yml
git commit -m "feat(.github): define label taxonomy (status/domain/type/severity/source/confidence)"
```

---

### Task 5: Add the label-sync workflow

Whenever `.github/labels.yml` changes, this workflow applies it to the repo. Also supports `workflow_dispatch` for one-shot initial sync.

**Files:**
- Create: `.github/workflows/labels-sync.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/labels-sync.yml`:

```yaml
name: Sync repo labels

on:
  push:
    branches: [master]
    paths:
      - '.github/labels.yml'
      - '.github/workflows/labels-sync.yml'
  workflow_dispatch: {}

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    steps:
      - uses: actions/checkout@v4

      - name: Apply labels from .github/labels.yml
        uses: EndBug/label-sync@v2
        with:
          config-file: .github/labels.yml
          delete-other-labels: false
```

`delete-other-labels: false` is deliberate: never auto-delete labels we didn't define (avoids nuking labels added by a human or a 3rd-party app).

- [ ] **Step 2: Validate YAML**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/labels-sync.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/labels-sync.yml
git commit -m "feat(.github): add labels-sync workflow (apply labels.yml on change)"
```

After merging to master, the workflow runs once automatically and creates all labels. To force-run before merge, dispatch from Actions UI.

---

### Task 6: Add the Issue template

Form-style template per spec §5.3. Auto-applies `feedback` and `status/needs-review` labels.

**Files:**
- Create: `.github/ISSUE_TEMPLATE/feedback.yml`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p .github/ISSUE_TEMPLATE`

- [ ] **Step 2: Write the template**

Create `.github/ISSUE_TEMPLATE/feedback.yml`:

```yaml
name: AI Sherpa Feedback
description: Report a case where Claude gave wrong or unsafe advice while using AI Sherpa rules.
title: "[feedback] "
labels:
  - feedback
  - status/needs-review
  - source/manual
body:
  - type: markdown
    attributes:
      value: |
        Thanks for filing feedback. Most of these fields are auto-filled
        by the `/ai-sherpa-feedback` slash command. If you're filling
        them out manually, keep each answer to one or two lines.

  - type: dropdown
    id: domain
    attributes:
      label: Domain
      options:
        - embedded
        - web
        - data
        - devops
        - marketing
        - sales
        - finance
        - service
        - procurement
        - uiux
        - core
        - tooling
    validations:
      required: true

  - type: textarea
    id: asked
    attributes:
      label: What you asked Claude to do
      placeholder: One line.
    validations:
      required: true

  - type: textarea
    id: did
    attributes:
      label: What Claude did (paste response or describe)
      placeholder: One paragraph or pasted excerpt.
    validations:
      required: true

  - type: textarea
    id: expected
    attributes:
      label: What it should have done
      placeholder: One line.
    validations:
      required: true

  - type: input
    id: rule
    attributes:
      label: Violated rule (if known)
      placeholder: e.g. domains/embedded/CLAUDE.md "Never Do" list, item 1

  - type: textarea
    id: env
    attributes:
      label: Environment (auto-filled)
      description: AI Sherpa version, Claude Code version, OS, active plugins/skills.
      placeholder: |
        ai_sherpa_version: vYYYY.MM.DD
        claude_code_version: x.y.z
        os: Windows 11 Pro 10.0.26200
        domain: embedded
        active_plugins: [...]
        active_skills: [...]

  - type: textarea
    id: context
    attributes:
      label: Transcript context (auto-filled, edit to redact)
      description: Last user prompt + last assistant response. Review before submitting.
```

- [ ] **Step 3: Validate YAML**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/ISSUE_TEMPLATE/feedback.yml'))"
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE/feedback.yml
git commit -m "feat(.github): add AI Sherpa Feedback Issue template"
```

---

## Section 2 — Release-notes generator

### Task 7: Add test fixtures for the generator

Before writing the generator, lock in inputs and expected outputs so we can TDD.

**Files:**
- Create: `scripts/fixtures/prs-sample.json`
- Create: `scripts/fixtures/notes-expected.md`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p scripts/fixtures`

- [ ] **Step 2: Write the sample PR list**

Create `scripts/fixtures/prs-sample.json`. This is the exact shape `gh pr list --json number,title,body,labels,author,url` returns:

```json
[
  {
    "number": 142,
    "title": "feat(embedded): warn about malloc in ISRs",
    "body": "## What this changes\nAdds a rule.\n\n## Source feedback\nCloses #137\n\n## Release-note line\n> Embedded: warn before suggesting malloc in ISRs\n\n## Domain\nembedded\n",
    "labels": [{"name": "release-note"}, {"name": "domain/embedded"}],
    "author": {"login": "alice"},
    "url": "https://github.com/ccjain/AI-Sherpa-Setup/pull/142"
  },
  {
    "number": 148,
    "title": "feat(web): stricter a11y checks",
    "body": "## What this changes\nTightens accessibility audit thresholds.\n\n## Source feedback\nCloses #140\n\n## Release-note line\n> Web: stricter accessibility checks\n\n## Domain\nweb\n",
    "labels": [{"name": "release-note"}, {"name": "domain/web"}],
    "author": {"login": "bob"},
    "url": "https://github.com/ccjain/AI-Sherpa-Setup/pull/148"
  },
  {
    "number": 151,
    "title": "feat(core): faster setup --update",
    "body": "## What this changes\nSpeeds up plugin refresh by skipping unchanged plugins.\n\n## Source feedback\nCloses #145\n\n## Release-note line\n> Core: faster `setup --update`\n\n## Domain\ncore\n",
    "labels": [{"name": "release-note"}, {"name": "domain/core"}],
    "author": {"login": "carol"},
    "url": "https://github.com/ccjain/AI-Sherpa-Setup/pull/151"
  }
]
```

- [ ] **Step 3: Write the expected output**

Create `scripts/fixtures/notes-expected.md`:

```markdown
# AI Sherpa v2026.06.01

_Released 2026-06-01. 3 fixes across 3 domains._

## Core
- Core: faster `setup --update` (#151, thanks @carol)

## Embedded
- Embedded: warn before suggesting malloc in ISRs (#142, thanks @alice)

## Web
- Web: stricter accessibility checks (#148, thanks @bob)

## How to update
Run `setup.bat --update` (Windows) or `bash setup.sh --update` (Linux/macOS/WSL).
Full diff: https://github.com/ccjain/AI-Sherpa-Setup/compare/v2026.05.25...v2026.06.01
```

(Domains sorted alphabetically; PRs within each domain sorted by PR number.)

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures/
git commit -m "test(scripts): add release-notes generator fixtures"
```

---

### Task 8: Write the release-notes generator and its test (TDD)

Pure function over `prs.json` + two tags. Bash + `jq`. Runs identically locally and in the GitHub Action.

**Files:**
- Create: `scripts/test-generate-release-notes.sh`
- Create: `scripts/generate-release-notes.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/test-generate-release-notes.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Test harness: runs the generator against the sample fixture,
# compares to expected output, diffs cleanly or exits non-zero.

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$THIS_DIR/.."

PREV_TAG="v2026.05.25"
NEW_TAG="v2026.06.01"
RELEASE_DATE="2026-06-01"
REPO_URL="https://github.com/ccjain/AI-Sherpa-Setup"

ACTUAL="$(bash scripts/generate-release-notes.sh \
    "$PREV_TAG" "$NEW_TAG" "$RELEASE_DATE" "$REPO_URL" \
    scripts/fixtures/prs-sample.json)"

EXPECTED="$(cat scripts/fixtures/notes-expected.md)"

if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    echo "PASS: release notes match fixture"
    exit 0
else
    echo "FAIL: release notes differ from fixture"
    diff <(echo "$EXPECTED") <(echo "$ACTUAL") || true
    exit 1
fi
```

Make it executable:
```bash
chmod +x scripts/test-generate-release-notes.sh
```

- [ ] **Step 2: Run the test (expect FAIL — script doesn't exist yet)**

Run: `bash scripts/test-generate-release-notes.sh`
Expected: error mentioning `scripts/generate-release-notes.sh: No such file or directory` (or similar), exit 1.

- [ ] **Step 3: Write the generator**

Create `scripts/generate-release-notes.sh`:

```bash
#!/usr/bin/env bash
# Usage: generate-release-notes.sh <prev_tag> <new_tag> <release_date> <repo_url> <prs_json>
#
# Reads PR objects from <prs_json> (shape: `gh pr list --json
# number,title,body,labels,author,url`), groups by `domain/*` label, extracts
# the first blockquote line after "Release-note line" from each PR body, and
# emits a Markdown release-notes document on stdout.
set -euo pipefail

PREV_TAG="${1:?prev_tag required}"
NEW_TAG="${2:?new_tag required}"
RELEASE_DATE="${3:?release_date required}"
REPO_URL="${4:?repo_url required}"
PRS_JSON="${5:?prs_json required}"

# Count PRs and unique domains for the summary line.
ITEM_COUNT="$(jq 'length' "$PRS_JSON")"

DOMAINS_PRESENT="$(jq -r '
    [.[] | .labels[].name | select(startswith("domain/")) | sub("^domain/";"")]
    | unique
    | .[]
' "$PRS_JSON")"

DOMAIN_COUNT="$(printf '%s\n' "$DOMAINS_PRESENT" | grep -c . || true)"

# Header.
printf '# AI Sherpa %s\n\n' "$NEW_TAG"
printf '_Released %s. %d fixes across %d domain%s._\n\n' \
    "$RELEASE_DATE" \
    "$ITEM_COUNT" \
    "$DOMAIN_COUNT" \
    "$([[ "$DOMAIN_COUNT" -eq 1 ]] && echo '' || echo 's')"

# One section per domain, alphabetical. Within each, PRs sorted by number.
while IFS= read -r DOMAIN; do
    [[ -z "$DOMAIN" ]] && continue
    # Capitalize first letter for the heading.
    HEADING="$(printf '%s' "$DOMAIN" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    printf '## %s\n' "$HEADING"

    # For each PR carrying domain/$DOMAIN, sorted by number, emit one bullet.
    jq -r --arg dom "domain/$DOMAIN" '
        [.[] | select(any(.labels[]; .name == $dom))]
        | sort_by(.number)
        | .[]
        | "\(.number)|\(.author.login)|\(.body)"
    ' "$PRS_JSON" | while IFS='|' read -r NUM AUTHOR BODY; do
        # Extract the first `> ` line under "Release-note line".
        # The PR body is a single line here because jq stripped newlines.
        # Restore newlines so grep works:
        NOTE_LINE="$(printf '%s\n' "$BODY" | sed 's/\\n/\n/g' \
            | awk '/^## Release-note line/{flag=1; next} flag && /^> /{sub(/^> /,""); print; exit}')"
        printf -- '- %s (#%s, thanks @%s)\n' "$NOTE_LINE" "$NUM" "$AUTHOR"
    done
    printf '\n'
done <<< "$DOMAINS_PRESENT"

# Footer.
printf '## How to update\n'
printf 'Run `setup.bat --update` (Windows) or `bash setup.sh --update` (Linux/macOS/WSL).\n'
printf 'Full diff: %s/compare/%s...%s\n' "$REPO_URL" "$PREV_TAG" "$NEW_TAG"
```

Make it executable:
```bash
chmod +x scripts/generate-release-notes.sh
```

- [ ] **Step 4: Run the test (expect PASS)**

Run: `bash scripts/test-generate-release-notes.sh`
Expected output:
```
PASS: release notes match fixture
```

If the diff shows differences, the most common causes are (a) trailing whitespace, (b) capitalisation of the domain heading, or (c) order of domains/PRs. Fix the generator until the diff is empty.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-release-notes.sh scripts/test-generate-release-notes.sh
git commit -m "feat(scripts): release-notes generator with fixture test"
```

---

## Section 3 — Auto-labeler workflow

### Task 9: Auto-apply `status/released` when an Issue is closed by a merged PR

Per spec §7.4: when a PR with `Closes #N` merges, GitHub auto-closes Issue #N. This workflow swaps that Issue's existing `status/*` label for `status/released`.

**Files:**
- Create: `.github/workflows/auto-label-released.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/auto-label-released.yml`:

```yaml
name: Auto-label released

on:
  issues:
    types: [closed]

jobs:
  relabel:
    runs-on: ubuntu-latest
    permissions:
      issues: write
    if: github.event.issue.state_reason == 'completed'
    steps:
      - name: Replace status/* with status/released
        env:
          GH_TOKEN: ${{ github.token }}
          ISSUE_NUMBER: ${{ github.event.issue.number }}
          REPO: ${{ github.repository }}
        run: |
          set -euo pipefail

          # Only act on Issues that carry the "feedback" label — skip other Issues.
          IS_FEEDBACK="$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" \
              --json labels --jq '[.labels[].name] | any(. == "feedback")')"
          if [[ "$IS_FEEDBACK" != "true" ]]; then
              echo "Issue #$ISSUE_NUMBER is not a feedback Issue; skipping."
              exit 0
          fi

          # Remove every existing status/* label.
          gh issue view "$ISSUE_NUMBER" --repo "$REPO" \
              --json labels --jq '.labels[].name' \
            | grep -E '^status/' \
            | while IFS= read -r LBL; do
                gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --remove-label "$LBL"
              done

          # Apply status/released.
          gh issue edit "$ISSUE_NUMBER" --repo "$REPO" --add-label "status/released"
          echo "Issue #$ISSUE_NUMBER relabeled to status/released."
```

- [ ] **Step 2: Validate YAML**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/auto-label-released.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/auto-label-released.yml
git commit -m "feat(.github): auto-apply status/released when feedback Issue closes"
```

---

## Section 4 — Release workflow

### Task 10: Add the release workflow scaffolding (steps 1–6 of spec §8.3)

Cron + dispatch trigger; discovery + bail-out + tag + GitHub Release. We'll add the email step in Task 11–14.

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Weekly release

on:
  schedule:
    - cron: '0 16 * * 1'   # Monday 16:00 UTC. Adjust here if Phase 0.1 picks a different time.
  workflow_dispatch: {}

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write   # needed for tag push + VERSION commit-back
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history for tag lookup

      - name: Install pandoc
        run: sudo apt-get update -qq && sudo apt-get install -y pandoc jq

      - name: Compute previous and new tag
        id: tags
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
          NEW_TAG="v$(date -u +%Y.%m.%d)"
          if [[ "$PREV_TAG" == "$NEW_TAG" ]]; then
              echo "Tag $NEW_TAG already exists (multiple release runs same day). Skipping."
              echo "skip=true" >> "$GITHUB_OUTPUT"
              exit 0
          fi
          echo "prev_tag=$PREV_TAG" >> "$GITHUB_OUTPUT"
          echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
          echo "release_date=$(date -u +%Y-%m-%d)" >> "$GITHUB_OUTPUT"

      - name: Find release-eligible merged PRs
        id: prs
        if: steps.tags.outputs.skip != 'true'
        env:
          GH_TOKEN: ${{ github.token }}
          PREV_TAG: ${{ steps.tags.outputs.prev_tag }}
        run: |
          set -euo pipefail
          # PRs merged since the previous tag, carrying the release-note label.
          PREV_DATE="$(git log -1 --format=%cI "$PREV_TAG" 2>/dev/null || echo "1970-01-01T00:00:00Z")"
          gh pr list --base master --state merged --label release-note \
              --search "merged:>$PREV_DATE" \
              --json number,title,body,labels,author,url \
              --limit 200 > prs.json
          COUNT="$(jq 'length' prs.json)"
          echo "Found $COUNT release-eligible PRs."
          echo "item_count=$COUNT" >> "$GITHUB_OUTPUT"

      - name: Bail if no PRs
        if: steps.tags.outputs.skip != 'true' && steps.prs.outputs.item_count == '0'
        run: |
          echo "::notice::No release-eligible PRs since ${{ steps.tags.outputs.prev_tag }}. No release this week."

      - name: Generate release notes
        id: notes
        if: steps.tags.outputs.skip != 'true' && steps.prs.outputs.item_count != '0'
        env:
          PREV_TAG: ${{ steps.tags.outputs.prev_tag }}
          NEW_TAG: ${{ steps.tags.outputs.new_tag }}
          RELEASE_DATE: ${{ steps.tags.outputs.release_date }}
          REPO_URL: https://github.com/${{ github.repository }}
        run: |
          set -euo pipefail
          bash scripts/generate-release-notes.sh \
              "$PREV_TAG" "$NEW_TAG" "$RELEASE_DATE" "$REPO_URL" prs.json \
              > notes.md
          pandoc notes.md -o notes.html
          echo "Notes generated ($(wc -l < notes.md) lines)."

      - name: Create GitHub Release
        id: release
        if: steps.tags.outputs.skip != 'true' && steps.prs.outputs.item_count != '0'
        env:
          GH_TOKEN: ${{ github.token }}
          NEW_TAG: ${{ steps.tags.outputs.new_tag }}
        run: |
          set -euo pipefail
          gh release create "$NEW_TAG" \
              --title "AI Sherpa $NEW_TAG" \
              --notes-file notes.md \
              --target master
          echo "tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
          echo "item_count=${{ steps.prs.outputs.item_count }}" >> "$GITHUB_OUTPUT"

      - name: Update VERSION file and push
        if: steps.tags.outputs.skip != 'true' && steps.prs.outputs.item_count != '0'
        env:
          NEW_TAG: ${{ steps.tags.outputs.new_tag }}
        run: |
          set -euo pipefail
          printf '%s\n' "$NEW_TAG" > VERSION
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add VERSION
          git commit -m "chore(release): bump VERSION to $NEW_TAG [skip ci]"
          git push origin master
```

- [ ] **Step 2: Validate YAML**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(.github): weekly release workflow (tag + notes + Release)"
```

---

## Section 5 — Email mailer

### Task 11: Add the Apps Script source to the repo

Per spec §9.3: the Apps Script Web App is the email transport. Source lives in the repo for version history.

**Files:**
- Create: `tools/mailer/mailer.gs`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p tools/mailer`

- [ ] **Step 2: Write the Apps Script source**

Create `tools/mailer/mailer.gs`:

```javascript
// AI Sherpa release-notification mailer.
//
// Deployed once at script.google.com as a Web App.
// Verifies a SHARED_SECRET property on every POST.
// Sends one email per request via MailApp.sendEmail.
//
// See tools/mailer/README.md for deployment + rotation instructions.

function doPost(e) {
  const expected = PropertiesService.getScriptProperties()
                      .getProperty('SHARED_SECRET');
  const p = JSON.parse(e.postData.contents);
  if (p.secret !== expected) {
    return ContentService.createTextOutput('forbidden')
                         .setHttpResponseCode(403);
  }
  MailApp.sendEmail({
    to: p.to,
    subject: p.subject,
    body: p.body,
    htmlBody: p.htmlBody,
    name: 'AI Sherpa',
  });
  return ContentService.createTextOutput('ok');
}
```

- [ ] **Step 3: Commit**

```bash
git add tools/mailer/mailer.gs
git commit -m "feat(tools): add Apps Script mailer source (deploy target)"
```

---

### Task 12: Add the mailer deployment README

Step-by-step deploy guide so any maintainer can re-deploy or rotate the secret.

**Files:**
- Create: `tools/mailer/README.md`

- [ ] **Step 1: Write the README**

Create `tools/mailer/README.md`:

````markdown
# AI Sherpa mailer (Google Apps Script Web App)

The release workflow (`.github/workflows/release.yml`) POSTs the rendered
release notes to a Google Apps Script Web App, which sends the
announcement email via `MailApp.sendEmail` to
`ai-sherpa-announce@<your-org>`.

The script source lives in `mailer.gs` (this folder). Apps Script itself
holds the deployed copy — keep this repo file as the source of truth for
review and rotation.

## One-time deploy

1. Open https://script.google.com signed in as the **deployer account**
   (Phase 0.2 — typically `ai-sherpa@<your-org>` or the team lead).
2. **New project** → name it "AI Sherpa Mailer".
3. Paste the entire contents of `mailer.gs` into the editor.
4. **Project Settings** (left sidebar) → **Script Properties** → **Add**:
   - Name: `SHARED_SECRET`
   - Value: a random 32-byte hex string. Generate locally:
     ```bash
     openssl rand -hex 32
     ```
5. **Deploy** → **New deployment**:
   - Type: **Web app**
   - Execute as: **Me**
   - Who has access: **Anyone**
6. Copy the deployment URL — it looks like
   `https://script.google.com/macros/s/AKfycb…/exec`.
7. In the GitHub repo: **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**, add two secrets:
   - `MAILER_URL` = the deployment URL from step 6
   - `MAILER_SECRET` = the same hex string used in step 4

## Rotating the shared secret

1. Generate a new hex string: `openssl rand -hex 32`.
2. In Apps Script: Project Settings → Script Properties → edit
   `SHARED_SECRET` to the new value.
3. In GitHub: Settings → Secrets → edit `MAILER_SECRET` to match.

If GitHub still has the old value when Apps Script has the new one,
every POST returns 403. (That's how you'd notice rotation drift.)

## Common failure modes

| Symptom (in Action logs) | Cause | Fix |
|---|---|---|
| `403 forbidden` from Apps Script | `MAILER_SECRET` in GitHub ≠ `SHARED_SECRET` in Apps Script | Re-sync the two values |
| 200 OK but no email arrives, response body is an HTML auth page | Deployment was re-saved without re-authorizing scopes | Open Apps Script, run `doPost` once manually to re-grant the `MailApp` scope |
| `Quota exceeded` | Workspace MailApp quota is 1500/day per deployer; should be ~impossible at our volume | Switch deployer account |

## Re-deploying after editing `mailer.gs`

1. Edit `mailer.gs` in this repo, commit, push.
2. Open Apps Script → paste the new contents over the old.
3. **Deploy** → **Manage deployments** → pencil-edit the existing deployment
   → **Version: New version** → **Deploy**. Keeps the same URL.
````

- [ ] **Step 2: Commit**

```bash
git add tools/mailer/README.md
git commit -m "docs(tools): mailer deploy + rotation runbook"
```

---

### Task 13: Add the email step to the release workflow

Bolt on the Apps Script POST step. Skipped automatically if no release happened.

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add the email step at the end of the `release` job**

Open `.github/workflows/release.yml` and append the following step **after** the "Update VERSION file and push" step (last in the job):

```yaml
      - name: Send release email
        if: steps.tags.outputs.skip != 'true' && steps.prs.outputs.item_count != '0'
        env:
          MAILER_URL: ${{ secrets.MAILER_URL }}
          MAILER_SECRET: ${{ secrets.MAILER_SECRET }}
          NEW_TAG: ${{ steps.tags.outputs.new_tag }}
          ITEM_COUNT: ${{ steps.prs.outputs.item_count }}
          ANNOUNCE_TO: ai-sherpa-announce@example.org   # replace with the Phase 0.3 Group address
        run: |
          set -euo pipefail
          jq -n \
              --arg secret   "$MAILER_SECRET" \
              --arg to       "$ANNOUNCE_TO" \
              --arg subject  "AI Sherpa $NEW_TAG released — $ITEM_COUNT fix(es)" \
              --rawfile body     notes.md \
              --rawfile htmlBody notes.html \
              '{secret:$secret, to:$to, subject:$subject, body:$body, htmlBody:$htmlBody}' \
            | curl -sSf -X POST -H "Content-Type: application/json" \
                --data-binary @- "$MAILER_URL"
          echo "Email POSTed to mailer."
```

Replace `ai-sherpa-announce@example.org` with the actual Group address from Phase 0.3 before merging.

- [ ] **Step 2: Validate YAML**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
```
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat(.github): release workflow sends email via Apps Script mailer"
```

---

### Task 14: Add the dry-run helper

Lets a maintainer run the same notes-generation logic locally for the last N days, without tagging or emailing. Same script the smoke test in Section 8 uses.

**Files:**
- Create: `tools/release-dry-run.sh`

- [ ] **Step 1: Write the script**

Create `tools/release-dry-run.sh`:

```bash
#!/usr/bin/env bash
# Dry-run the release pipeline locally:
#   - Find merged release-note-labeled PRs since the last tag
#   - Generate the notes Markdown + HTML
#   - Print what would be POSTed to the mailer
#
# Does NOT create a tag, GitHub Release, VERSION commit, or send an email.
#
# Requires: gh (authed), jq, pandoc.
#
# Usage:
#   bash tools/release-dry-run.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

for tool in gh jq pandoc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing required tool: $tool" >&2
        exit 1
    }
done

PREV_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
NEW_TAG="v$(date -u +%Y.%m.%d)"
RELEASE_DATE="$(date -u +%Y-%m-%d)"
REPO_URL="$(gh repo view --json url --jq .url)"

echo "Previous tag: $PREV_TAG"
echo "Would-be new tag: $NEW_TAG"

PREV_DATE="$(git log -1 --format=%cI "$PREV_TAG" 2>/dev/null || echo "1970-01-01T00:00:00Z")"
gh pr list --base master --state merged --label release-note \
    --search "merged:>$PREV_DATE" \
    --json number,title,body,labels,author,url \
    --limit 200 > /tmp/ai-sherpa-prs.json

ITEM_COUNT="$(jq 'length' /tmp/ai-sherpa-prs.json)"
echo "Release-eligible PRs found: $ITEM_COUNT"

if [[ "$ITEM_COUNT" -eq 0 ]]; then
    echo "No release would be produced this run."
    exit 0
fi

bash scripts/generate-release-notes.sh \
    "$PREV_TAG" "$NEW_TAG" "$RELEASE_DATE" "$REPO_URL" \
    /tmp/ai-sherpa-prs.json > /tmp/ai-sherpa-notes.md

pandoc /tmp/ai-sherpa-notes.md -o /tmp/ai-sherpa-notes.html

echo
echo "==================== notes.md ===================="
cat /tmp/ai-sherpa-notes.md
echo "==================== notes.html (first 20 lines) =="
head -20 /tmp/ai-sherpa-notes.html
echo "===================================================="
echo
echo "Would POST a JSON payload of ~$(wc -c < /tmp/ai-sherpa-notes.md) bytes (md) + $(wc -c < /tmp/ai-sherpa-notes.html) bytes (html) to MAILER_URL."
echo "Would tag $NEW_TAG against current master, then push."
echo "Would email: ai-sherpa-announce@<org>"
```

Make it executable:
```bash
chmod +x tools/release-dry-run.sh
```

- [ ] **Step 2: Sanity-check locally**

Run: `bash tools/release-dry-run.sh`

Expected: either prints "No release would be produced this run." (if no release-note-labeled PRs exist yet) or prints the rendered notes. Either is a pass — we're verifying the script runs without error, not the output content.

- [ ] **Step 3: Commit**

```bash
git add tools/release-dry-run.sh
git commit -m "feat(tools): release-dry-run.sh for local debugging"
```

---

## Section 6 — `/ai-sherpa-feedback` skill

### Task 15: Add the SKILL.md

The skill is what Claude Code loads when the user types `/ai-sherpa-feedback`. Per Claude Code's skill format, the frontmatter `description:` controls discovery; the body tells Claude how to invoke the helper script.

**Files:**
- Create: `skills/ai-sherpa-feedback/SKILL.md`

- [ ] **Step 1: Create the directory**

Run: `mkdir -p skills/ai-sherpa-feedback/lib`

- [ ] **Step 2: Write SKILL.md**

Create `skills/ai-sherpa-feedback/SKILL.md`:

````markdown
---
name: ai-sherpa-feedback
description: Use when the user types /ai-sherpa-feedback, or when they say things like "Claude got this wrong", "the rule didn't fire", "AI Sherpa missed", or otherwise want to report Claude giving wrong or unsafe advice. Collects environment context, asks four short questions, shows the assembled Issue body, and files a GitHub Issue in the AI Sherpa repo via the dev's own `gh` auth.
---

# AI Sherpa Feedback

This skill turns a one-off complaint into a structured GitHub Issue in
the AI Sherpa repo (`ccjain/AI-Sherpa-Setup`). The team triages weekly
and ships fixes in the next release.

## When to use

- The user explicitly types `/ai-sherpa-feedback`.
- The user complains that Claude broke an AI Sherpa rule, ignored a
  CLAUDE.md instruction, gave unsafe advice for their domain, or
  suggested code wrong for their toolchain.

Do **not** trigger on general complaints about Claude that aren't
AI Sherpa-specific.

## How to run

1. **Detect platform** and pick the correct helper:
   - Windows / PowerShell session →
     `powershell -NoProfile -ExecutionPolicy Bypass -File <skill_dir>/lib/submit-feedback.ps1`
   - Linux / macOS / WSL → `bash <skill_dir>/lib/submit-feedback.sh`

   `<skill_dir>` is the directory containing this `SKILL.md`.

2. **The helper does five things, in order:**
   - Runs `gh auth status` and aborts with install/login instructions if not authed.
   - Auto-collects environment context (AI Sherpa version, Claude Code version, OS,
     active plugins, active skills, project markers, git identity).
   - Reads the last user prompt and last assistant response from the current
     session transcript and shows them to the user for review/redaction.
   - Asks four short questions:
     1. What did you ask Claude to do?
     2. What did Claude do wrong?
     3. What should it have done?
     4. Which rule was violated (if known)?
   - Shows the assembled Issue body, asks "OK to file? [y/N]", and on yes
     runs `gh issue create --repo ccjain/AI-Sherpa-Setup --template feedback.yml`.

3. **Print the resulting Issue URL** so the user can follow up.

## Privacy

The helper always shows the captured transcript context to the user
before submission and lets them edit it. It never auto-submits. The
GitHub Issue is **public** (the AI Sherpa repo is public by design) —
the helper makes this explicit in its confirmation prompt.

## Failure modes

- `gh not installed` → print install URL for their platform, exit cleanly.
- `gh auth status` non-zero → print `gh auth login` instructions, exit cleanly.
- User answers "N" at confirmation → no Issue filed, no side effects.
- `gh issue create` fails (network, perms) → print error, do not retry,
  suggest filing manually at the printed `…/issues/new` URL.
````

- [ ] **Step 3: Commit**

```bash
git add skills/ai-sherpa-feedback/SKILL.md
git commit -m "feat(skills): add /ai-sherpa-feedback skill (Claude Code trigger metadata)"
```

---

### Task 16: Write the Windows helper

PowerShell script that runs on the dev's machine, collects env, asks questions, files the Issue.

**Files:**
- Create: `skills/ai-sherpa-feedback/lib/submit-feedback.ps1`

- [ ] **Step 1: Write the script**

Create `skills/ai-sherpa-feedback/lib/submit-feedback.ps1`:

```powershell
# /ai-sherpa-feedback helper (Windows / PowerShell 5.1+)
#
# Collects environment context, asks four questions, and files a
# structured GitHub Issue in the AI Sherpa repo via `gh`.

[CmdletBinding()]
param(
    [string]$Repo = 'ccjain/AI-Sherpa-Setup'
)

$ErrorActionPreference = 'Stop'

function Fail-Clean($msg) {
    Write-Host ""
    Write-Host "[ai-sherpa-feedback] $msg" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# 1. Verify gh is installed and authed.
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail-Clean @"
GitHub CLI (gh) is not installed.
Install via: winget install --id GitHub.cli
Then run:  gh auth login
"@
}

$ghStatus = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Fail-Clean @"
gh is installed but not authenticated.
Run:  gh auth login
Then retry /ai-sherpa-feedback.
"@
}

# 2. Auto-collect environment.
function Read-FirstLine($path) {
    if (Test-Path $path) { (Get-Content $path -TotalCount 1) } else { $null }
}

$aiSherpaVersion = Read-FirstLine "$env:USERPROFILE\.claude\CLAUDE.md"
if ($aiSherpaVersion -notmatch '^<!--\s*AI Sherpa\s+(v\S+)') {
    $aiSherpaVersion = Read-FirstLine (Join-Path (git rev-parse --show-toplevel 2>$null) 'VERSION')
}
$claudeVersion   = (& claude --version 2>$null) -join ''
$osVersion       = (Get-CimInstance Win32_OperatingSystem).Caption + ' ' + (Get-CimInstance Win32_OperatingSystem).Version
$ghUser          = (& gh api user --jq .login)
$gitEmail        = & git config user.email 2>$null

$claudeMdPath = "$env:USERPROFILE\.claude\CLAUDE.md"
$domain = if (Test-Path $claudeMdPath) {
    (Get-Content $claudeMdPath -TotalCount 1) -replace '^#\s*AI Sherpa\s*[—-]?\s*', '' -replace '\s*Rules$', '' -replace '\s*Software\s*$', ''
} else { 'unknown' }

# Plugins + skills snapshot.
$pluginsPath = "$env:USERPROFILE\.claude\plugins\installed_plugins.json"
$activePlugins = if (Test-Path $pluginsPath) {
    (Get-Content $pluginsPath -Raw | ConvertFrom-Json).PSObject.Properties.Name -join ', '
} else { '' }

$skillsDir = "$env:USERPROFILE\.claude\skills"
$activeSkills = if (Test-Path $skillsDir) {
    (Get-ChildItem $skillsDir -Directory | Select-Object -ExpandProperty Name) -join ', '
} else { '' }

# Project fingerprint (best-effort).
$projectMarkers = @()
foreach ($m in 'package.json','tsconfig.json','Cargo.toml','pyproject.toml','west.yml','prj.conf','pom.xml','build.gradle','go.mod') {
    if (Test-Path (Join-Path (Get-Location) $m)) { $projectMarkers += $m }
}

# 3. Capture last prompt + last response from session transcript (best effort).
$transcriptHint = "(auto-capture not available in this version of the helper — paste manually if needed)"

# 4. Ask four questions.
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  AI Sherpa Feedback" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Repo:   $Repo"
Write-Host "  Domain: $domain"
Write-Host "  This Issue will be PUBLIC. Review the context before submitting." -ForegroundColor Yellow
Write-Host ""

$asked    = Read-Host "1. What did you ask Claude to do? (one line)"
$did      = Read-Host "2. What did Claude do wrong? (one line)"
$expected = Read-Host "3. What should it have done? (one line)"
$rule     = Read-Host "4. Which rule was violated, if known? (free text, ENTER to skip)"

# 5. Render the Issue body.
$envBlock = @"
ai_sherpa_version: $aiSherpaVersion
claude_code_version: $claudeVersion
os: $osVersion
domain: $domain
github_login: $ghUser
git_email: $gitEmail
active_plugins: $activePlugins
active_skills: $activeSkills
project_markers: $($projectMarkers -join ', ')
"@

$body = @"
### Domain
$domain

### What you asked Claude to do
$asked

### What Claude did
$did

### What it should have done
$expected

### Violated rule (if known)
$rule

### Environment (auto-filled)
``````
$envBlock
``````

### Transcript context (auto-filled, edit to redact)
$transcriptHint
"@

$title = "[feedback] " + ($did -replace '\s+', ' ').Substring(0, [Math]::Min(72, $did.Length))

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  Issue preview" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Title: $title"
Write-Host ""
Write-Host $body
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "OK to file this PUBLIC Issue? [y/N]"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "Cancelled. No Issue filed." -ForegroundColor Yellow
    exit 0
}

# 6. File via gh.
$tmpBody = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpBody -Value $body -Encoding UTF8

$url = & gh issue create --repo $Repo --title $title --body-file $tmpBody `
    --label feedback --label status/needs-review --label source/manual `
    --label "domain/$domain"

Remove-Item $tmpBody -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Fail-Clean @"
gh issue create failed (exit $LASTEXITCODE).
File manually at: https://github.com/$Repo/issues/new/choose
"@
}

Write-Host ""
Write-Host "Filed: $url" -ForegroundColor Green
Write-Host ""
```

- [ ] **Step 2: Smoke test the prompt parsing path**

Run a parse-only check (won't file an Issue because we'll Ctrl-C at the first prompt):
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File skills/ai-sherpa-feedback/lib/submit-feedback.ps1
```
Expected: the script prints the AI Sherpa Feedback banner and the auto-detected domain, then waits at the first question. Ctrl-C to abort.

(If `gh` is not installed or authed, expect the clean failure message instead — also a pass.)

- [ ] **Step 3: Commit**

```bash
git add skills/ai-sherpa-feedback/lib/submit-feedback.ps1
git commit -m "feat(skills): Windows PowerShell helper for /ai-sherpa-feedback"
```

---

### Task 17: Write the Linux/Mac helper

Bash equivalent of the PowerShell script. Same env collection, same four questions, same submission via `gh`.

**Files:**
- Create: `skills/ai-sherpa-feedback/lib/submit-feedback.sh`

- [ ] **Step 1: Write the script**

Create `skills/ai-sherpa-feedback/lib/submit-feedback.sh`:

```bash
#!/usr/bin/env bash
# /ai-sherpa-feedback helper (Linux / macOS / WSL)
set -euo pipefail

REPO="${AI_SHERPA_REPO:-ccjain/AI-Sherpa-Setup}"

fail_clean() {
    printf '\n[ai-sherpa-feedback] %s\n\n' "$1"
    exit 1
}

# 1. Verify gh.
command -v gh >/dev/null 2>&1 || fail_clean "GitHub CLI (gh) is not installed.
Install via:  https://github.com/cli/cli#installation
Then run:     gh auth login"

if ! gh auth status >/dev/null 2>&1; then
    fail_clean "gh is installed but not authenticated.
Run:  gh auth login
Then retry /ai-sherpa-feedback."
fi

# 2. Auto-collect environment.
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
AI_SHERPA_VERSION=""
if [[ -f "$CLAUDE_MD" ]]; then
    AI_SHERPA_VERSION="$(head -1 "$CLAUDE_MD" | grep -oP 'v\d{4}\.\d{2}\.\d{2}' || true)"
fi
[[ -z "$AI_SHERPA_VERSION" ]] && AI_SHERPA_VERSION="$(cat "$(git rev-parse --show-toplevel 2>/dev/null)/VERSION" 2>/dev/null || echo 'unknown')"

CLAUDE_VERSION="$(claude --version 2>/dev/null || echo 'unknown')"
OS_VERSION="$(uname -srm)"
GH_USER="$(gh api user --jq .login 2>/dev/null || echo 'unknown')"
GIT_EMAIL="$(git config user.email 2>/dev/null || echo 'unknown')"

DOMAIN='unknown'
if [[ -f "$CLAUDE_MD" ]]; then
    DOMAIN="$(head -1 "$CLAUDE_MD" \
        | sed -E 's/^#\s*AI Sherpa\s*[—-]?\s*//;s/\s*Rules$//;s/\s*Software\s*$//' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d ' ')"
fi

PLUGINS_FILE="$HOME/.claude/plugins/installed_plugins.json"
ACTIVE_PLUGINS=""
if [[ -f "$PLUGINS_FILE" ]]; then
    ACTIVE_PLUGINS="$(jq -r 'keys | join(", ")' "$PLUGINS_FILE" 2>/dev/null || echo '')"
fi

SKILLS_DIR="$HOME/.claude/skills"
ACTIVE_SKILLS=""
if [[ -d "$SKILLS_DIR" ]]; then
    ACTIVE_SKILLS="$(ls -1 "$SKILLS_DIR" 2>/dev/null | tr '\n' ',' | sed 's/,$//;s/,/, /g')"
fi

PROJECT_MARKERS=""
for m in package.json tsconfig.json Cargo.toml pyproject.toml west.yml prj.conf pom.xml build.gradle go.mod; do
    [[ -f "$m" ]] && PROJECT_MARKERS="$PROJECT_MARKERS, $m"
done
PROJECT_MARKERS="${PROJECT_MARKERS#, }"

TRANSCRIPT_HINT="(auto-capture not available in this version of the helper — paste manually if needed)"

# 3. Banner.
printf '\n'
printf '============================================================\n'
printf '  AI Sherpa Feedback\n'
printf '============================================================\n'
printf '  Repo:   %s\n' "$REPO"
printf '  Domain: %s\n' "$DOMAIN"
printf '  This Issue will be PUBLIC. Review context before submitting.\n'
printf '\n'

# 4. Ask four questions.
read -r -p "1. What did you ask Claude to do? (one line) " ASKED
read -r -p "2. What did Claude do wrong? (one line) " DID
read -r -p "3. What should it have done? (one line) " EXPECTED
read -r -p "4. Which rule was violated, if known? (ENTER to skip) " RULE

# 5. Render body + title.
ENV_BLOCK=$(cat <<EOF
ai_sherpa_version: $AI_SHERPA_VERSION
claude_code_version: $CLAUDE_VERSION
os: $OS_VERSION
domain: $DOMAIN
github_login: $GH_USER
git_email: $GIT_EMAIL
active_plugins: $ACTIVE_PLUGINS
active_skills: $ACTIVE_SKILLS
project_markers: $PROJECT_MARKERS
EOF
)

BODY=$(cat <<EOF
### Domain
$DOMAIN

### What you asked Claude to do
$ASKED

### What Claude did
$DID

### What it should have done
$EXPECTED

### Violated rule (if known)
$RULE

### Environment (auto-filled)
\`\`\`
$ENV_BLOCK
\`\`\`

### Transcript context (auto-filled, edit to redact)
$TRANSCRIPT_HINT
EOF
)

TITLE_TRUNC="$(printf '%s' "$DID" | tr -s ' ' | cut -c1-72)"
TITLE="[feedback] $TITLE_TRUNC"

printf '\n------------------------------------------------------------\n'
printf '  Issue preview\n'
printf '------------------------------------------------------------\n'
printf 'Title: %s\n\n' "$TITLE"
printf '%s\n' "$BODY"
printf '------------------------------------------------------------\n\n'

read -r -p "OK to file this PUBLIC Issue? [y/N] " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    printf 'Cancelled. No Issue filed.\n'
    exit 0
fi

# 6. File via gh.
TMP_BODY="$(mktemp)"
printf '%s\n' "$BODY" > "$TMP_BODY"

URL="$(gh issue create --repo "$REPO" --title "$TITLE" --body-file "$TMP_BODY" \
    --label feedback --label status/needs-review --label source/manual \
    --label "domain/$DOMAIN" 2>&1 || true)"

rm -f "$TMP_BODY"

if [[ "$URL" != https://* ]]; then
    fail_clean "gh issue create failed. Output was:
$URL
File manually at: https://github.com/$REPO/issues/new/choose"
fi

printf '\nFiled: %s\n\n' "$URL"
```

Make executable:
```bash
chmod +x skills/ai-sherpa-feedback/lib/submit-feedback.sh
```

- [ ] **Step 2: Smoke test the banner**

Run (then Ctrl-C at the first prompt):
```bash
bash skills/ai-sherpa-feedback/lib/submit-feedback.sh
```
Expected: the banner prints with the auto-detected domain. (Will fail at `gh auth status` if not authed — that's the alternative pass condition.)

- [ ] **Step 3: Commit**

```bash
git add skills/ai-sherpa-feedback/lib/submit-feedback.sh
git commit -m "feat(skills): bash helper for /ai-sherpa-feedback (Linux/macOS/WSL)"
```

---

## Section 7 — Setup script changes

### Task 18: Update `setup.sh` to print Was → Now and a change-summary tail

Two additions to `--update`: stamp `<!-- AI Sherpa v… -->` into `~/.claude/CLAUDE.md`, print a "Was vX → Now vY" line, and print the cumulative release-note highlights between the two versions.

**Files:**
- Modify: `setup.sh` (the `--update` branch)

- [ ] **Step 1: Find the `--update` handler**

Run: `grep -n -E '(--update|do_update|update_mode)' setup.sh | head -20`
Expected: shows the lines where `--update` is processed. Note the function name (it may differ in your setup; treat `do_update` as a placeholder below).

- [ ] **Step 2: Add the helper functions before `do_update`**

Open `setup.sh` and add these helpers near the top (just below the other helper functions):

```bash
# --- Phase 1 release-aware update helpers ---

ai_sherpa_current_local_version() {
    # Reads the version footer from the user's installed CLAUDE.md.
    # Echoes "v0.0.0" if not found.
    local f="$HOME/.claude/CLAUDE.md"
    [[ -f "$f" ]] || { echo "v0.0.0"; return; }
    head -1 "$f" | grep -oE 'v[0-9]{4}\.[0-9]{2}\.[0-9]{2}' || echo "v0.0.0"
}

ai_sherpa_repo_version() {
    # Reads VERSION from the repo we just pulled.
    local repo_root="$1"
    [[ -f "$repo_root/VERSION" ]] || { echo "v0.0.0"; return; }
    head -1 "$repo_root/VERSION"
}

ai_sherpa_stamp_version_footer() {
    # Prepends `<!-- AI Sherpa <tag> — installed <date> via setup.sh --update -->`
    # to ~/.claude/CLAUDE.md, replacing any existing version footer comment.
    local tag="$1"
    local f="$HOME/.claude/CLAUDE.md"
    [[ -f "$f" ]] || return 0
    local today
    today="$(date -u +%Y-%m-%d)"
    local stamp="<!-- AI Sherpa $tag — installed $today via setup.sh --update -->"
    local rest
    rest="$(awk 'NR==1 && /^<!-- AI Sherpa / {next} {print}' "$f")"
    printf '%s\n%s\n' "$stamp" "$rest" > "$f"
}

ai_sherpa_print_change_summary() {
    # Lists the intermediate release tags between OLD..NEW and prints each tag's
    # release-note highlights via `gh release view`. Best-effort; silently no-ops
    # if gh isn't installed/authed.
    local old="$1" new="$2"
    command -v gh >/dev/null 2>&1 || return 0
    gh auth status >/dev/null 2>&1 || return 0
    [[ "$old" == "$new" ]] && return 0

    echo "[AI Sherpa --update] Highlights since your last update:"
    local tag
    git -C "$AI_SHERPA_REPO_ROOT" tag --sort=creatordate \
        | awk -v old="$old" -v new="$new" '
            $0 == old { flag = 1; next }
            flag { print }
            $0 == new { exit }
        ' \
        | while IFS= read -r tag; do
            gh release view "$tag" --json body --jq .body 2>/dev/null \
                | awk '/^- /{print "   " $0}'
        done
    echo
}
```

- [ ] **Step 3: Wire the helpers into `do_update`**

Inside the `--update` handler (likely a function called `do_update` or similar), find the spot **after** the `git pull` of the AI Sherpa repo and **before** the plugins update. Insert:

```bash
# --- Phase 1: capture before/after versions and stamp the footer ---
OLD_VERSION="$(ai_sherpa_current_local_version)"
NEW_VERSION="$(ai_sherpa_repo_version "$AI_SHERPA_REPO_ROOT")"
echo "[AI Sherpa --update] Was: $OLD_VERSION  →  Now: $NEW_VERSION"
ai_sherpa_stamp_version_footer "$NEW_VERSION"
```

At the **end** of `do_update` (just before the final success message), insert:

```bash
ai_sherpa_print_change_summary "$OLD_VERSION" "$NEW_VERSION"
```

Note: `AI_SHERPA_REPO_ROOT` is the variable your `setup.sh` already uses to refer to the AI Sherpa repo it's running from. If it has a different name (e.g., `SCRIPT_DIR`, `REPO_DIR`), substitute that name in the helpers above.

- [ ] **Step 4: Sanity test with bash -n**

Run: `bash -n setup.sh`
Expected: exit 0 (no syntax errors). Any error needs to be fixed before commit.

- [ ] **Step 5: Commit**

```bash
git add setup.sh
git commit -m "feat(setup.sh): --update prints Was→Now and release-notes tail"
```

---

### Task 19: Install the feedback skill during setup

The `ai-sherpa-feedback` skill needs to land at `~/.claude/skills/ai-sherpa-feedback/` on the dev's machine. Setup already installs other skills; we add this one alongside.

**Files:**
- Modify: `setup.sh` (the skills-install branch)
- Modify: `setup.bat` (same change in batch syntax)
- Modify: `setup.ps1` (same change in PowerShell syntax)

- [ ] **Step 1: Find the skills-install branch in `setup.sh`**

Run: `grep -n -E '(skills|SKILLS)' setup.sh | head -10`
Expected: shows where setup currently copies/links skills.

- [ ] **Step 2: Add the feedback skill install to `setup.sh`**

After the existing skills-install loop, append:

```bash
# Phase 1: install /ai-sherpa-feedback skill (always, regardless of domain)
if [[ -d "$AI_SHERPA_REPO_ROOT/skills/ai-sherpa-feedback" ]]; then
    mkdir -p "$HOME/.claude/skills"
    cp -r "$AI_SHERPA_REPO_ROOT/skills/ai-sherpa-feedback" "$HOME/.claude/skills/"
    chmod +x "$HOME/.claude/skills/ai-sherpa-feedback/lib/submit-feedback.sh" 2>/dev/null || true
    echo "[AI Sherpa] Installed /ai-sherpa-feedback skill."
fi
```

- [ ] **Step 3: Same change to `setup.bat`**

Open `setup.bat` and find the existing skills-install block (look for `xcopy` or `robocopy` calls referencing `skills`). After it, append:

```bat
:: Phase 1: install /ai-sherpa-feedback skill
if exist "%AI_SHERPA_REPO_ROOT%\skills\ai-sherpa-feedback" (
    if not exist "%USERPROFILE%\.claude\skills" mkdir "%USERPROFILE%\.claude\skills"
    xcopy /E /I /Y "%AI_SHERPA_REPO_ROOT%\skills\ai-sherpa-feedback" "%USERPROFILE%\.claude\skills\ai-sherpa-feedback" >nul
    echo [AI Sherpa] Installed /ai-sherpa-feedback skill.
)
```

(Substitute `%AI_SHERPA_REPO_ROOT%` with the actual variable your setup.bat uses if different — likely `%~dp0` or similar.)

- [ ] **Step 4: Same change to `setup.ps1`**

Open `setup.ps1` and append after the existing skills-install block:

```powershell
# Phase 1: install /ai-sherpa-feedback skill
$feedbackSkillSrc = Join-Path $AiSherpaRepoRoot 'skills\ai-sherpa-feedback'
if (Test-Path $feedbackSkillSrc) {
    $skillsDest = Join-Path $env:USERPROFILE '.claude\skills'
    if (-not (Test-Path $skillsDest)) { New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null }
    Copy-Item -Path $feedbackSkillSrc -Destination $skillsDest -Recurse -Force
    Write-Host "[AI Sherpa] Installed /ai-sherpa-feedback skill."
}
```

- [ ] **Step 5: Syntax-check each file**

Run:
```bash
bash -n setup.sh
```
Expected: exit 0.

For `setup.bat`, no easy syntax check; eyeball it.

For `setup.ps1`:
```bash
powershell -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw setup.ps1), [ref]\$null)"
```
Expected: no errors. (Skip if not running on a Windows host; the eyeball check is OK.)

- [ ] **Step 6: Commit**

```bash
git add setup.sh setup.bat setup.ps1
git commit -m "feat(setup): install /ai-sherpa-feedback skill alongside domain skills"
```

---

## Section 8 — Docs

### Task 20: Update `docs/feedback-guide.md` to reflect the new flow

Replace the v1 "open a GitHub Issue manually" instructions with the slash-command flow + how the team triages.

**Files:**
- Modify: `docs/feedback-guide.md`

- [ ] **Step 1: Replace the file content**

Overwrite `docs/feedback-guide.md` with:

````markdown
# AI Sherpa — How to report problems with Claude

If Claude gives wrong, unsafe, or unhelpful advice while you're using
AI Sherpa, report it so the team can fix the underlying rule, skill, or
plugin in the next weekly release.

---

## How to report

### Easy path — the slash command

Inside any Claude Code session, type:

```
/ai-sherpa-feedback
```

The skill auto-collects environment context (AI Sherpa version, OS,
active plugins, project type), asks you four short questions, shows you
the full Issue body for review (you can redact anything), and files a
structured GitHub Issue.

Total time: about 45 seconds.

### Fallback — the web form

If you can't use the slash command, open
[New Issue → AI Sherpa Feedback](../../issues/new/choose) on GitHub. The
form asks for the same fields.

> **Heads up — the AI Sherpa repo is public.** Anything you put in a
> feedback Issue is world-readable. The slash command makes this explicit
> at the confirmation step and lets you redact the auto-attached context
> before submitting. Do not paste customer names, API keys, internal
> codenames, or proprietary algorithms.

---

## What to report

Report when Claude:

- Ignored an AI Sherpa rule (e.g. skipped the pre-flight check).
- Gave unsafe advice for your domain (e.g. suggested `malloc` in an
  embedded ISR without a hardware-critical warning).
- Suggested code that's wrong for your toolchain or framework.
- Missed a security issue that AI Sherpa rules should have caught.
- Got stuck in a loop or refused a reasonable request.

Don't report general Claude limitations (it doesn't know your internal
APIs, it can't test on hardware, it makes occasional mistakes). Those
are expected and the team can't fix them by changing AI Sherpa rules.

---

## What happens next

1. **Auto-labels.** Your Issue lands with `feedback`, `status/needs-review`,
   `source/manual`, and `domain/<your domain>` labels.
2. **Weekly triage.** The AI Sherpa team reviews new feedback every Friday
   (30 min). Each Issue gets one of three outcomes:
   - **Approved** → moves to the `Approved` column. A team member opens
     a PR that closes the Issue.
   - **Rejected** → closed with a comment explaining why.
   - **Duplicate** → closed and linked to the original.
3. **Released.** When a PR closing your Issue merges and the next
   Monday's release ships, the Issue is auto-labeled `status/released`
   and you get a GitHub notification.
4. **Email.** Everyone subscribed to `ai-sherpa-announce@<your-org>`
   gets a short release email with the highlights and the update
   command.

Most feedback ships within one to two weeks.

---

## Pull-side conventions (for the AI Sherpa team)

See `CONTRIBUTING.md` for the PR template, `release-note` label
convention, and how the release notes are auto-generated.
````

- [ ] **Step 2: Commit**

```bash
git add docs/feedback-guide.md
git commit -m "docs(feedback-guide): rewrite around /ai-sherpa-feedback flow"
```

---

### Task 21: Update `docs/user-guide.md` to mention `/ai-sherpa-feedback`

Add one short section. Don't rewrite the whole guide.

**Files:**
- Modify: `docs/user-guide.md`

- [ ] **Step 1: Find the "Invoking plugins & skills" section**

Run: `grep -n '^## ' docs/user-guide.md`
Expected: a list of section headings. Find the one closest to "feedback" or "updating later" (typically section 11 or 14 in the existing guide).

- [ ] **Step 2: Insert the new section**

Add this section between "Common slash commands to test" (or wherever the document mentions slash commands) and the next major section:

```markdown
## Reporting problems with Claude

When Claude breaks an AI Sherpa rule or gives unsafe advice for your
domain, type `/ai-sherpa-feedback` inside Claude Code. The skill:

1. Auto-collects your environment (AI Sherpa version, OS, active
   plugins/skills, project markers).
2. Asks four short questions (what you asked, what Claude did, what it
   should have done, which rule was violated).
3. Shows you the full Issue body for review — you can edit or redact
   anything before submission.
4. Files the Issue in the AI Sherpa repo via your own `gh` auth.

The AI Sherpa team triages weekly and ships fixes in the next Monday
release. You'll get a GitHub notification when your Issue ships, and an
email summary of all the week's changes if you subscribe to
`ai-sherpa-announce@<your-org>`.

The AI Sherpa repo is **public** — the slash command makes that explicit
and lets you redact the auto-attached transcript context before
submitting. Don't paste secrets, customer names, or proprietary code.

Full details in [docs/feedback-guide.md](feedback-guide.md).
```

- [ ] **Step 3: Commit**

```bash
git add docs/user-guide.md
git commit -m "docs(user-guide): document /ai-sherpa-feedback and release email"
```

---

## Section 9 — End-to-end verification

### Task 22: Add the fork-test runbook

Step-by-step instructions to validate the entire pipeline end-to-end on a personal GitHub fork before pointing the production repo at the live Action.

**Files:**
- Create: `docs/phase1-fork-runbook.md`

- [ ] **Step 1: Write the runbook**

Create `docs/phase1-fork-runbook.md`:

````markdown
# Phase 1 fork-test runbook

Run this once before letting the production AI Sherpa repo cut its first
release. Validates: feedback skill → Issue → triage labels → PR → merge
→ release Action → GitHub Release → email → `setup --update` change
summary.

Estimated time: 30–45 minutes.

## 0. Prereqs

- A personal GitHub account.
- `gh` installed and authed against that personal account.
- `jq`, `pandoc`, `bash` available locally.

## 1. Fork the repo

```bash
gh repo fork ccjain/AI-Sherpa-Setup --clone --remote
cd AI-Sherpa-Setup
```

## 2. Trigger the labels sync

```bash
gh workflow run labels-sync.yml --ref master
sleep 30
gh label list --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" | head -20
```

Expected: at least 40 labels listed (status/*, domain/*, type/*, severity/*, source/*, confidence/*, feedback, release-note).

## 3. Set up a test Google Group + Apps Script

For the fork test, create a **personal** Google Group (free Google
account works) and deploy a personal Apps Script per
`tools/mailer/README.md`. Add the resulting `MAILER_URL` and
`MAILER_SECRET` as repo secrets on your fork.

Edit `.github/workflows/release.yml` to change `ANNOUNCE_TO` to your
personal Group email. Commit and push.

## 4. File three fake feedback Issues

For three different domains (e.g., embedded, web, core), open an Issue
manually via the GitHub web UI using the feedback template. Fill in
plausible answers. Confirm:

- Each Issue lands with `feedback`, `status/needs-review`,
  `source/manual` labels.
- The selected domain label was applied.

## 5. Walk Issues through triage

For each Issue:

```bash
ISSUE=NN   # the Issue number
gh issue edit "$ISSUE" --remove-label status/needs-review --add-label status/approved
gh issue edit "$ISSUE" --add-label type/rule-violation --add-label severity/normal
```

## 6. Open three PRs that close the Issues

For each Issue, make a trivial doc tweak on a branch, push, open a PR
using the PR template, fill in `Closes #N` and the
"Release-note line" blockquote. Add the `release-note` label to each PR.

Merge all three PRs to master.

Verify:

- Each source Issue auto-closes (because of `Closes #N`).
- The `auto-label-released` workflow ran and applied
  `status/released` to each closed Issue.

## 7. Manually trigger the release workflow

```bash
gh workflow run release.yml --ref master
```

Watch the run:

```bash
gh run watch
```

Verify:

- A new tag `vYYYY.MM.DD` is created.
- A GitHub Release with that tag exists and contains release notes
  grouped by domain.
- The `VERSION` file is updated on `master`.
- The email step shows green and the personal Google Group received
  the email.

## 8. Test `setup --update` on a fresh-ish machine

On a test machine or container with AI Sherpa not yet installed (or with
`VERSION` artificially rolled back):

```bash
bash setup.sh --update
```

Expected output includes:

```
[AI Sherpa --update] Was: v0.0.0  →  Now: vYYYY.MM.DD
[AI Sherpa --update] Highlights since your last update:
   - <domain>: <release-note line>
   ...
```

## Sign-off

If steps 2–8 all succeeded, the production rollout is just:

1. Deploy the production Apps Script per `tools/mailer/README.md`.
2. Add `MAILER_URL` + `MAILER_SECRET` as production repo secrets.
3. Update `ANNOUNCE_TO` in `.github/workflows/release.yml` to the
   production Google Group address.
4. Merge to master. The cron-scheduled release Action fires the
   following Monday.
````

- [ ] **Step 2: Commit**

```bash
git add docs/phase1-fork-runbook.md
git commit -m "docs: add Phase 1 fork-test runbook"
```

---

## Final integration

### Task 23: Self-review the plan against the spec

Don't dispatch a subagent — run this as a personal review.

- [ ] **Step 1: Spec coverage check**

Open the spec at `docs/superpowers/specs/2026-05-28-feedback-release-pipeline-design.md`. For each numbered section, find the implementing task:

| Spec section | Implementing task(s) |
|---|---|
| §5 Intake (slash command + Issue template) | Tasks 6, 15, 16, 17, 19 |
| §6 Triage (labels + Project board) | Tasks 4, 5; Phase 0.6 (Project board) |
| §7 Implementation (PR convention) | Tasks 2, 3 |
| §8 Release Action | Tasks 7, 8, 10, 13 |
| §9 Notification (Apps Script email) | Tasks 11, 12, 13; Phase 0.3 |
| §10 Update flow (VERSION + change-summary) | Tasks 1, 18 |
| §12 Verification | Task 22 |
| §13 Security & privacy | Covered in skill helpers (Tasks 16, 17) and feedback-guide (Task 20) |
| §14 Repo changes summary | This plan IS the implementation of §14 |
| §15 Rollout plan | Task 22 (fork runbook) + Phase 0 checklist |

No gaps expected. If any spec section maps to no task, add a task to cover it.

- [ ] **Step 2: Placeholder scan**

Run:
```bash
grep -nE 'TBD|TODO|fill in|implement later|add appropriate|similar to Task' \
    docs/superpowers/plans/2026-05-29-phase1-feedback-release-pipeline.md
```
Expected: no matches (or only matches inside fenced code blocks that legitimately contain those words).

- [ ] **Step 3: Type-consistency check**

Skim the plan looking for function/file/label names that should match across tasks:

- Helper names: `Fail-Clean` (PS), `fail_clean` (bash) — referenced only within their own files. OK.
- File paths: `scripts/generate-release-notes.sh` is used in Tasks 8, 10, 14 — verify spelled identically.
- Label names: `release-note` (Tasks 2, 4, 8, 10), `status/needs-review` (Tasks 4, 6, 9, 16, 17), etc.

Skim the plan once. Fix any drift inline.

---

## Spec section 17 — Open implementer questions

These don't change the plan; they're knobs to set during implementation:

1. **Exact cron time/timezone** — Task 10 uses `0 16 * * 1` (Monday 16:00 UTC). Adjust per Phase 0.1.
2. **Apps Script deployer account** — Phase 0.2.
3. **Issue creation restriction** — Phase 0.4 (GitHub Settings, not code).
4. **`--update` always prints change summary** — Task 18 default; if you prefer behind a `--verbose` flag, swap the call.
````
