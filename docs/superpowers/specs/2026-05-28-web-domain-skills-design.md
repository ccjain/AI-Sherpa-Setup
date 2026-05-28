# AI Sherpa — Web Domain Skills Design

**Date:** 2026-05-28
**Status:** Approved
**Related:** [2026-05-27-plugin-config-design.md](2026-05-27-plugin-config-design.md), feat commit `65fd763` (skills installer)

---

## Goal

Wire in raw-skill repos that fill known gaps in AI Sherpa's web domain — accessibility, performance / Core Web Vitals, and design-system patterns — using the skills installer shipped in `65fd763`. No new installer code.

## Background

The skills installer (`Install-Skills` in `setup.ps1`, `install_skills` in `setup.sh`) clones each entry under `plugins.json` → `skills.<domain>` and copies its subpath into `~/.claude/skills/`. Embedded is the first consumer (`beriberikix/zephyr-agent-skills`). This spec adds web entries.

Existing web coverage:
- **Plugins** under `domains.web`: `figma`, `frontend-design`, `vercel` (Claude-official marketplace)
- **Global skills** via `fullstack-dev-skills`: 66 stack-specific skills (react-expert, nextjs-developer, vue-expert, etc.) that auto-activate

Gaps not covered by the above: a11y, perf, design-system patterns, frontend-specific security.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Install model | Raw-skill clone+copy (Approach A) | Existing installer handles it; widest candidate pool; pinning gap is acceptable since `--update` is explicit |
| License bar | MIT / Apache-2.0 / BSD / ISC | Permissive only, broadly redistributable |
| Curation target | ~4 entries max | Lean `plugins.json`, low maintenance |
| A11y coverage | Use addyosmani's bundled a11y skill, no dedicated repo | Source-of-truth quality (Google Chrome team), avoids overlap |
| Security gap | Not filled in this iteration | No standalone repo passes §2 bar; existing `secure-code-guardian` + `security-reviewer` globals are sufficient for now |

## Evaluation Criteria

A candidate must meet **all** of:

| Criterion | Bar |
|---|---|
| Schema | At least one valid `SKILL.md` with `name:` and `description:` frontmatter |
| Subpath | `skills/` (default) or explicit path via the `subpath` field |
| License | MIT / Apache-2.0 / BSD / ISC |
| Maintained | Commit within last 6 months OR stable v1+ release |
| Quality signal | ≥50 stars OR named maintainer with prior reputation OR referenced from a known list |
| Topic fit | Description covers one of the four gaps; no generic-dev duplication |

## Selected Entries

### `addyosmani/web-quality-skills`

| Field | Value |
|---|---|
| License | MIT |
| Stars | 2.1k |
| Maintainer | Addy Osmani (Google Chrome team) |
| Subpath | `skills` |
| Coverage | performance, core-web-vitals, accessibility, SEO, best-practices, web-quality-audit |
| Activity | 29 commits on main, active |

Fills: **performance** and **accessibility** gaps.

### `bitjaru/styleseed`

| Field | Value |
|---|---|
| License | MIT |
| Stars | 367 |
| Subpath | `.claude/skills` (non-default — must be specified) |
| Coverage | 69 design rules, 48 shadcn components, brand skins (Toss / Stripe / Linear / Vercel / Notion), Tailwind v4 + Radix |
| Activity | v2.1.1 released 2026-04-10 |

Fills: **design-system** gap.

### Rejected candidates (for the record)

- **`airowe/claude-a11y-skill`** — no LICENSE file, 10 stars, 1 commit total. Fails on three criteria.
- **`masuP9/a11y-specialist-skills`** — MIT, 48 stars (borderline on the 50-star floor but plausibly passes via the "on a known list" OR-clause), 4 dedicated WCAG 2.2 / WAI-ARIA workflows. **Declined** to avoid overlap with addyosmani's a11y coverage, not on quality grounds. Re-evaluate if addyosmani's a11y depth proves insufficient.

## Files Changed

### `plugins.json`

```json
"skills": {
  "global": [],
  "embedded": [
    { "repo": "beriberikix/zephyr-agent-skills", "subpath": "skills" }
  ],
  "web": [
    { "repo": "addyosmani/web-quality-skills",   "subpath": "skills" },
    { "repo": "bitjaru/styleseed",               "subpath": ".claude/skills" }
  ]
}
```

### `docs/user-guide.md`

§6.4 (currently has an "Embedded domain" subsection) gets a parallel "Web domain" subsection:

| Source | Type | Contents |
|---|---|---|
| `figma`, `frontend-design`, `vercel` plugins (from `claude-plugins-official`) | plugins | Existing — design tooling integrations |
| `addyosmani/web-quality-skills` | raw skills | Lighthouse / Core Web Vitals / a11y / SEO / best-practices |
| `bitjaru/styleseed` | raw skills | shadcn + Tailwind v4 + Radix design system, 48 components, brand skins |

## Verification

Smoke test on a clean machine:

```powershell
# From inside the AI Sherpa repo
.\setup.ps1
# Pick: 2 (Web)
# Expected console output:
#   [AI Sherpa] Cloning skills from addyosmani/web-quality-skills...
#   [AI Sherpa] Installed skills from addyosmani/web-quality-skills into <skillsDir>
#   [AI Sherpa] Cloning skills from bitjaru/styleseed...
#   [AI Sherpa] Installed skills from bitjaru/styleseed into <skillsDir>
```

Then verify the skill directories landed:

```powershell
dir $env:USERPROFILE\.claude\skills
```

Expected: multiple new subdirectories from each repo, each with a `SKILL.md`.

Inside Claude Code, ask a Lighthouse-related question and confirm the relevant skill activates (e.g., "Audit this site's Core Web Vitals").

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `styleseed`'s `.claude/skills` subpath misbehaves (e.g., hidden-dir handling on Windows) | Medium | If `Copy-Item` skips it, fall back to `subpath: "."` (whole repo) and accept the extra files |
| Either upstream repo breaks schema on a future commit | Low | `--update` is explicit; team controls when to refresh. Per-repo rollback is just removing one line from `plugins.json` |
| Name collisions between addyosmani's `accessibility` skill and a future a11y repo we add | Low | Same-named SKILL.md would overwrite. Defer until it actually happens |
| Web-security gap stays open | Known | Existing `secure-code-guardian` + `security-reviewer` already cover OWASP basics. Revisit when a focused frontend-sec repo emerges |

## Out of Scope

- Filling the web-security gap (no acceptable repo found this round)
- Adding skills for other domains (data, devops, business) — separate brainstorm
- Vendoring (Approach C) — defer until a specific repo's instability forces it
- Version pinning support in the installer — defer until upstream-drift becomes a real incident

## Rollout

1. Edit `plugins.json`: add the two `web` entries
2. Edit `docs/user-guide.md`: append the web subsection to §6.4
3. Smoke-test on local machine (skills land in `~/.claude/skills/`)
4. Commit both files in one commit
5. (Optional, by user) push to origin/master
