---
name: ai-sherpa-ai
description: Use when working on any AI / LLM application task — Claude API, OpenAI, Anthropic SDK, RAG, vector database, embeddings, agent orchestration, prompt engineering, evals, MLOps, model training, fine-tuning, LangChain. Provides AI-specific guardrails and effectiveness boundaries.
---

# AI Sherpa — AI / ML Engineering Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

## Context Check (Before Every AI Task)

Before writing or modifying code, confirm if not already documented:

1. Which model(s) is this code targeting? (Claude 4.6, 4.7; GPT-4o, GPT-5;
   open-weights via Ollama / vLLM; embedding model)
2. Provider / SDK in use? (Anthropic SDK, OpenAI SDK, LangChain, LlamaIndex,
   Vercel AI SDK, custom HTTP)
3. Is this an interactive app, batch pipeline, agent loop, or eval harness?
4. Is there a token / cost budget? Latency SLA?

Don't assume the model family from imports alone — the same `messages` API
shape exists across providers. Ask explicitly.

---

## Cost & Performance — Always Do

1. **Enable prompt caching** for any prompt with a stable prefix > 1024 tokens.
   Cache breakpoints belong before the user turn, not after. State the
   expected hit-rate when you add caching.
2. **State the model ID** in code or config — never let model selection drift
   to a default that may change upstream.
3. **Stream responses** for user-facing latency unless the call is part of an
   internal batch pipeline.
4. **Set token budgets** (`max_tokens`, `max_thinking_tokens`) explicitly.
   Defaults are usually wrong for the use case.
5. **Use the Batch API** for non-realtime jobs — 50% discount on Anthropic.

---

## Evaluation & Quality — Always Do

1. **Define the eval before writing the feature.** Even a 5-prompt smoke test
   is better than nothing. State the metric (accuracy / pass@1 / cost / p95
   latency).
2. **Pin the eval dataset.** Commit it to the repo or reference an immutable
   storage URL. "Tested on prod queries" doesn't reproduce.
3. **Re-run evals on every prompt or model change.** Treat prompts as code.
4. **Report eval deltas as part of the change**, not after the fact.
5. **Distinguish anecdotal demo wins from eval movement.** A demo that "feels
   better" but moves no metric is a regression in disguise.

---

## Safety & Reliability — Always Do

1. **Validate model outputs at every trust boundary** before passing to other
   systems (DB writes, shell exec, API calls, user UI). Tool-use responses
   are user-controlled until proven otherwise.
2. **Set timeouts on every API call.** Default infinite waits will hang
   production.
3. **Plan retry behavior** (exponential backoff, max attempts, jitter) for
   transient 5xx and rate-limit responses.
4. **Sanitize prompt-injectable content** (RAG docs, tool output, user input)
   before concatenating into system or user turns. State which injection
   surfaces exist.
5. **Log prompts and completions** (with PII handling per your policy) for
   debugging — but never log API keys.

---

## Never Do (AI)

1. **Never hardcode API keys or secrets.** Use env vars or a secrets manager.
   If you see a key in code, stop and flag it before continuing.
2. **Never ship a prompt change without running the eval.** "It worked in
   one test" is not evidence.
3. **Never trust a model's self-report of confidence** as a hard threshold
   without empirical calibration.
4. **Never autonomously execute destructive tool calls** (file deletion,
   `git push --force`, `rm -rf`, prod DB writes) without an explicit human
   approval step or dry-run.
5. **Never use deprecated model IDs in new code.** Default to the latest
   supported model per the Anthropic docs.

---

## AI Effectiveness Boundaries

**Effective:** prompt drafting, eval set generation, agent-loop scaffolding,
RAG retrieval logic, SDK boilerplate, schema design for tool use, refactoring
prompt files, generating few-shot examples.

**Not suitable as final authority:** decisions about model selection at scale
(test instead), latency budgets under real load (benchmark instead), fairness
or harm evaluation (use human review + dedicated red-teaming), legal
compliance (HIPAA, GDPR, etc.) of data handling (escalate to legal).

---

## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin includes skills for
Python, TypeScript, prompt engineering, RAG architecture, and fine-tuning
that auto-activate when working in those contexts. The `claude-api` skill
(also global via superpowers) activates when modifying Anthropic SDK code.

If you need a specific skill that isn't activating, mention the topic
explicitly in your prompt (e.g., "using Anthropic prompt caching, …").
