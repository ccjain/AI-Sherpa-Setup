> **ARCHIVED 2026-05-30.** Superseded by [docs/superpowers/2026-05-30-program-v2.md](../../2026-05-30-program-v2.md).
> Preserved for historical context. Not authoritative. Do not cite.

# AI Sherpa — Feedback & Release Pipeline Design

**Date:** 2026-05-28
**Status:** Spec (pre-implementation)
**Scope:** End-to-end thin-slice pipeline from developer feedback to released update, deployed to the central AI Sherpa team for use across 10+ teams / 150+ developers.

---

## 1. Goals

1. Make it easy for any developer using AI Sherpa to report when Claude gives wrong or unsafe advice.
2. Give the central AI Sherpa team a clear, low-overhead workflow to triage feedback and approve or reject each item.
3. Turn approved feedback into versioned releases of AI Sherpa on a predictable weekly cadence with auto-generated release notes.
4. Notify all teams of every new release by email with a concise summary and a one-line update command.

## 2. Non-Goals

- AI-assisted auto-triage (deliberately deferred — Approach A explicitly chose manual triage).
- A custom web dashboard for the triage team.
- Auto-update of dev machines (devs still manually run `setup --update`).
- Per-team customization or branching of releases.
- Multi-channel notifications (Slack/Teams) — email only for v1.

## 3. Constraints & Context

| Item | Value |
|---|---|
| Repo host | Public GitHub, org-owned |
| Scale | 10+ teams, 150+ developers |
| Ownership | One central AI Sherpa team approves all changes |
| Feedback channel | In-Claude slash command (primary), GitHub Issue web UI (fallback, same template) |
| Release cadence | Weekly scheduled (default Monday) + manual dispatch for hotfixes |
| Notification path | Google Apps Script Web App → Google Group distribution list |
| Update mechanism | Existing `setup.bat --update` / `setup.sh --update` (no change to runtime model) |

---

## 4. Architecture

Five components stitched together with GitHub-native primitives. No custom services to host; one external dependency (a Google Apps Script Web App) for email sending.

```
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ 1. INTAKE        │   │ 2. TRIAGE        │   │ 3. IMPLEMENT     │
│  /ai-sherpa-     │──▶│  Labels +        │──▶│  Approved items  │
│  feedback        │   │  Project board   │   │  → PRs → merge   │
│  → GH Issue      │   │  (central team)  │   │  to main         │
└──────────────────┘   └──────────────────┘   └──────────────────┘
                                                       │
                                                       ▼
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│ 5. UPDATE        │   │ 4b. NOTIFY       │   │ 4a. RELEASE      │
│  Devs run        │◀──│  Apps Script     │◀──│  Weekly Action:  │
│  setup --update  │   │  → Google Group  │   │  tag + notes +   │
│                  │   │                  │   │  GH Release      │
└──────────────────┘   └──────────────────┘   └──────────────────┘
```

| # | Component | Lives in | Responsibility |
|---|---|---|---|
| 1 | Slash command + skill | `skills/ai-sherpa-feedback/SKILL.md` shipped by AI Sherpa setup, installs to `~/.claude/skills/ai-sherpa-feedback/` | Collect context, draft body, file Issue via `gh` |
| 2 | Issue template + labels + Project board | `.github/ISSUE_TEMPLATE/feedback.yml`, `.github/labels.yml`, GitHub Projects v2 config | Define feedback schema; enforce triage workflow |
| 3 | PR convention | `.github/pull_request_template.md`, `CONTRIBUTING.md` | Link each merged PR to its source feedback Issue; carry a release-note line |
| 4 | Release Action | `.github/workflows/release.yml` + `scripts/generate-release-notes.sh` | Cron-weekly: discover release-eligible PRs, tag, generate notes, create GH Release, trigger email |
| 5 | Update path | Existing `setup.bat` / `setup.sh` + new version-print logic | After email, dev runs `--update` and gets latest rules |

**Key design principle:** Each component reads and writes a single, well-defined artifact (Issue, label, PR, tag, GitHub Release, email). No shared state, no custom database — the pipeline is git + GitHub.

---

## 5. Component 1 — Intake (`/ai-sherpa-feedback`)

### 5.1 Slash command + skill

Installed by AI Sherpa setup as a skill at `~/.claude/skills/ai-sherpa-feedback/SKILL.md`. The skill's `description:` triggers on `/ai-sherpa-feedback` and on natural-language phrases such as "the rule didn't fire", "Claude got this wrong", or "AI Sherpa missed".

When triggered, the skill performs five steps, all in-terminal:

1. **Detect domain.** Read `~/.claude/CLAUDE.md`; match the H1 header (e.g. `AI Sherpa — Embedded Software Rules` → `embedded`). If no match, ask the developer once via `AskUserQuestion`.
2. **Capture transcript context.** Show the developer the last user prompt and last assistant response from the current session. Let them edit or fully delete the context block before submission. Default to showing, not silently grabbing — code may be confidential.
3. **Ask four short questions** via `AskUserQuestion`:
   - What did you ask Claude to do? (one line)
   - What did Claude do wrong? (one line)
   - What should it have done? (one line)
   - Which rule was violated, if known? (free text, optional)
4. **Render and confirm.** Print the assembled Issue body; ask "OK to file?". The developer can answer "no" and abort with no side effects.
5. **File via `gh`.** Run `gh issue create --repo <org>/ai-sherpa --template feedback.yml --title "[feedback] <one-line summary>" --body-file <tmp>`. Print the Issue URL.

### 5.2 Authentication

Skill requires `gh auth status` to pass. If `gh` is missing or unauthenticated, the skill prints the exact install + `gh auth login` instructions for the developer's platform and exits cleanly without filing anything. AI Sherpa itself does not store or proxy any GitHub tokens — every developer rides on their own `gh` auth.

### 5.3 GitHub Issue form template

`.github/ISSUE_TEMPLATE/feedback.yml`:

```yaml
name: AI Sherpa Feedback
description: Report a case where Claude gave wrong or unsafe advice.
labels: ["feedback", "status/needs-review"]
body:
  - type: dropdown
    id: domain
    attributes:
      label: Domain
      options: [embedded, web, data, devops, marketing, sales, finance, service, procurement, uiux, core]
    validations: { required: true }
  - type: textarea
    id: asked
    attributes: { label: "What you asked Claude to do" }
    validations: { required: true }
  - type: textarea
    id: did
    attributes: { label: "What Claude did (paste response or describe)" }
    validations: { required: true }
  - type: textarea
    id: expected
    attributes: { label: "What it should have done" }
    validations: { required: true }
  - type: input
    id: rule
    attributes: { label: "Violated rule (if known)" }
  - type: textarea
    id: context
    attributes: { label: "Transcript context (auto-filled, edit to redact)" }
```

The slash command submits this form; the same template also works for developers who file from the GitHub web UI directly (zero-friction fallback path).

### 5.4 Privacy stance

The skill always shows captured transcript context to the developer before submission and lets them edit. It never auto-submits. The Issue template's `context` field is freely editable in the GitHub web UI as well.

---

## 6. Component 2 — Triage (labels + Project board)

### 6.1 Lifecycle

A feedback Issue moves through states by replacing exactly one `status/*` label at a time:

```
status/needs-review  ──▶  status/approved  ──▶  status/in-progress  ──▶  status/released (closed)
                     ╲
                      ╲──▶ status/rejected   (closed)
                       ╲─▶ status/duplicate  (closed, linked to original)
```

### 6.2 Label taxonomy

Defined once in `.github/labels.yml`; applied to the repo by a one-shot Action on first push.

| Prefix | Labels | Purpose |
|---|---|---|
| `status/` | `needs-review`, `approved`, `in-progress`, `released`, `rejected`, `duplicate` | Pipeline state — exactly one applied at any time |
| `domain/` | `embedded`, `web`, `data`, `devops`, `marketing`, `sales`, `finance`, `service`, `procurement`, `uiux`, `core` | Which area is affected; matches `domains/` folders plus `core` |
| `type/` | `rule-violation`, `enhancement`, `bug`, `docs` | What kind of change |
| `severity/` | `critical`, `high`, `normal`, `low` | Triage priority |
| `release-note` | (single label) | Applied to a PR whose changes should appear in release notes |

### 6.3 Project board

A single GitHub Projects v2 board for the repo, kanban view. Columns map 1:1 to `status/*` labels via Project workflow rules (`when label status/approved added → move to Approved column`). New Issues automatically land in the Inbox column because the Issue template applies `status/needs-review`.

### 6.4 Triage cadence

The central AI Sherpa team holds a weekly 30-minute triage (default: Friday). The goal of the meeting is to empty the Inbox column by end of day:

- **Approve** → label `status/approved` + `domain/*` + `type/*` + `severity/*`.
- **Reject** → label `status/rejected` + a comment explaining why; the submitter is auto-notified by GitHub.
- **Duplicate** → label `status/duplicate`, post `Duplicate of #<original>`, close. The original Issue tracks the duplicate count so submitters know their report mattered even if marked dup.

### 6.5 No automation in this layer

Per the chosen approach (Approach A — thin glue), label-applying is fully manual. The Project board does the visualization; humans do the sorting. AI-assisted auto-triage is deferred (see §16, Future work).

---

## 7. Component 3 — Implementation (approved → PR → merge)

### 7.1 The convention

Every fix or rule update lands as a PR that:

1. **Body contains `Closes #<N>`** linking the source feedback Issue (merging the PR auto-closes the Issue).
2. **Carries the `release-note` label** (added by a reviewer once the release-note line is acceptable).
3. **Body contains a `> ` blockquote line** under the *Release-note line* heading. This blockquote is what the release Action extracts verbatim.

### 7.2 PR template

`.github/pull_request_template.md`:

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
```

### 7.3 Why per-PR notes rather than a CHANGELOG file

A single edited `CHANGELOG.md` becomes a merge-conflict hotspot at high PR volume. Per-PR release-note metadata is conflict-free; the Action assembles the CHANGELOG at release time.

### 7.4 Issue lifecycle on merge

When a PR merges:

1. `Closes #N` closes the source Issue.
2. A small repo Action listens for `issues.closed` and replaces the Issue's existing `status/in-progress` (or `status/approved`) label with `status/released`.
3. The submitter receives an automatic GitHub notification linking to the PR.

### 7.5 Who writes the PR

The central AI Sherpa team. Approach A does not include AI-generated PRs. For small rule additions (a single line in a `domains/*/CLAUDE.md`), this is trivial work; for larger changes, normal review and merge process applies.

---

## 8. Component 4a — Release Action

### 8.1 Trigger

```yaml
on:
  schedule:
    - cron: '0 16 * * 1'   # Mondays 16:00 UTC ≈ 09:00 PT (adjust to team timezone)
  workflow_dispatch: {}
```

### 8.2 Versioning scheme

**CalVer:** `vYYYY.MM.DD` (e.g., `v2026.06.01`).

Rationale: AI Sherpa is a config bundle, not an API consumers semver-depend on. What teams care about is *is this the latest set of rules?* A calendar version makes that obvious at a glance and removes "major vs. minor" arguments from every release.

### 8.3 Action steps (single job)

`.github/workflows/release.yml`. The job declares `permissions: contents: write` (needed for the commit-back in step 8) and uses a step id of `release` on step 7 so the email step in §9.5 can read `steps.release.outputs.tag` and `steps.release.outputs.item_count`.

1. `actions/checkout@v4` with `fetch-depth: 0` (full history needed for tag lookup).
2. **Compute previous tag and new tag.** `PREV_TAG=$(git describe --tags --abbrev=0)`; `NEW_TAG="v$(date -u +%Y.%m.%d)"`.
3. **Find release-eligible merged PRs.**
   ```bash
   gh pr list --base master --state merged --label release-note \
     --search "merged:>$(git log -1 --format=%cI $PREV_TAG)" \
     --json number,title,body,labels,author,url > prs.json
   ```
4. **Bail out cleanly if no items.** If `prs.json` is empty, post a workflow-summary note ("no release-eligible PRs this week, skipping") and `exit 0`. **No empty releases.** Skipping leaves `steps.release.outputs.tag` empty, which gates the email step (§9.5).
5. **Generate release notes.** Run `scripts/generate-release-notes.sh "$PREV_TAG" "$NEW_TAG" prs.json > notes.md`. The script groups items by `domain/*` label and extracts each PR's blockquoted release-note line. Writes `notes.md` to the job workspace.
6. **Convert to HTML.** `pandoc notes.md -o notes.html`. Writes `notes.html` to the job workspace.
7. **Create the GitHub Release** — this is the step with `id: release`. Set step outputs `tag=$NEW_TAG` and `item_count=$(jq length prs.json)` via `$GITHUB_OUTPUT`.
   ```bash
   gh release create "$NEW_TAG" --title "AI Sherpa $NEW_TAG" --notes-file notes.md --target master
   echo "tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
   echo "item_count=$(jq 'length' prs.json)" >> "$GITHUB_OUTPUT"
   ```
8. **Stamp `VERSION` and update `CHANGELOG.md`.** Commit both back to `master` via the default `GITHUB_TOKEN` (the workflow has `permissions: contents: write`) with a `[skip ci]` message to avoid loop-triggering.
9. **Email step.** The next step (§9.5) reads `notes.md` and `notes.html` directly from the job workspace; nothing needs to be passed explicitly.

### 8.4 Release-notes shape

```markdown
# AI Sherpa v2026.06.01

_Released 2026-06-01. 7 fixes across 4 domains._

## Embedded
- Warn before suggesting malloc in ISRs (#142, thanks @alice)
- …

## Web
- …

## Core / tooling
- …

## How to update
Run `setup.bat --update` (Windows) or `bash setup.sh --update` (Linux/macOS/WSL).
Full diff: <compare-url>
```

### 8.5 Repository artifacts to add

- `.github/workflows/release.yml` — the workflow.
- `scripts/generate-release-notes.sh` — pure function over `prs.json`; locally testable with fixture inputs.
- `VERSION` — single-line file at repo root containing the current tag; written by the Action.

### 8.6 Manual release / hotfix path

A maintainer runs the workflow via `gh workflow run release.yml` (CLI) or the "Run workflow" button in the Actions UI. Same code path executes — no special hotfix branch is required.

### 8.7 Failure modes

| Condition | Action behavior |
|---|---|
| Previous tag lookup fails | Action errors loudly and exits non-zero; no release is created. |
| No release-eligible PRs | Workflow-summary message; exit 0 (no release, no email). |
| `gh release create` fails | Action errors; no email sent (the email step is gated on a successful release). |
| Email step fails after tag exists | Tag and GitHub Release remain; maintainer re-runs just the email step. (Idempotency caveat: re-running sends a second email. Accepted trade-off.) |

---

## 9. Component 4b — Email notification (Google Apps Script Web App)

### 9.1 Distribution list

Google Group `ai-sherpa-announce@<your-org>` in announce-only mode (only the sender can post; members read-only).

### 9.2 Sender identity

The Apps Script runs as its **deploying user** (a designated AI Sherpa team Workspace account, e.g., `ai-sherpa@<org>` if available; otherwise the team lead's account). `MailApp.sendEmail()` sends from that identity. No service mailbox, no SMTP App Password, no SMTP creds in GitHub secrets.

### 9.3 Apps Script Web App

A single short script deployed at `script.google.com`. The source is checked into the repo at `tools/mailer/mailer.gs` so it has version history; the deployment itself is manual.

```javascript
function doPost(e) {
  const expected = PropertiesService.getScriptProperties().getProperty('SHARED_SECRET');
  const p = JSON.parse(e.postData.contents);
  if (p.secret !== expected) {
    return ContentService.createTextOutput('forbidden').setHttpResponseCode(403);
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

### 9.4 One-time deployment steps (`tools/mailer/README.md`)

1. Open `script.google.com`, create a new project named "AI Sherpa Mailer", paste `mailer.gs`.
2. Project Settings → Script Properties → add `SHARED_SECRET` = a random 32-byte hex string.
3. Deploy → New deployment → Type: **Web App** → Execute as: **Me** → Access: **Anyone**.
4. Copy the deployment URL (`https://script.google.com/macros/s/AKfycb…/exec`).
5. GitHub repo → Settings → Secrets and variables → Actions → add `MAILER_URL` (the URL) and `MAILER_SECRET` (the matching hex string).

### 9.5 Release-workflow email step

```yaml
- name: Send release email
  if: steps.release.outputs.tag != ''
  run: |
    jq -n \
      --arg secret   "${{ secrets.MAILER_SECRET }}" \
      --arg to       "ai-sherpa-announce@<org>" \
      --arg subject  "AI Sherpa ${{ steps.release.outputs.tag }} released — ${{ steps.release.outputs.item_count }} fixes" \
      --rawfile body     notes.md \
      --rawfile htmlBody notes.html \
      '{secret:$secret,to:$to,subject:$subject,body:$body,htmlBody:$htmlBody}' \
    | curl -sSf -X POST -H "Content-Type: application/json" \
        --data-binary @- "${{ secrets.MAILER_URL }}"
```

### 9.6 Email body

```
AI Sherpa v2026.06.01 is live.

7 fixes across 4 domains this week. Highlights:
  • Embedded: warn before malloc in ISRs
  • Web: stricter accessibility checks
  • Core: faster `setup --update`

▶ Full release notes: <github release URL>
▶ How to update:
    Windows:        setup.bat --update
    Linux/macOS/WSL: bash setup.sh --update

▶ Not subscribed? Self-subscribe at:
    https://groups.google.com/a/<org>/g/ai-sherpa-announce

— AI Sherpa team
```

Kept short on purpose: the full notes are one click away on GitHub. The email's job is to *announce* a release and tell devs how to pull it, not to be the canonical changelog.

### 9.7 Auth model

The Web App URL alone is not sufficient to send — the script enforces `SHARED_SECRET` on every POST body. A URL leak alone does not enable sending. Secret rotation: edit the Apps Script property and the matching GitHub secret in tandem.

### 9.8 Quotas

`MailApp` caps at 1500 recipients per deployer per day. We send 1 email per week to a single Google Group address; Google fans out internally and does not count against the per-user quota. No concern.

### 9.9 Subscription model

**Self-subscribe only (v1).** Setup prints the Group URL during install. Programmatic auto-subscription via the Workspace Admin SDK is deferred — it requires a service account with admin scope and adds setup complexity. If self-subscribe uptake is poor, upgrade to programmatic in a later iteration.

### 9.10 Failure modes documented in `tools/mailer/README.md`

| Symptom | Diagnosis |
|---|---|
| 403 "forbidden" from Apps Script | `MAILER_SECRET` in GitHub does not match `SHARED_SECRET` in Apps Script. Re-sync. |
| Apps Script returns the HTML auth page (200 OK, no email sent) | Deployment was re-saved without re-authorizing scopes. Open Apps Script, run `doPost` once manually to re-grant the `MailApp` scope. |
| Quota exceeded | Unlikely at our volume; switch deployer account if it ever happens. |

---

## 10. Component 5 — Update flow (developer side)

### 10.1 Existing tooling reused

`setup.bat --update` (Windows) and `bash setup.sh --update` (Linux/macOS/WSL) are already the canonical update path. They pull the latest repo content and refresh plugins. **No change to runtime model.**

### 10.2 Additions made by this design

1. **`VERSION` file at repo root.** Single line containing the current release tag (e.g., `v2026.06.01`). Written by the release Action (§8.5). Allows `--update` to print a "Was → Now" line.
2. **Version footer in `core/CLAUDE.md`.** Release Action prepends a comment line:
   ```markdown
   <!-- AI Sherpa v2026.06.01 — installed YYYY-MM-DD via setup.bat --update -->
   ```
   Lets developers self-diagnose by running `head -1 ~/.claude/CLAUDE.md`.
3. **`--update` change-summary tail.** After pulling, the setup script reads `git log $OLD_VERSION..HEAD -- VERSION` to enumerate intermediate release tags, then calls `gh release view <tag>` to print a cumulative summary. Critical when a developer has missed multiple weekly releases.

### 10.3 Sample `--update` output

```
[AI Sherpa --update] Pulling latest from origin/master...
[AI Sherpa --update] Was: v2026.05.18  →  Now: v2026.06.01
[AI Sherpa --update] Updating plugins from plugins.json...
[AI Sherpa --update] Refreshing settings template (your project CLAUDE.md not touched)...
[AI Sherpa --update] Done. Highlights since your last update:
   - Embedded: warn before malloc in ISRs
   - Web: stricter accessibility checks
[AI Sherpa --update] Full notes: https://github.com/<org>/ai-sherpa/releases/tag/v2026.06.01
```

### 10.4 Explicitly deferred

A "version check at Claude startup" that hits the network on every session is **out of scope**. The email + manual `--update` loop is enough for v1.

---

## 11. Data flow (single feedback item, end-to-end)

```
Developer hits a bad Claude response
        │
        ▼
Types /ai-sherpa-feedback
        │  → skill collects domain, transcript, answers
        ▼
gh issue create  →  GH Issue #142  (status/needs-review)
        │
        ▼
Central team triage (Fri) → label status/approved + domain/embedded + type/rule-violation
        │
        ▼
Team member opens PR #157  (Closes #142, blockquoted release-note line, label release-note)
        │
        ▼
PR merges to master  →  #142 auto-closes  →  status/released applied by auto-labeler
        │
        ▼
Monday release Action runs  →  finds #157 in release-note set
        │
        ▼
Tag v2026.06.01 + GH Release with notes + VERSION bump
        │
        ▼
Apps Script email  →  ai-sherpa-announce@<org>  →  fans out to all devs
        │
        ▼
Dev sees email, runs setup --update → new rules live on their machine
```

Each transition is one GitHub primitive (label change, PR merge, tag creation, Release publish, HTTP POST). No background workers, no custom state machine.

---

## 12. Verification strategy

This pipeline is mostly process + GitHub config + a few shell scripts, so "testing" looks different from a typical service. Three checks before declaring done:

### 12.1 Local-testable pieces (script-level tests)

- **`scripts/generate-release-notes.sh`** — feed it two tags from real history and a recorded `gh pr list` JSON fixture; assert the rendered Markdown matches a checked-in golden file.
- **`setup --update` version-print** — assert that running update after artificially rolling back the `VERSION` file prints the correct "Was → Now" line.

### 12.2 Integration smoke test (manual)

`tools/release-dry-run.sh` runs the release-discovery + notes-generation logic against the last 7 days of merged PRs *without* tagging or sending email. Prints the proposed tag, the rendered Markdown + HTML notes, and the proposed email body. Maintainer reviews; same script is what someone runs to debug a misbehaving live release.

### 12.3 End-to-end on a private fork (one-time before launch)

1. Fork to a personal account.
2. Create 2–3 dummy feedback Issues; take each through the full lifecycle (label, PR with `Closes`, merge, `release-note` label).
3. Trigger the release Action via `workflow_dispatch`.
4. Confirm: tag created, GitHub Release created with correct notes, `VERSION` updated, test email arrives at a personal Google Group, `--update` from a test machine shows the right "Was → Now".

If all three pass, production rollout is: deploy Apps Script + add repo secrets + enable the cron Action.

---

## 13. Security & privacy

| Concern | Mitigation |
|---|---|
| Feedback may include proprietary code in the transcript | Skill always shows context to the developer before submission; never auto-submits. Issue template `context` field is freely editable in the web UI. |
| GitHub auth | No tokens managed by AI Sherpa. Developers ride on their own `gh auth`. |
| Apps Script URL leak | URL alone is not sufficient — script enforces `SHARED_SECRET` on every POST. |
| Secret rotation | `MAILER_SECRET` and `SHARED_SECRET` can be rotated in tandem; documented in `tools/mailer/README.md`. |
| Replay of a captured POST | Not an integrity threat — replaying the request just resends an already-sent email to the same Group. Acceptable. |
| Issue spam from outside contributors | Repo is org-owned; restrict Issue creation to org members if needed (GitHub setting). |
| Email going to the wrong recipient | Group is announce-only and explicitly named; subject prefix `AI Sherpa` makes the source unmistakable. |

---

## 14. Repository changes summary

New files / dirs:

- `skills/ai-sherpa-feedback/SKILL.md` (+ supporting files) — the in-Claude slash command skill.
- `.github/ISSUE_TEMPLATE/feedback.yml` — feedback form schema.
- `.github/labels.yml` — label taxonomy + a one-shot Action to sync.
- `.github/pull_request_template.md` — PR convention with release-note line.
- `.github/workflows/release.yml` — weekly release Action.
- `.github/workflows/auto-label-released.yml` — small Action listening for `issues.closed` to apply `status/released`.
- `scripts/generate-release-notes.sh` — notes assembler.
- `tools/mailer/mailer.gs` — checked-in copy of the Apps Script source.
- `tools/mailer/README.md` — deployment + rotation instructions.
- `tools/release-dry-run.sh` — local debugging helper.
- `VERSION` — single-line release tag; updated by the release Action.

Modified files:

- `setup.bat` and `setup.sh` — add version-print + change-summary tail to `--update`; install the feedback skill alongside other skills.
- `docs/feedback-guide.md` — replace the v1 manual-GH-Issue instructions with the slash command flow; add a section on the lifecycle (triage states) and the weekly release cadence.
- `docs/user-guide.md` — mention `/ai-sherpa-feedback` and the release email under "How feedback and updates work".
- `CONTRIBUTING.md` (new or modified) — describe the PR convention.

GitHub config (one-time, not in repo files):

- Google Group `ai-sherpa-announce@<org>` (announce-only).
- Apps Script deployment (URL + `SHARED_SECRET`).
- Repo secrets `MAILER_URL`, `MAILER_SECRET`.
- GitHub Projects v2 board with `status/*` column rules.
- Optional: restrict Issue creation to org members.

---

## 15. Rollout plan

1. **Land the GitHub-side scaffolding** in a single PR: labels, Issue template, PR template, both Actions, scripts, `VERSION`, `tools/mailer/`. Test via dry-run.
2. **Deploy Apps Script** and add repo secrets.
3. **Land the feedback skill** in a second PR; update `setup.sh` / `setup.bat` to install it.
4. **Run the end-to-end fork test** (§12.3).
5. **Update `feedback-guide.md` and `user-guide.md`** to reflect the new flow.
6. **Announce internally** (one-time manual email): explain the new flow, link to the Google Group, ask devs to subscribe.
7. **Cut the first scheduled release** the following Monday.

---

## 16. Future work (explicitly out of scope)

- **AI-assisted auto-triage** (Approach B). On every new feedback Issue, a small Action calls Claude (Haiku) to auto-label by domain, find near-duplicates, post a one-line summary. Add when the central team's triage burden becomes the bottleneck.
- **Triage dashboard** (Approach C). A hosted UI for bulk operations, dedup view, PR-draft generation. Only justified if the triage team grows.
- **Programmatic Google Group subscribe** on `setup`. Worth doing if self-subscribe uptake is poor.
- **Startup version-check in Claude** that warns when local version is older than latest. Defer until / unless missed-update is a real observed problem.
- **Slack notification** alongside email. Easy to add by extending `mailer.gs` to also POST to a Slack webhook; not in v1.

---

## 17. Open questions for the implementing engineer

These are intentionally left for the implementer; they do not change the architecture.

1. Exact cron time and timezone (Monday 09:00 PT? UTC? team preference).
2. Which AI Sherpa Workspace account deploys the Apps Script (`ai-sherpa@<org>` shared account, or a team lead's account).
3. Whether to restrict feedback Issue creation to org members (recommended yes).
4. Whether `--update` should print the change summary by default or only with `--verbose` (recommended: default on; it's short).
