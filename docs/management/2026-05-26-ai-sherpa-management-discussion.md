# AI Sherpa — Management Discussion: Risks & Critical Decisions
**Version:** 0.1
**Date:** 2026-05-26
**Audience:** Management / Decision Makers
**Purpose:** Surface critical risks, unresolved decisions, and strategic choices BEFORE development begins

---

## Why This Document Exists

Enterprise AI tooling initiatives fail regularly — not because the technology doesn't work, but because hard questions were answered optimistically in planning and painfully in production. This document captures those questions upfront so management can make informed decisions before the company commits resources.

---

## Risk 1: Developer Adoption — The Highest Risk

### The Problem
Mandating a tool from the top down without developer involvement creates quiet non-compliance. Developers will "use it" on paper while avoiding it in practice — especially senior engineers who already have established workflows. Junior developers may over-trust AI output and stop developing their own judgment.

### What Could Go Wrong
- Teams claim to use AI Sherpa but don't actually run it on real work
- AI-generated code gets committed without review because "the tool said it was fine"
- Resentment toward management for imposing a tool that slows down experienced developers

### Decision Required from Management
1. **How will adoption be measured?** (Git hook logs? PR comments? Self-reporting?)
2. **Will there be an onboarding period** where teams can experiment before compliance is required?
3. **Is there a feedback channel for developers** to push back on rules they find obstructive?

### Recommendation
Mandate the tool, but also run 2-week onboarding sessions per team with a designated AI champion. Make it easy to comply — the setup must take under 10 minutes or developers will skip it.

---

## Risk 2: Embedded Software — AI Confidence vs. AI Accuracy

### The Problem
AI coding tools are most effective on web and backend code. For embedded software (C/C++, RTOS, firmware), AI can be **confidently wrong** — suggesting code that compiles and looks correct but has subtle real-time or hardware-specific bugs that only appear on physical hardware.

### What Could Go Wrong
- An AI-suggested fix for an interrupt handler introduces a timing bug that passes code review and only surfaces in a specific hardware configuration at production volume
- Developers trust AI review for safety-critical modules because "it reviewed the code"
- A MISRA-C violation is introduced by AI and not caught because reviewers assume AI checked for it

### Decision Required from Management
1. **Are any embedded modules safety-critical or subject to regulatory standards (ISO 26262, IEC 61508)?** If yes, AI-assisted review cannot replace formal verification.
2. **Should embedded teams have a stricter policy** — e.g., AI for review only, no AI-generated code in hardware-critical paths?
3. **Who is accountable** when an AI-assisted embedded change causes a hardware incident?

### Recommendation
Define a clear boundary: AI is a tool for embedded review, debugging, and test writing. It is explicitly NOT a substitute for hardware-in-the-loop testing or formal safety analysis. Write this into the CLAUDE.md and user guide explicitly.

---

## Risk 3: The Feedback Loop Will Silently Die

### The Problem
The feedback mechanism — where developers flag bad AI decisions and admin reviews them — is the self-improvement engine of the whole system. Without it, AI Sherpa v1 is also AI Sherpa v10. The same mistakes repeat. But feedback loops have a well-known failure pattern: they get created, used for 2-3 weeks, then abandoned as teams get busy.

### What Could Go Wrong
- Admin team receives 50 feedback items in week 1, falls behind, stops processing
- Developers submit feedback, see no action taken, stop submitting
- High-quality feedback from embedded team sits unreviewed for months
- A known bad AI pattern keeps occurring across teams because the fix was never propagated

### Decision Required from Management
1. **Who specifically owns the admin review role?** (A named person, not "the team")
2. **What is the SLA for feedback review?** (e.g., critical: 48 hours, high: 1 week)
3. **What is the review cadence?** (Weekly meeting? Async process?)
4. **How many feedback items per week can the admin realistically handle?**

### Recommendation
Start with a realistic volume target. If the admin team can only handle 10 feedback items per week, design the feedback form to filter noise aggressively. A feedback loop that processes 10 high-quality items is more valuable than one that receives 100 and processes 2.

---

## Risk 4: False Sense of Security from Guardrails

### The Problem
CLAUDE.md rules and skills like `/careful` and `/guard` are probabilistic — they work most of the time but are not enforced like code. Claude is a language model, not a rule engine. If developers believe guardrails are hard enforcement, they will reduce their own oversight, creating a gap where neither the AI nor the human is checking carefully.

### What Could Go Wrong
- Developer approves AI-suggested PR without reading it because "AI Sherpa reviewed it"
- A destructive command runs because the guardrail phrase wasn't triggered in that specific context
- Sensitive credentials are committed because the AI's pattern detection missed an unusual format

### Decision Required from Management
1. **Is human review of AI-generated code always required,** or can teams define their own threshold?
2. **Will there be periodic audits** of AI-assisted PRs to check if quality standards are being met?

### Recommendation
Communicate clearly in the user guide: **guardrails reduce risk, they do not eliminate it.** Human review of AI output is always required. Consider adding a required checklist to PR templates for AI-assisted changes.

---

## Risk 5: Cost Management — No Cap = Surprise Bills

### The Problem
Multiple teams running Claude Code across large projects generates API costs that are difficult to predict. One team doing a large refactor or running graphify on a 500k-line codebase can generate significant token usage in a single session. Without monitoring and caps, costs can exceed budget before anyone notices.

### What Could Go Wrong
- A team runs graphify indexing on a large monorepo daily — costs multiply by team count
- No cost attribution per team, so nobody is accountable for overuse
- End of quarter surprise: AI API costs 3x over budget

### Decision Required from Management
1. **What is the monthly budget for Claude API usage?**
2. **Is there a per-team allocation?** How is overuse handled?
3. **Who monitors costs?** (IT? Finance? The admin team?)
4. **Will Anthropic's enterprise billing/controls be used** to set hard limits?

### Recommendation
Set a baseline cost estimate before rollout: run a pilot with 2-3 teams for 4 weeks and measure actual API consumption. Use that data to set realistic per-team budgets before company-wide rollout.

---

## Risk 6: Data Privacy and IP Leakage

### The Problem
Claude Code sends code to Anthropic's API for processing. This means your proprietary codebase — business logic, algorithms, architecture — passes through Anthropic's infrastructure. For most companies this is acceptable, but it requires an explicit decision, not an assumption.

### What Could Go Wrong
- A developer uses AI Sherpa on code that is subject to a customer NDA
- Embedded firmware containing proprietary hardware interfaces is indexed by graphify and sent to the API
- A compliance audit flags AI tool usage as a data handling risk

### Decision Required from Management
1. **Has legal reviewed Anthropic's data handling and privacy terms?**
2. **Are any codebases subject to NDAs, export controls, or regulatory restrictions** that would prohibit sending code to a third-party API?
3. **Is Anthropic's zero-data-retention option enabled** on your API account? (Enterprise accounts can request this)
4. **Should certain projects be explicitly excluded** from AI Sherpa usage?

### Recommendation
Get legal sign-off before company-wide rollout. Identify any restricted codebases upfront and add them to an explicit exclusion list in the AI Sherpa policy document.

---

## Risk 7: Building on gstack — External Dependency Risk

### The Problem
gstack (the reference project from Garry Tan) is a personal GitHub repo, not a supported enterprise product. It is MIT licensed and free, but it is maintained at one person's discretion. Claude Code updates regularly — gstack has broken on past Claude Code version upgrades.

### What Could Go Wrong
- gstack stops being maintained or changes direction
- A Claude Code update breaks gstack skills and teams can't work until it's fixed
- The company builds internal workflows on top of gstack patterns, then has to re-architect when gstack diverges

### Decision Required from Management
1. **Should gstack be used as reference only** (take ideas, don't take dependencies), or as an active dependency?
2. **Who is responsible for maintaining AI Sherpa** when upstream tools change?

### Recommendation
Treat gstack as **inspiration, not infrastructure**. Take the workflow concepts and skill patterns. Write your own implementations. This adds 2-3 weeks of initial development time but eliminates the ongoing dependency risk.

---

## Risk 8: Developer Skill Atrophy

### The Problem
When AI handles debugging, code review, and architecture planning, developers may gradually lose the ability to do these things without AI assistance. This is a slow, invisible risk — no single incident triggers an alarm, but capability quietly erodes over 12-18 months.

### What Could Go Wrong
- A senior developer who has relied on AI review for 18 months cannot conduct a thorough manual code review when AI is unavailable
- Junior developers never fully develop debugging skills because AI diagnoses issues for them
- An embedded engineer becomes dependent on AI for code that AI is weak at — embedded-specific bugs go undetected because human skill has atrophied

### Decision Required from Management
1. **Is there a policy on AI usage for junior developers?** (e.g., use AI to learn, not to bypass learning)
2. **Will engineering managers actively monitor** whether engineers are developing skills or just accepting AI output?

### Recommendation
Establish explicit "AI-free zones" for skill development — certain types of problems that junior developers must solve without AI assistance as part of their growth track. This is especially important for embedded teams.

---

## Summary: Decisions Management Needs to Make Before Launch

| # | Decision | Urgency | Risk if Deferred |
|---|---|---|---|
| 1 | How will adoption be measured and enforced? | High | Invisible non-compliance |
| 2 | What are the AI boundaries for safety-critical embedded code? | High | Hardware incident liability |
| 3 | Who owns the feedback loop? What is their SLA? | High | System stops improving |
| 4 | Is human review always mandatory for AI-generated code? | High | Quality gaps |
| 5 | What is the monthly API budget and per-team cap? | Medium | Surprise cost overruns |
| 6 | Has legal reviewed Anthropic's data handling terms? | Medium | Compliance exposure |
| 7 | Which codebases (if any) are excluded from AI Sherpa? | Medium | IP / NDA violations |
| 8 | Gstack: reference only or active dependency? | Medium | Maintenance burden |
| 9 | Is there a developer skill development policy alongside AI usage? | Low | Long-term capability erosion |

---

## Recommended Next Steps

1. **Schedule a 60-minute management review** of this document — get answers to the High urgency decisions before development starts
2. **Legal review** of Anthropic's enterprise terms — 1 week task
3. **Run a 2-team pilot** for 4 weeks before company-wide rollout — gather real cost and adoption data
4. **Name the admin team owner** — a specific person, not a committee
5. **Define embedded AI policy** with input from the embedded engineering lead
