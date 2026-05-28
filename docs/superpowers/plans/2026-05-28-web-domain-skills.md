# Web Domain Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire two raw-skill GitHub repos (`addyosmani/web-quality-skills` and `bitjaru/styleseed`) into AI Sherpa's web domain by adding them to `plugins.json` and documenting them in the user guide.

**Architecture:** No new code. Existing skills installer (`Install-Skills` in `setup.ps1`, `install_skills` in `setup.sh`) already supports `{repo, subpath}` entries under `plugins.json` → `skills.<domain>`. This plan only adds two config rows and a parallel doc subsection.

**Tech Stack:** JSON config (`plugins.json`), Markdown docs (`docs/user-guide.md`), PowerShell + Bash setup scripts (no changes), Git.

**Spec:** `docs/superpowers/specs/2026-05-28-web-domain-skills-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `plugins.json` | Modify | Add two entries under `skills.web` |
| `docs/user-guide.md` | Modify | Add "Web domain" subsection in §6.4 |

No file creation. No new responsibilities.

---

### Task 1: Add web entries to `plugins.json`

**Files:**
- Modify: `plugins.json` (the `skills.web` array, currently `[]` or missing)

- [ ] **Step 1: Read current state of the skills section**

Run:
```bash
git show HEAD:plugins.json | grep -A 6 '"skills"'
```

Expected: a `"skills"` object with at least `"global": []` and `"embedded": [...]`. If `"web"` is already present and non-empty, **stop and reconcile manually** — this plan assumes it's empty.

- [ ] **Step 2: Edit `plugins.json` — add the web entries**

Find this block in `plugins.json`:

```json
  "skills": {
    "global": [],
    "embedded": [
      { "repo": "beriberikix/zephyr-agent-skills", "subpath": "skills" }
    ]
  }
```

Replace it with:

```json
  "skills": {
    "global": [],
    "embedded": [
      { "repo": "beriberikix/zephyr-agent-skills", "subpath": "skills" }
    ],
    "web": [
      { "repo": "addyosmani/web-quality-skills", "subpath": "skills" },
      { "repo": "bitjaru/styleseed",             "subpath": ".claude/skills" }
    ]
  }
```

Notes:
- `bitjaru/styleseed` uses the non-default `.claude/skills` subpath — copy it exactly.
- Do not touch any other section of `plugins.json`.

- [ ] **Step 3: Verify the file is still valid JSON**

Run:
```powershell
Get-Content plugins.json -Raw | ConvertFrom-Json | Select-Object -ExpandProperty skills | ConvertTo-Json
```

Expected output: a JSON object with `global` (empty array), `embedded` (one entry), `web` (two entries — `addyosmani/web-quality-skills` and `bitjaru/styleseed`).

If `ConvertFrom-Json` errors out, the file has a syntax error — fix and re-verify.

- [ ] **Step 4: No commit yet**

Wait — we'll commit `plugins.json` and the doc change together in Task 4.

---

### Task 2: Update `docs/user-guide.md` §6.4 with a "Web domain" subsection

**Files:**
- Modify: `docs/user-guide.md` (§6.4, which currently has only an "Embedded domain" block)

- [ ] **Step 1: Locate §6.4 in the file**

Run:
```bash
git grep -n "### 6.4 Embedded domain" docs/user-guide.md
```

Expected: one match. The "Embedded domain" subsection lives there with a 3-column markdown table.

- [ ] **Step 2: Edit `docs/user-guide.md` — append the web subsection**

Find this exact block:

```markdown
### 6.4 Embedded domain — what you get

After picking domain **1** (Embedded):

| Source | Type | Contents |
|---|---|---|
| `antigravity-bundle-systems-programming` plugin | plugin | Editorial bundle of low-level / systems skills (C, C++, Rust, embedded, performance) |
| `beriberikix/zephyr-agent-skills` | raw skills | 21 Zephyr skills: `board-bringup`, `build-system`, `connectivity-ble`, `devicetree`, `hardware-io`, `kernel-basics`, `kernel-services`, `multicore`, `power-performance`, `security-updates`, `storage`, `testing-debugging`, `zephyr-foundations`, and more |

All of these auto-activate on relevant prompts; none need a slash command.
```

Replace with (i.e. append the Web subsection just after the existing paragraph):

```markdown
### 6.4 Embedded domain — what you get

After picking domain **1** (Embedded):

| Source | Type | Contents |
|---|---|---|
| `antigravity-bundle-systems-programming` plugin | plugin | Editorial bundle of low-level / systems skills (C, C++, Rust, embedded, performance) |
| `beriberikix/zephyr-agent-skills` | raw skills | 21 Zephyr skills: `board-bringup`, `build-system`, `connectivity-ble`, `devicetree`, `hardware-io`, `kernel-basics`, `kernel-services`, `multicore`, `power-performance`, `security-updates`, `storage`, `testing-debugging`, `zephyr-foundations`, and more |

All of these auto-activate on relevant prompts; none need a slash command.

### 6.5 Web domain — what you get

After picking domain **2** (Web):

| Source | Type | Contents |
|---|---|---|
| `figma`, `frontend-design`, `vercel` plugins (from `claude-plugins-official`) | plugins | Design tooling, frontend-design guidance, Vercel deployment workflow |
| `addyosmani/web-quality-skills` | raw skills | Lighthouse / Core Web Vitals / accessibility / SEO / best-practices — Agent Skills from Addy Osmani (Google Chrome team) |
| `bitjaru/styleseed` | raw skills | 69 design rules + 48 shadcn components + brand skins (Toss / Stripe / Linear / Vercel / Notion) on Tailwind v4 + Radix |

The `fullstack-dev-skills` global bundle still applies on top — React, Vue, Next.js, TypeScript, etc. auto-activate as usual.
```

Notes:
- Indent and column alignment must match the existing Embedded table exactly.
- The new subsection is numbered **6.5**, immediately after 6.4. Do not renumber any later sections.

- [ ] **Step 3: Verify section numbering is still sequential**

Run:
```bash
git grep -n "^### 6\." docs/user-guide.md
```

Expected output (in order):
```
### 6.1 Invoking a plugin (slash command)
### 6.2 Invoking a skill (context-triggered)
### 6.3 What's installed on this machine
### 6.4 Embedded domain — what you get
### 6.5 Web domain — what you get
```

If any number is duplicated or skipped, fix it.

- [ ] **Step 4: No commit yet**

Hold for Task 4.

---

### Task 3: Smoke test the installer with the new entries

**Goal:** Confirm `setup.ps1` clones both repos and copies their skill files into `~/.claude/skills/` without errors.

- [ ] **Step 1: Note current skill count**

Run:
```powershell
(Get-ChildItem $env:USERPROFILE\.claude\skills -Directory).Count
```

Record the number (e.g. `21`). After install you should see additional directories.

- [ ] **Step 2: Run setup at user-level for the web domain**

From the AI Sherpa repo root:

```powershell
.\setup.ps1
```

When prompted for domain, enter `2` (Web).

Expected console output, among the install logs:
```
[AI Sherpa] Cloning skills from addyosmani/web-quality-skills...
[AI Sherpa] Installed skills from addyosmani/web-quality-skills into C:\Users\<you>\.claude\skills
[AI Sherpa] Cloning skills from bitjaru/styleseed...
[AI Sherpa] Installed skills from bitjaru/styleseed into C:\Users\<you>\.claude\skills
```

If you see `Subpath '.claude/skills' not found in bitjaru/styleseed`, see "Fallback" below.

- [ ] **Step 3: Verify skill directories landed**

Run:
```powershell
Get-ChildItem $env:USERPROFILE\.claude\skills -Directory | Select-Object Name | Format-Table -AutoSize
```

Expected: at minimum, several new entries that did not exist before — e.g. `performance`, `accessibility`, `seo`, `core-web-vitals`, `best-practices` (from addyosmani) and `ss-setup`, `ss-component`, `ss-page` (from styleseed).

- [ ] **Step 4: Spot-check one SKILL.md from each repo**

Run:
```powershell
Get-Content $env:USERPROFILE\.claude\skills\performance\SKILL.md -TotalCount 5
Get-Content $env:USERPROFILE\.claude\skills\ss-setup\SKILL.md -TotalCount 5
```

(Substitute the actual directory names from Step 3 if they differ.)

Expected: each starts with frontmatter (`---` then `name:` and `description:` lines).

- [ ] **Step 5: Fallback if `bitjaru/styleseed` subpath fails**

If Step 2 logged a `Subpath '.claude/skills' not found` warning, the `.claude/` prefix may have been filtered out during clone or copy. Two options:

**Option A (preferred): change subpath to `.`** — copies the whole repo into `~/.claude/skills/`, which puts the `.claude/skills/*` dirs at `~/.claude/skills/.claude/skills/*`. Not great — abandon and try Option B.

**Option B: vendor styleseed into the AI Sherpa repo.** Out of scope for this plan. Open a follow-up issue and remove the styleseed entry from `plugins.json` for now. Mark this plan complete with one of two web entries delivered.

Do not silently skip the failure — document the outcome before moving on.

---

### Task 4: Commit both file changes

**Files:**
- `plugins.json`
- `docs/user-guide.md`

- [ ] **Step 1: Stage both files**

```bash
git add plugins.json docs/user-guide.md
```

Do **not** use `git add -A` — there are unrelated modified files in the working tree that should not ride along.

- [ ] **Step 2: Verify staged contents**

```bash
git diff --staged --stat
```

Expected: exactly two files changed — `plugins.json` and `docs/user-guide.md`. If you see anything else, run `git restore --staged <unwanted-file>` to unstage it.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: wire addyosmani/web-quality-skills + bitjaru/styleseed into web domain

Adds two raw-skill repos to `plugins.json` under `skills.web`:
- addyosmani/web-quality-skills — perf, Core Web Vitals, a11y, SEO, best practices
- bitjaru/styleseed — 48 shadcn components + Tailwind v4 + Radix design system

Adds a parallel "Web domain — what you get" subsection (§6.5) to the user
guide, listing the installed plugins + raw skills.

Web-security gap intentionally not filled this iteration; existing global
skills (secure-code-guardian, security-reviewer) cover OWASP basics.

Spec: docs/superpowers/specs/2026-05-28-web-domain-skills-design.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify commit**

```bash
git log --oneline -1
git show --stat HEAD
```

Expected: latest commit message starts with `feat: wire addyosmani/web-quality-skills + bitjaru/styleseed`, two files changed.

---

### Task 5: (Optional, by user request) Push to origin

Only run this if the user explicitly asks. Do not push proactively.

- [ ] **Step 1: Push current branch**

```bash
git push
```

Expected: branch is now in sync with origin/master.

---

## Verification Summary

After all tasks complete:

1. `plugins.json` has `skills.web` populated with two `{repo, subpath}` entries.
2. `docs/user-guide.md` §6.5 documents the web domain installation.
3. Skill directories from both repos exist under `~/.claude/skills/`.
4. At least one new commit on the branch with both files.

If any of these is missing, the plan is not complete. Re-run the affected task.

---

## Out of Scope (not in this plan — see spec)

- Filling the web-security gap (no acceptable repo found this round)
- Adding skills for data / devops / business domains
- Version pinning in the installer
- Vendoring the styleseed skills directly into AI Sherpa
