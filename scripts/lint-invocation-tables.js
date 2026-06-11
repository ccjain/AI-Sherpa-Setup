#!/usr/bin/env node
// Verify every plugin/skill in plugins.json is acknowledged in the matching
// scope file.
//
// Scope routing:
//   plugins.json.global[]            → core/CLAUDE.md
//   plugins.json.skills.global[]     → core/CLAUDE.md
//   plugins.json.domains.<name>[]    → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
//   plugins.json.skills.<name>[]     → domains/<name>/SKILL.md   (or CLAUDE.md if disabled)
//
// Phase 1 permissive mode — two behaviors that BOTH go away in Phase 3:
//   (a) A SKILL.md that doesn't exist yet falls back to the sibling CLAUDE.md
//       (transition state while domains are being migrated to SKILL.md).
//   (b) A scope file without a "## Plugin & Skill Invocation Contract" heading
//       is SKIPPED, not flagged.
//
// SKILL.md files must additionally have valid YAML frontmatter with `name:`
// and `description:` fields. Missing or malformed frontmatter is a hard error.
//
// Exit 0 = clean; exit 1 = at least one missing entry or malformed frontmatter.

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CONTRACT_HEADING = '## Plugin & Skill Invocation Contract';

function loadConfig() {
  const raw = fs.readFileSync(path.join(ROOT, 'plugins.json'), 'utf8');
  return JSON.parse(raw);
}

function collectExpected(config) {
  const expected = { global: new Set() };
  for (const p of config.global || [])             expected.global.add(p.name);
  for (const s of (config.skills?.global) || [])   expected.global.add(s.repo);

  for (const [dom, plugins] of Object.entries(config.domains || {})) {
    expected[dom] = expected[dom] || new Set();
    for (const p of plugins) expected[dom].add(p.name);
  }
  for (const [dom, skills] of Object.entries(config.skills || {})) {
    if (dom === 'global') continue;
    expected[dom] = expected[dom] || new Set();
    for (const s of skills) expected[dom].add(s.repo);
  }
  return expected;
}

function scopeFile(scope, disabledSet) {
  if (scope === 'global') return path.join(ROOT, 'core/CLAUDE.md');
  const filename = disabledSet.has(scope) ? 'CLAUDE.md' : 'SKILL.md';
  return path.join(ROOT, 'domains', scope, filename);
}

function backtickedTokenRegex(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('`' + escaped + '(:|`)');
}

function validateFrontmatter(content, relPath) {
  if (!content.startsWith('---\n') && !content.startsWith('---\r\n')) {
    return `MALFORMED FRONTMATTER: ${relPath} does not start with '---' line`;
  }
  const endMatch = content.match(/\r?\n---\r?\n/);
  if (!endMatch) {
    return `MALFORMED FRONTMATTER: ${relPath} has no closing '---' line`;
  }
  const fmEnd = endMatch.index + endMatch[0].length;
  const fm = content.slice(0, fmEnd);
  if (!/^name:[ \t]*\S/m.test(fm)) {
    return `MALFORMED FRONTMATTER: ${relPath} missing 'name:' field`;
  }
  if (!/^description:[ \t]*\S/m.test(fm)) {
    return `MALFORMED FRONTMATTER: ${relPath} missing 'description:' field`;
  }
  return null;
}

function main() {
  const config = loadConfig();
  const expected = collectExpected(config);
  const disabledSet = new Set(config.disabled_domains || []);
  let failed = false;

  for (const [scope, names] of Object.entries(expected)) {
    let mdPath = scopeFile(scope, disabledSet);
    if (!fs.existsSync(mdPath)) {
      // Phase 1 permissive mode: if SKILL.md doesn't exist yet, fall back to
      // CLAUDE.md. Once all domains have been migrated (Phase 3), remove this
      // fallback and treat missing SKILL.md as a hard error.
      const fallback = path.join(ROOT, 'domains', scope, 'CLAUDE.md');
      if (scope !== 'global' && mdPath.endsWith('SKILL.md') && fs.existsSync(fallback)) {
        console.warn(`FALLBACK: ${path.relative(ROOT, mdPath)} not found — using CLAUDE.md`);
        mdPath = fallback;
      } else {
        console.error(`MISSING FILE: ${mdPath} (referenced by plugins.json scope "${scope}")`);
        failed = true;
        continue;
      }
    }
    const content = fs.readFileSync(mdPath, 'utf8');

    // Frontmatter check applies only to SKILL.md files.
    if (mdPath.endsWith(`${path.sep}SKILL.md`) || mdPath.endsWith('/SKILL.md')) {
      const err = validateFrontmatter(content, path.relative(ROOT, mdPath));
      if (err) {
        console.error(err);
        failed = true;
        continue;
      }
    }

    // Phase 1 permissive mode: skip if this file hasn't received an
    // Invocation Contract yet. Phase 3 removes this skip.
    if (!content.includes(CONTRACT_HEADING)) {
      console.log(`SKIP: ${path.relative(ROOT, mdPath)} has no "${CONTRACT_HEADING}" heading yet.`);
      continue;
    }

    for (const name of names) {
      const pattern = backtickedTokenRegex(name);
      if (!pattern.test(content)) {
        console.error(`MISSING: \`${name}\` not mentioned in ${path.relative(ROOT, mdPath)}`);
        failed = true;
      }
    }
  }

  process.exit(failed ? 1 : 0);
}

main();
