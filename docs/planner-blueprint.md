# AI Sherpa - Microsoft Planner Blueprint

A copy-paste-ready blueprint for setting up the team's roadmap tracker in
Microsoft Planner. **Manual setup (~10 minutes)** - this is the fallback when
Graph API provisioning is blocked by tenant policy.

> If your tenant *does* allow Graph scopes `Group.ReadWrite.All` +
> `Tasks.ReadWrite`, you can skip this and run `scripts/provision-planner.ps1`
> instead.

---

## 1. Create the plan (1 min)

1. Open **Teams** -> the **AI Sherpa team** channel.
2. Click **+** at the top of the channel -> **Tasks by Planner and To Do**.
3. **Create a new plan** -> name it:

   ```
   AI Sherpa - Roadmap
   ```

4. Pin it to the channel.

(Alt path without Teams: <https://tasks.office.com/> -> **+ New plan**.)

---

## 2. Create the 5 buckets (2 min)

Switch the board to **Group by -> Bucket** (default). Add buckets in this order
(use **Add new bucket** at the right edge of the board):

| # | Bucket name           |
|---|-----------------------|
| 1 | Backlog               |
| 2 | Next up               |
| 3 | In progress           |
| 4 | In review / testing   |
| 5 | Done                  |

---

## 3. Define the 4 labels (1 min)

Open any task -> click the **colored label bar** on the right (or the
**Labels** icon) -> rename the first 4 labels:

| Color slot | Label name           |
|------------|----------------------|
| 1          | Feedback loop        |
| 2          | Knowledge            |
| 3          | Release automation   |
| 4          | Distribution / IT    |

(Planner remembers label names per plan. Other 21 slots stay unused.)

---

## 4. Add the 4 tasks (5 min)

All four tasks go into the **Backlog** bucket. For each one:

1. **+ Add task** in Backlog -> paste the **Title**.
2. Open the task -> paste the **Description** into Notes.
3. Apply the matching **Label** (color from the table above).
4. Add the **Checklist** items one per line via **Add an item**.
5. Leave assignment, dates, and priority blank for now.

### Task 1

- **Title:** `Lesson-learn feedback loop and dashboard`
- **Label:** Feedback loop
- **Description:**

  > Capture per-session learnings from developers and surface them in a
  > team-visible dashboard.

- **Checklist:**
  - Decide capture mechanism (daemon vs. opt-in cmd)
  - Pick storage backend (OneDrive / Git / DB)
  - Dashboard spec
  - MVP dashboard
  - Pilot with 2 devs
  - Team rollout

### Task 2

- **Title:** `Toolchain-specific lesson-learn knowledge`
- **Label:** Knowledge
- **Description:**

  > Separate lesson stores per toolchain (embedded / web / AI) so insights
  > flow to the right audience.

- **Checklist:**
  - Define toolchain taxonomy (embedded / web / AI)
  - Tagging at capture time
  - Per-toolchain retrieval slice
  - Index into Claude memory
  - Validate routing

### Task 3

- **Title:** `Weekly release automation + auto-test`
- **Label:** Release automation
- **Description:**

  > Auto-notify the team on new releases and run the release through an
  > automated test pass before announcement.

- **Checklist:**
  - Pick CI surface (GitHub Actions)
  - Smoke-test matrix (Win / WSL)
  - Release notes generator
  - Teams / email notification
  - Cut first automated release

### Task 4

- **Title:** `IT-managed auto-install and weekly update`
- **Label:** Distribution / IT
- **Description:**

  > Distribute weekly updates through IT-managed channels so developer
  > machines stay current without manual setup.

- **Checklist:**
  - Talk to IT (Intune? winget?)
  - Packaging format
  - Update channel design
  - Signed installer
  - Pilot on 3 machines
  - Org rollout

---

## 5. Operating cadence

- **Weekly:** during standup, walk the board left-to-right. Pull at most 1-2
  items from Backlog into "Next up" per cycle - we are a small team.
- **When work starts:** assign owner, set Start/Due dates, move to
  "In progress".
- **When work ships:**
  1. Move task to **Done**.
  2. Record the work under the right version in
     [`CHANGELOG.md`](../CHANGELOG.md).
  3. Remove the matching line from [`ROADMAP.md`](../ROADMAP.md).

The three artifacts have distinct jobs: **Planner** = live workstream
visibility; **ROADMAP.md** = strategic intent in the repo; **CHANGELOG.md** =
shipped history.

---

## 6. Adding new roadmap items later

1. Add a one-liner to `ROADMAP.md` under **Pending**.
2. Create a matching Planner task in **Backlog** with title + description +
   one label.
3. Add a checklist when the item is picked up - not at creation time.
