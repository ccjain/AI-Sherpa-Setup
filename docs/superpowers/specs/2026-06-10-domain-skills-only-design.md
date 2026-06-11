# AI Sherpa — Domain Skills Only (drop domain CLAUDE.md) Design

**Date:** 2026-06-10
**Status:** Approved
**Related:** [2026-05-28-web-domain-skills-design.md](2026-05-28-web-domain-skills-design.md), [2026-05-29-plugin-invocation-contracts-design.md](2026-05-29-plugin-invocation-contracts-design.md)

---

## Goal

Replace per-domain `domains/<name>/CLAUDE.md` files with per-domain `ai-sherpa-<domain>` skills installed under `~/.claude/skills/`. The merged `~/.claude/CLAUDE.md` shrinks to core-only content (~164 lines instead of ~280–320 lines), and domain-specific rules load progressively when their skill description matches the user's task.

## Background

Today the AI Sherpa setup script concatenates `core/CLAUDE.md` + `domains/<picked>/CLAUDE.md` into `~/.claude/CLAUDE.md`. Every turn in every project pays the full token cost of all 8 active domains' worth of context (whichever one the developer picked at setup), regardless of what task is actually being run.

Claude Code's skills system loads skill **descriptions** always (cheap; ~250 chars × 8 ≈ ~500 tokens) but loads skill **bodies** only when Claude judges the description relevant to the current task. Moving domain rules from CLAUDE.md to skill bodies preserves the rules but shifts their cost from "every turn" to "only when relevant."

The risk: rules currently always-on (security guardrails, Always-Do / Never-Do lists, the MANDATORY Plugin Invocation Contract) become lazy. We mitigate that by using **one broadly-described skill per domain** so any task in the domain triggers the skill — making the guardrails effectively always-on within the domain.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Conversion scope | Full conversion: delete domain CLAUDE.md, all content moves to skills | Maximum token savings; user accepts lazy-loading tradeoff with mitigation via broad descriptions |
| Granularity | One skill per domain (~8 skills total) | Broad descriptions = reliable firing; closest 1:1 mapping with current CLAUDE.md structure |
| Distribution | Setup copies all 8 SKILL.md from repo → `~/.claude/skills/ai-sherpa-<name>/SKILL.md` | Reuses existing repo-as-source-of-truth pattern; all domain skills available everywhere, descriptions filter firing |
| Plugin Invocation Contract location | Inside each domain skill body | Same lint coupling as today, file path swap only; broad skill firing keeps contract effectively always-on within domain |
| Rollout | One-shot (single change set) | User preference for speed; rollback is a clean revert; verification gated on smoke tests pre-merge |
| Scope of conversion | 8 active domains only: embedded, web, data, devops, ai, frontend, backend, uiux | Disabled domains (marketing/sales/finance/service/procurement) are unmaintained and not merged into anyone's `~/.claude/CLAUDE.md` anyway |
| Skill body content | Relocated verbatim from existing CLAUDE.md, no rule rewrites | Keeps diff small and reviewable; rule rewrites are a separate exercise |

## Architecture & Scope

**In scope (8 active domains):** `embedded`, `web`, `data`, `devops`, `ai`, `frontend`, `backend`, `uiux`.

**Out of scope (this iteration):**
- 5 disabled domains: `marketing`, `sales`, `finance`, `service`, `procurement` — their existing `CLAUDE.md` files stay untouched.
- `core/CLAUDE.md` content (except one informational pointer line added).
- Third-party skills installed via `plugins.json` `skills.<domain>[]` (zephyr-agent-skills, web-quality-skills, styleseed) — untouched.
- Domain plugins in `plugins.json` `domains.<name>[]` — install logic untouched.
- Hooks (`brainstorm-reminder.js` etc.) — untouched.
- Templates (`templates/project-CLAUDE.md`) — untouched.
- Rule rewrites or content changes — body is relocated verbatim.
- Migrating the global MANDATORY contract out of `core/CLAUDE.md` — would defeat always-on enforcement of brainstorming/TDD/code-review.

**The "pick a domain" prompt at setup survives** but its role narrows: it drives only domain plugin installation and embedded toolchain detection. It no longer determines what lands in `~/.claude/CLAUDE.md` or which skills are installed (all 8 are always installed).

## SKILL.md File Format

Each `domains/<active>/SKILL.md` is a Markdown file with YAML frontmatter followed by the existing CLAUDE.md body content.

### Frontmatter (mandatory fields)

```yaml
---
name: ai-sherpa-<domain>
description: <one sentence enumerating the domain + its frameworks/keywords broadly enough that any task in the domain triggers the skill>. Provides security guardrails, architecture/accessibility rules, and framework conventions for this domain.
---
```

### Description-writing rule

The description **must** enumerate the domain's framework and keyword vocabulary broadly enough that any task in the domain triggers the skill. This is the single most important property of each skill — guardrail firing reliability depends entirely on this field. Concrete examples to be used as starting points (final wording finalized during implementation):

- `ai-sherpa-web` → "Use when working on any task in a full-stack web project — React, Vue, Angular, Next.js, Node.js, Express, FastAPI, Django, Spring, .NET, HTML/CSS, Tailwind, shadcn, frontend, backend, API endpoint, component, accessibility, or UI work. Provides security guardrails, accessibility rules, and framework conventions."
- `ai-sherpa-embedded` → "Use when working on any embedded/firmware/RTOS task — C/C++, Zephyr, FreeRTOS, bare-metal, MCU, board bringup, devicetree, Kconfig, GPIO, sensors, BLE, CAN, flashing, JLink, OpenOCD, MISRA, or hardware bringup. Provides toolchain lookup, hardware constraints, and embedded-specific patterns."
- `ai-sherpa-data` → covers SQL/NoSQL/dbt/Spark/Airflow/pandas/ETL/data warehouse/data pipeline/data quality terms.
- `ai-sherpa-devops` → covers Kubernetes/Helm/Terraform/CI/CD/GitOps/observability/incident/SRE/cloud infra terms.
- `ai-sherpa-ai` → covers LLM/RAG/agent/embeddings/Claude API/MLOps/model training/prompt terms.
- `ai-sherpa-frontend` → covers a11y/Core Web Vitals/responsive/ARIA/WCAG/component library/design system terms (subset of web; coexists because some teams pick `frontend` rather than `web`).
- `ai-sherpa-backend` → covers backend service/API/database/auth/queue/microservice/REST/GraphQL/gRPC terms.
- `ai-sherpa-uiux` → covers UI design/UX/wireframe/Figma/prototype/usability/visual design terms.

### Body structure

Sections are unchanged from the existing CLAUDE.md files (Context Check, Always Do / Never Do, Domain specifics, AI Effectiveness Boundaries, MANDATORY + Self-described Plugin Invocation Contract tables). The H1 of the body stays the human-readable title (`# AI Sherpa — Web (Full-stack) Rules`).

A one-line reference at the top of each body: `These rules apply in addition to the global guidelines in core/CLAUDE.md.`

## Distribution Mechanism

### Setup script changes (both `setup.ps1` and `setup.sh`)

1. The function that writes `~/.claude/CLAUDE.md` (PowerShell: `Write-GlobalClaudeMd`, Bash: `copy_claude_md`) **stops concatenating** the domain CLAUDE.md. It writes only `core/CLAUDE.md` → `~/.claude/CLAUDE.md`.

2. A new function — `Install-AISherpaSkills` (PowerShell) / `install_ai_sherpa_skills` (Bash) — iterates over every directory under `domains/` that is **not** listed in `plugins.json` `disabled_domains` and that **has** a `SKILL.md` file. For each, copies `domains/<name>/SKILL.md` → `~/.claude/skills/ai-sherpa-<name>/SKILL.md`. Creates the target directory if missing. Idempotent: overwrites on re-run.

3. The "pick a domain" prompt at setup is unchanged in behavior — it still drives domain plugin installation (`plugins.json` `domains.<name>[]`) and embedded toolchain detection. It no longer determines what lands in `~/.claude/CLAUDE.md` or which skills are installed.

4. The existing third-party `install_skills` function (for `plugins.json` `skills.<domain>[]` entries) is untouched. The new `install_ai_sherpa_skills` runs alongside it.

5. The uninstaller (`Restore-OriginalConfig` and bash equivalent) gains a step to remove `~/.claude/skills/ai-sherpa-*/` directories.

### Update flow (`setup.ps1 update` and `bash setup.sh --update`)

Re-copies SKILL.md from the repo, overwriting any local edits in `~/.claude/skills/ai-sherpa-*/`. Same overwrite contract as today's CLAUDE.md.

### Repo layout

```
domains/
├── embedded/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── web/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── data/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── devops/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── ai/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── frontend/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── backend/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── uiux/
│   └── SKILL.md       ← new (replaces CLAUDE.md)
├── marketing/
│   └── CLAUDE.md      ← untouched (disabled domain)
├── sales/
│   └── CLAUDE.md      ← untouched (disabled domain)
├── finance/
│   └── CLAUDE.md      ← untouched (disabled domain)
├── service/
│   └── CLAUDE.md      ← untouched (disabled domain)
└── procurement/
    └── CLAUDE.md      ← untouched (disabled domain)
```

## Lint Script Changes (`scripts/lint-invocation-tables.js`)

**Current behavior:** The script iterates over `plugins.json.domains` keys (all 11 entries, including the 5 disabled ones) and `plugins.json.skills` keys, mapping each domain `<name>` to `domains/<name>/CLAUDE.md`. Files without a `## Plugin & Skill Invocation Contract` heading are skipped (Phase 1 permissive mode). The `backtickedTokenRegex` matches names like `` `plugin-name:` `` or `` `plugin-name` `` in the body. The `backend` and `uiux` domains are **not** keys in `plugins.json.domains`, so the script never opens those files — they remain unlinted regardless of CLAUDE.md vs SKILL.md.

**Changes:**

1. **Conditional file path.** Modify the `scopeFile(scope)` function so that for any domain in `config.disabled_domains`, it returns `domains/<name>/CLAUDE.md` (unchanged from today). For every other domain scope, it returns `domains/<name>/SKILL.md`. The `global` scope path stays `core/CLAUDE.md`. Pass the `disabled_domains` set into `scopeFile` (or close over it via a factory). Update the comment headers at the top of the script:

   ```
   plugins.json.domains.<name>[]    → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
   plugins.json.skills.<name>[]     → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
   ```

2. **Frontmatter check (new).** Before running the existing backtick-token check on a `SKILL.md` file, parse and validate the YAML frontmatter: must start with `---`, contain a `name:` field and a `description:` field, end with `---`. Fails the build with a clear error if a SKILL.md is malformed. Use a minimal regex extraction (no new dependency needed; ~15 lines). Skip the frontmatter check for `CLAUDE.md` files (disabled domains).

3. **No regex changes for the MANDATORY/Self-described table parse.** The existing `backtickedTokenRegex` operates on body content and isn't fooled by frontmatter (the `name:` field has no backticks). Validated by inspection during implementation; no behavior change expected for body matching.

4. **Phase 1 permissive mode preserved.** The "skip if no contract heading" behavior stays. Disabled-domain CLAUDE.md files don't have contract headings today — they keep getting skipped. The 6 active-and-in-plugins-json domains (embedded, web, data, devops, ai, frontend) have contract headings today; their SKILL.md files carry the same heading verbatim.

5. **CI hook unchanged.** `.github/workflows/lint-invocation.yml` keeps running `node scripts/lint-invocation-tables.js`. No workflow file changes.

6. **No transition tolerance.** Because the rollout is one-shot, the script does not need to accept either filename — it does a clean conditional swap based on the disabled list.

## Rollout (One-Shot)

A single change set covers everything:

1. Write 8 new `domains/<active>/SKILL.md` files (embedded, web, data, devops, ai, frontend, backend, uiux) — frontmatter + body relocated from CLAUDE.md.
2. Delete the corresponding 8 `domains/<active>/CLAUDE.md` files in the same change.
3. Update `setup.ps1` and `setup.sh`: stop concatenating domain CLAUDE.md into `~/.claude/CLAUDE.md`; add `install_ai_sherpa_skills` that copies all 8 skills; update the uninstaller to clean up `ai-sherpa-*` skill directories.
4. Update `scripts/lint-invocation-tables.js`: path swap CLAUDE.md → SKILL.md + frontmatter check.
5. Update `scripts/test-setup.sh`: new test for skill installation (all 8 land; disabled domains skipped; idempotent re-run); existing CLAUDE.md test shrinks to verify core-only.
6. Update `AGENTS.md` repo layout section to reflect new `domains/<name>/SKILL.md` files.
7. Update `core/CLAUDE.md` with one informational line in the Plugin & Skill Invocation Contract section: "Domain-specific contracts live in `ai-sherpa-<domain>` skills, which auto-activate on domain-matched tasks."

### Pre-merge validation

- `node scripts/lint-invocation-tables.js` passes against all 8 new SKILL.md files.
- `bash scripts/test-setup.sh` passes.
- Local smoke test on a clean `~/.claude/` checkout:
  - Run `setup.ps1` (or `bash setup.sh`).
  - Confirm all 8 `~/.claude/skills/ai-sherpa-*/SKILL.md` files land.
  - Confirm `~/.claude/CLAUDE.md` is core-only (no domain section appended).
- Spot-check skill firing in Claude Code: ask three sample tasks across different domains (e.g. "review this React component", "configure a Zephyr board", "design a Postgres schema") and confirm the matching `ai-sherpa-<domain>` skill activates.

### Rollback

If guardrail firing turns out unreliable post-merge, revert the single change. The old CLAUDE.md content is recoverable from git history.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Domain skill description is too narrow → skill doesn't fire on some tasks → guardrails silently skipped | Medium | Description-writing rule (Section "SKILL.md File Format") mandates broad enumeration of domain vocabulary. Spot-check firing on real tasks during pre-merge validation. If a domain under-fires, broaden its description in a follow-up PR. |
| Multiple domain skills fire on overlapping tasks (e.g. `web` + `frontend` + `backend` all match) | Medium | Acceptable. Skill bodies are not contradictory — they extend each other. The cost is some duplicate content in context for cross-domain tasks. Acceptable tradeoff for reliable firing. |
| `~/.claude/skills/ai-sherpa-*/` name collides with a third-party skill someone installs | Low | The `ai-sherpa-` prefix is namespaced; collision would be deliberate. Document the namespace reservation in `AGENTS.md`. |
| Setup script change breaks the existing `update` flow for users with custom edits in `~/.claude/CLAUDE.md` | Low | Setup already overwrites `~/.claude/CLAUDE.md` (it's not edit-friendly today). The `.bak` backup mechanism remains. No behavior regression. |
| Lint script frontmatter parse breaks on edge-case YAML (e.g. quoted strings with colons in description) | Low | Use a real YAML parser (`js-yaml` or the existing JSON-only approach extended). Add a unit test for one tricky description. |
| Team members on dev branches with old `~/.claude/CLAUDE.md` (still has domain content) don't update for weeks | Low | One Slack/email announcement at merge time. The merged-down `~/.claude/CLAUDE.md` is a no-op regression (loses some guidance) but doesn't break anything. |
| Disabled-domain content drift: someone re-enables `marketing` later but its CLAUDE.md was never migrated | Low | Re-enablement triggers a one-line migration PR for that domain. Out of scope for this iteration. |

## Files Changed

### New files (8)

- `domains/embedded/SKILL.md`
- `domains/web/SKILL.md`
- `domains/data/SKILL.md`
- `domains/devops/SKILL.md`
- `domains/ai/SKILL.md`
- `domains/frontend/SKILL.md`
- `domains/backend/SKILL.md`
- `domains/uiux/SKILL.md`

### Deleted files (8)

- `domains/embedded/CLAUDE.md`
- `domains/web/CLAUDE.md`
- `domains/data/CLAUDE.md`
- `domains/devops/CLAUDE.md`
- `domains/ai/CLAUDE.md`
- `domains/frontend/CLAUDE.md`
- `domains/backend/CLAUDE.md`
- `domains/uiux/CLAUDE.md`

### Modified files (6)

- `setup.ps1` — `Write-GlobalClaudeMd` drops domain concatenation; add `Install-AISherpaSkills`; uninstaller cleans up `ai-sherpa-*` skill dirs.
- `setup.sh` — `copy_claude_md` drops domain concatenation; add `install_ai_sherpa_skills`; uninstaller cleans up `ai-sherpa-*` skill dirs.
- `scripts/lint-invocation-tables.js` — file path swap + frontmatter check.
- `scripts/test-setup.sh` — new test for skill installation; existing CLAUDE.md test simplified.
- `AGENTS.md` — repo layout section reflects `SKILL.md` filenames for active domains; namespace reservation note.
- `core/CLAUDE.md` — one informational line in the Plugin & Skill Invocation Contract section pointing to `ai-sherpa-<domain>` skills.

## Verification

Smoke test on a clean machine (Windows or Linux/macOS):

```powershell
# Windows
.\setup.ps1
# Pick: 2 (Web), or any active domain — choice no longer affects skill installation

# Expected:
# - ~/.claude/CLAUDE.md contains ONLY core content (no "AI Sherpa — Web Rules" section)
# - ~/.claude/skills/ai-sherpa-embedded/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-web/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-data/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-devops/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-ai/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-frontend/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-backend/SKILL.md exists
# - ~/.claude/skills/ai-sherpa-uiux/SKILL.md exists
```

```bash
# Linux/macOS
bash setup.sh
# Same verification as above using ls ~/.claude/skills/
```

Inside Claude Code, ask domain-specific questions and confirm the matching skill activates:
- "Review this React component for accessibility issues" → `ai-sherpa-web` (and/or `ai-sherpa-frontend`) fires
- "Set up a custom Zephyr board" → `ai-sherpa-embedded` fires
- "Design a Postgres schema for a multi-tenant app" → `ai-sherpa-data` (and/or `ai-sherpa-backend`) fires

Run lint:

```bash
node scripts/lint-invocation-tables.js
# Expected: exit 0
```

Run setup tests:

```bash
bash scripts/test-setup.sh
# Expected: all tests pass, including new install_ai_sherpa_skills test
```

## Out of Scope

(Already enumerated in "Architecture & Scope" above; restated here for the spec scan.)

- Migrating the 5 disabled domains.
- Restructuring `core/CLAUDE.md`.
- Rewriting domain rules — content is relocated verbatim.
- Migrating the global MANDATORY contract out of `core/CLAUDE.md`.
- Converting third-party skill installations to a different mechanism.
- Adding new MANDATORY/Self-described rows to any contract table.
- Plugin install logic changes.
- Hook changes.
- Template (`templates/project-CLAUDE.md`) changes.
