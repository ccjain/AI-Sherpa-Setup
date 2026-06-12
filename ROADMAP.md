# Roadmap

Pending AI Sherpa improvements, in no particular order. Shipped work lives in
[CHANGELOG.md](CHANGELOG.md); this file tracks what's still ahead. Each item is
a one-liner — scope, design, and success criteria get fleshed out when the item
is picked up (run `superpowers:brainstorming` at that point).

## Pending

- **Lesson-learn feedback loop and dashboard** — capture per-session learnings
  from developers and surface them in a team-visible dashboard.
- **Toolchain-specific lesson-learn knowledge** — separate lesson stores per
  toolchain (embedded / web / AI) so insights flow to the right audience.
- **Weekly release automation** — auto-notify the team on new releases and run
  the release through an automated test pass before announcement.
- **IT-managed auto-install and update** — distribute weekly updates through
  IT-managed channels so developer machines stay current without manual setup.
- **Restructure repo to Universal Repository Framework** — align layout with
  Shyam's framework: root limited to project-wide files; canonical subfolders
  for specs / src / tests / docs / knowledge / prompts / data / scripts /
  assets / archive / scratchpad / .claude.

## How to use this file

- Add new pending items as one-line bullets under **Pending**.
- When work starts on an item, link the PR / spec doc inline.
- When work ships, move the entry to `CHANGELOG.md` under the right release
  and delete it from here.
