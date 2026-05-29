# `schemas/` — cross-phase contracts

This directory pins the contracts that multiple phases of the AI Sherpa feedback
program must agree on. **The contracts here exist so that Phase 1 (manual feedback)
and the future Gate E (auto-filer over the Scorer Registry) cannot drift from each
other.** See `docs/superpowers/2026-05-30-program-v2.md` §3.3 and §5.4 for the
program-level rationale.

## What lives here

| File | Purpose | Consumed by |
|---|---|---|
| `feedback_issue.schema.json` | Canonical shape of a structured feedback Issue body — same fields whether the source is the `/ai-sherpa-feedback` slash command or the Gate E auto-filer. Contains the `session_ref` triage-pivot contract. | `/ai-sherpa-feedback` skill (produces); triage tooling (consumes); Gate E auto-filer (produces); CI validation on `.github/ISSUE_TEMPLATE/` PRs (validates). |
| `release_manifest.schema.json` | Machine-readable description of what a release contains. | Weekly release Action (produces); Atom-feed → Google Group email (consumes); `setup --update --pin` (consumes for rollback decisions). |
| `label_taxonomy.yml` | Single source of truth for GitHub label namespaces (`source/*`, `domain/*`, `type/*`, `severity/*`, `confidence/*`, `status/*`). | `.github/labels.yml` (derived); Phase 1 Issue form defaults (derived); Gate E auto-filer (derived); CI cross-check (validates). |
| `helper_abi.md` | Calling convention for `submit-feedback.{ps1,sh}` so it can be invoked both interactively (by humans) and non-interactively (by Gate E). | `/ai-sherpa-feedback` skill (caller); Gate E auto-filer (caller); helper scripts (implement). |

## Versioning rules

- Every JSON schema includes a `schema_version` integer at the top of each
  instance. Increment **only** when adding a non-backward-compatible change.
- New optional fields = no version bump.
- New required fields, renamed fields, removed fields = version bump + a
  migration note in the schema's `$comment` field.
- `label_taxonomy.yml` carries a `version:` key at the top of the file with the
  same semantics.
- `helper_abi.md` is documented prose; changes are versioned in its own §History
  section.

## CI enforcement

A PR that changes any file in this directory must also:
1. Bump the schema's `schema_version` if the change is non-backward-compatible.
2. Update at least one fixture in `tests/schemas/fixtures/` that exercises the new
   shape.
3. Pass `tools/validate-schemas.{ps1,sh}` — to be added in Phase 1.

A PR that changes any of these files *without* matching consumer changes (issue
template, helper script, label-sync config) must explain why in the PR body.

## Why this directory is small

The contracts here are deliberately narrow. If a field can live entirely inside
one phase's implementation, it does not belong in `schemas/`. The bar for adding
a new contract is: *"do at least two independently-shippable components need to
agree on this?"* If no, keep the structure local.
