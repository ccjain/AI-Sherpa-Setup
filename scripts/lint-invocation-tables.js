#!/usr/bin/env node
// Verify every plugin/skill in plugins.json is acknowledged in the matching
// CLAUDE.md scope file.
//
// Scope routing:
//   plugins.json.global[]            → core/CLAUDE.md
//   plugins.json.skills.global[]     → core/CLAUDE.md
//   plugins.json.domains.<name>[]    → domains/<name>/CLAUDE.md
//   plugins.json.skills.<name>[]     → domains/<name>/CLAUDE.md
//
// Phase 1 permissive mode: a domain CLAUDE.md without a
// "## Plugin & Skill Invocation Contract" heading is SKIPPED, not flagged.
// Phase 3 (bulk rollout) will remove this skip behavior once every domain
// has a contract.
//
// Exit 0 = clean; exit 1 = at least one missing entry.

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

function scopeFile(scope) {
  return scope === 'global'
    ? path.join(ROOT, 'core/CLAUDE.md')
    : path.join(ROOT, 'domains', scope, 'CLAUDE.md');
}

function backtickedTokenRegex(name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('`' + escaped + '(:|`)');
}

function main() {
  const config = loadConfig();
  const expected = collectExpected(config);
  let failed = false;

  for (const [scope, names] of Object.entries(expected)) {
    const mdPath = scopeFile(scope);
    if (!fs.existsSync(mdPath)) {
      console.error(`MISSING FILE: ${mdPath} (referenced by plugins.json scope "${scope}")`);
      failed = true;
      continue;
    }
    const content = fs.readFileSync(mdPath, 'utf8');

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
