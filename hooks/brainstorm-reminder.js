#!/usr/bin/env node
/*
 * UserPromptSubmit hook: nudges Claude toward superpowers:brainstorming
 * when the user's prompt looks like a feature/build/implement request.
 *
 * Behavior:
 *  - Reads {prompt, ...} JSON from stdin (Claude Code hook payload).
 *  - Emits {hookSpecificOutput: {hookEventName, additionalContext}} only
 *    when the prompt matches a build-intent pattern AND is not clearly
 *    read-only / debug / trivial.
 *  - Silent (exit 0, no output) for non-matches — zero context overhead.
 *
 * Soft enforcement: this injects a reminder; it does not block tools.
 * Per AI Sherpa setup, see core/CLAUDE.md for the MANDATORY skill table.
 */

// Optional polite preamble before the real verb: "please", "can you", "could
// you", "I want to", "I'd like to", "let's", "we should", etc.
const PREAMBLE = '(?:please\\s+|can\\s+you\\s+|could\\s+you\\s+|would\\s+you\\s+|i(?:\\s+|\')?(?:want|need|would\\s+like)\\s+(?:to|you\\s+to)\\s+|i\'?d\\s+like\\s+(?:to|you\\s+to)\\s+|let\'?s\\s+|we\\s+should\\s+|we\\s+need\\s+to\\s+|help\\s+me\\s+|now\\s+|next,?\\s+|then\\s+|also\\s+|first,?\\s+|lets\\s+|first\\s+thing,?\\s+)*';
const BUILD_VERB = '(?:build|add|implement|create|make|develop|design|scaffold|wire(?:\\s+up)?|integrate|introduce|refactor|rewrite|migrate|port|set\\s+up|stand\\s+up|spin\\s+up|bootstrap|generate|write\\s+(?:a|an|the|some))';

// Build intent = build-verb at start of prompt (after optional preamble),
// OR explicit "new <thing>" / "modify behavior" phrasing anywhere.
const BUILD_INTENT_START = new RegExp('^\\s*' + PREAMBLE + BUILD_VERB + '\\b', 'i');
const NEW_FEATURE = /\b(new\s+(feature|component|module|page|screen|endpoint|api|service|tool|plugin|skill|hook|integration|workflow|script|capability)|modify\s+(behavior|behaviour|feature))\b/i;

// Skip patterns: read-only questions, debugging, trivial edits.
const READ_ONLY = new RegExp('^\\s*' + PREAMBLE + '(?:what|why|where|when|who|which|how(?:\\s+do(?:es)?)?|explain|describe|summari[sz]e|show(?:\\s+me)?|list|find|search|look\\s+up|read|tell\\s+me|does\\s+|do\\s+(?:we|you|i)\\s+|is\\s+(?:there|this|that)\\s+|are\\s+(?:there|these|those)\\s+)\\b', 'i');
const DEBUG_FIX = /\b(debug|diagnose|investigate|trace|reproduce|repro|why\s+is|why\s+does|why\s+isn'?t|fix\s+(a\s+)?(bug|typo|test|error|crash|warning|lint)|typo|crash|stack\s*trace|error\s+message)\b/i;
const TRIVIAL = /\b(rename|reword|tweak\s+wording|update\s+(comment|docstring|readme)|change\s+(label|text|copy)|bump\s+version|update\s+dependency)\b/i;

const REMINDER = [
    'AI Sherpa: this prompt looks like a feature/build/implement request.',
    'You MUST invoke the superpowers:brainstorming skill via the Skill tool',
    'BEFORE proposing approaches or writing implementation code.',
    '',
    'Brainstorming is a HARD GATE:',
    '  1. Explore project context (files, docs, recent commits)',
    '  2. Ask clarifying questions one at a time',
    '  3. Propose 2-3 approaches with trade-offs',
    '  4. Get explicit user approval on the design',
    '  5. Write design doc to docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md',
    '  6. Transition to writing-plans skill',
    '',
    'Skip ONLY if this is genuinely a debug/typo/read-only/trivial-edit ask.'
].join('\n');

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { raw += chunk; });
process.stdin.on('end', () => {
    let payload;
    try {
        payload = JSON.parse(raw || '{}');
    } catch {
        process.exit(0);
    }

    const prompt = String(payload.prompt || '').trim();
    if (!prompt) process.exit(0);

    const looksLikeBuild =
        BUILD_INTENT_START.test(prompt) ||
        NEW_FEATURE.test(prompt);

    const looksLikeOther =
        READ_ONLY.test(prompt) ||
        DEBUG_FIX.test(prompt) ||
        TRIVIAL.test(prompt);

    if (!looksLikeBuild || looksLikeOther) process.exit(0);

    process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
            hookEventName: 'UserPromptSubmit',
            additionalContext: REMINDER
        }
    }));
});
