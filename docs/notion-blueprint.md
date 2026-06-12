# AI Sherpa - Notion Project Management Blueprint

A copy-paste-ready setup for tracking AI Sherpa development & activity in
Notion. One **Roadmap database** with status, category, priority, and owner
properties; multiple views; one page per roadmap item with description +
checklist.

**Setup time:** ~12 minutes, manual. Notion is updated directly in the UI -
no API or script path.

---

## 1. Create the workspace page (1 min)

In your Notion sidebar:

1. Click **+ Add a page** at the top of the AI Sherpa team space (or in
   Private if piloting solo first).
2. Title it:

   ```
   AI Sherpa - Development & Activity
   ```

3. Inside it, you'll create the Roadmap database as a sub-page.

---

## 2. Create the Roadmap database (2 min)

On the `AI Sherpa - Development & Activity` page:

1. Type `/database` -> pick **Database - Full page**.
2. Title it:

   ```
   Roadmap
   ```

3. Configure properties (delete the default `Tags` first):

| Property name     | Type            | Options / notes                                                                                    |
|-------------------|-----------------|----------------------------------------------------------------------------------------------------|
| Name              | Title (default) | Task title                                                                                         |
| Status            | Status          | Group **To-do:** `Backlog`, `Next up`. Group **In progress:** `In progress`, `In review / testing`. Group **Complete:** `Done`. |
| Category          | Select          | `Feedback loop` (blue), `Knowledge` (green), `Release automation` (yellow), `Distribution / IT` (purple), `Repo structure` (orange) |
| Priority          | Select          | `High` (red), `Medium` (yellow), `Low` (gray) - default Medium                                     |
| Owner             | Person          | Leave blank until pulled into `Next up`                                                            |
| Target release    | Text            | Optional, e.g. `0.6.0`                                                                             |
| Spec / PR         | URL             | Link to design doc or PR once one exists                                                           |

---

## 3. Create the views (3 min)

Click **+ Add view** on the database header:

1. **Board** (default for daily work)
   - Layout: **Board**
   - Group by: **Status**
   - Sort: Priority descending
2. **By Category**
   - Layout: **Board**
   - Group by: **Category**
3. **Table** (full detail)
   - Layout: **Table**
   - Sort: Status ascending, Priority descending
4. **Active**
   - Layout: **Table**
   - Filter: Status is **not** `Done`
5. **This week** (for Shyam's weekly review)
   - Layout: **Table**
   - Filter: Priority is `High` AND Status is `Backlog` or `Next up` or `In progress`
   - Sort: Status ascending

Set **Board** as the default view.

---

## 4. Add the 5 roadmap items (6 min)

For each item: click **+ New** in the Backlog column -> paste **Title** -> set
**Category** + **Priority** -> open the page -> paste **Description** at the
top -> add **Checklist** items as `to-do` blocks (`/todo` or `[]`).

### Item 1

- **Title:** `Lesson-learn feedback loop and dashboard`
- **Status:** Backlog
- **Category:** Feedback loop
- **Priority:** Medium
- **Description:**

  > Capture per-session learnings from developers and surface them in a
  > team-visible dashboard.

- **Checklist:**
  - [ ] Decide capture mechanism (daemon vs. opt-in cmd)
  - [ ] Pick storage backend (OneDrive / Git / DB)
  - [ ] Dashboard spec
  - [ ] MVP dashboard
  - [ ] Pilot with 2 devs
  - [ ] Team rollout

### Item 2

- **Title:** `Toolchain-specific lesson-learn knowledge`
- **Status:** Backlog
- **Category:** Knowledge
- **Priority:** Medium
- **Description:**

  > Separate lesson stores per toolchain (embedded / web / AI) so insights
  > flow to the right audience.

- **Checklist:**
  - [ ] Define toolchain taxonomy (embedded / web / AI)
  - [ ] Tagging at capture time
  - [ ] Per-toolchain retrieval slice
  - [ ] Index into Claude memory
  - [ ] Validate routing

### Item 3

- **Title:** `Weekly release automation + auto-test`
- **Status:** Backlog
- **Category:** Release automation
- **Priority:** Medium
- **Description:**

  > Auto-notify the team on new releases and run the release through an
  > automated test pass before announcement.

- **Checklist:**
  - [ ] Pick CI surface (GitHub Actions)
  - [ ] Smoke-test matrix (Win / WSL)
  - [ ] Release notes generator
  - [ ] Teams / email notification
  - [ ] Cut first automated release

### Item 4

- **Title:** `IT-managed auto-install and weekly update`
- **Status:** Backlog
- **Category:** Distribution / IT
- **Priority:** Medium
- **Description:**

  > Distribute weekly updates through IT-managed channels so developer
  > machines stay current without manual setup.

- **Checklist:**
  - [ ] Talk to IT (Intune? winget?)
  - [ ] Packaging format
  - [ ] Update channel design
  - [ ] Signed installer
  - [ ] Pilot on 3 machines
  - [ ] Org rollout

### Item 5

- **Title:** `Restructure repo to Universal Repository Framework`
- **Status:** Backlog
- **Category:** Repo structure
- **Priority:** High
- **Description:**

  > Align AI Sherpa repo layout with Shyam's Universal Repository Framework:
  > root limited to project-wide files; canonical subfolders for specs / src /
  > tests / docs / knowledge / prompts / data / scripts / assets / archive /
  > scratchpad / .claude. Each top-level dir documents Purpose / Why / Memory
  > Aid. Resolve AI-Sherpa-specific deviations (core/, domains/, setup.ps1 at
  > root) before migrating.

- **Checklist:**
  - [ ] Gap analysis: map current dirs/files to framework targets
  - [ ] Decide AI-Sherpa-specific deviations (core/, domains/, setup at root) - get Shyam's sign-off
  - [ ] Migration plan: file moves + path/import updates + setup.ps1 / setup.sh path updates
  - [ ] Move project-wide files to root, everything else into subfolders
  - [ ] Add README.md in each new top-level dir with Purpose / Why / Memory Aid
  - [ ] Update CLAUDE.md, README.md, ROADMAP.md references to new paths
  - [ ] Run full setup smoke test on Win + WSL
  - [ ] CHANGELOG entry + breaking-change note for users

---

## 5. Operating cadence

- **Weekly review with Shyam:** open the **This week** view. Walk
  highest-priority items, surface blockers, agree what gets pulled into
  `Next up`.
- **Standup / daily:** walk the **Board** view left-to-right. Pull at most
  1-2 items from Backlog into `Next up` per cycle.
- **When work starts:** assign Owner, fill Target release, move to
  `In progress`.
- **When work ships:**
  1. Move to `Done` in Notion.
  2. Record under the right version in [`CHANGELOG.md`](../CHANGELOG.md).
  3. Remove the matching line from [`ROADMAP.md`](../ROADMAP.md).

Source-of-truth split:
- **Notion Roadmap DB** = live workstream visibility, owners, dates,
  priority for weekly review.
- **`ROADMAP.md`** = strategic intent inside the repo, reviewed in PRs.
- **`CHANGELOG.md`** = shipped history, version-tagged.

---

## 6. Adding new roadmap items later

1. Add a one-liner to `ROADMAP.md` under **Pending**.
2. Add a matching item to the Notion Roadmap DB in `Backlog` with Title +
   Description + Category + Priority.
3. Add the checklist when the item is picked up - not at creation time.
