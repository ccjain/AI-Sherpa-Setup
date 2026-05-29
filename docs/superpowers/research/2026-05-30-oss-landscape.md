# OSS landscape — Claude Code feedback / observability / rule-effectiveness (2026-05-30)

**Status:** Living reference. Supersedes the 2026-05-29 narrow comparison (`2026-05-29-oss-claude-session-tools-comparison.md`), which covered 2 tools. This doc consolidates four parallel investigations conducted 2026-05-29 → 2026-05-30 covering ~40 OSS projects across 4 categories.

**Purpose:** Be the build-vs-adopt reference for the AI Sherpa program. Every component in `2026-05-30-program-v2.md` traces back to a finding here.

**How to read this:** §1–6 are the surveyed landscape grouped by category. §7 is the consolidated adopt-vs-build matrix (the answer). §8 is the white-space finding that justifies the Scorer Registry. §9 lists open questions for the next research pass. §10 is the bibliography.

---

## 1. Why this doc exists

The previous OSS research (2026-05-29) covered only two projects (`sujankapadia/claude-code-analytics`, `lucemia/claude-session-analyzer`), which led the v1 program plan to conclude "we need to build our own" without surveying the broader ecosystem. The architect review surfaced this as the thinnest part of the v1 bundle. Four parallel investigations were dispatched on 2026-05-30 to fill the gap:

- **Investigation 1:** Direct competitors — Claude Code session analyzers and feedback loops
- **Investigation 2:** LLM observability platforms (Langfuse, Helicone, Phoenix, OpenLLMetry, LangSmith, Lunary, Literal AI)
- **Investigation 3:** Telemetry collection infrastructure (OpenTelemetry Collector, Vector, Grafana Alloy, Fluent Bit, Filebeat)
- **Investigation 4:** AI rules / prompt-engineering ecosystem (Cursor, Continue.dev, Aider, Codeium, Cline, OpenHands; DeepEval / Inspect AI / Promptfoo)

Combined surface: ~40 OSS projects + 6 emerging standards + 2 community efforts. The headline conclusion is at §7.

---

## 2. Method and limits

- Searches performed via web search + targeted GitHub fetches on 2026-05-29 → 2026-05-30.
- Every tool listed has been verified by fetching its repository or docs URL at investigation time. Tools that could not be verified were excluded.
- License + activity (commits, stars, recency) recorded for adoption-risk analysis.
- This is a snapshot. The space is moving fast — Langfuse moved to MIT in June 2025, Promtail EOL is March 2026, Helicone joined Mintlify March 2026, Traceloop was acquired by ServiceNow March 2026. Re-survey before any decision that would not have been made 3 months ago.
- We surveyed *capability*, not just *brand*. A platform with the right name but missing the needed feature is not a match.

---

## 3. Direct competitors — Claude Code session analyzers

The most-adopted projects in the niche (mid-2026):

| Project | License | Stars | Recency | Shape | Fit for AI Sherpa |
|---|---|---|---|---|---|
| `disler/claude-code-hooks-multi-agent-observability` | Unverified (READ ME silent) | 1.4k | Active | Laptop-agent → Bun/TypeScript server on :4000 → SQLite → Vue 3 dashboard via WebSocket | **Fork-and-extend.** Exact collector + transport + storage shape AI Sherpa wants. Hooks pre-wired incl. `PostToolUseFailure`. Pending license verification. |
| `chiphuyen/sniffly` | MIT | 1.2k | Low velocity | Local web app on 127.0.0.1:8081, parses Claude Code logs, error categorization | **Lift modules.** Error-classification logic only. Whole product is single-laptop, not fleet. |
| `simple10/agents-observe` | Unverified | 575 | Active | React + Node dashboard, hook→server→SQLite | Similar shape to #1 above; lower adoption |
| `ColeMurray/claude-code-otel` | MIT | 415 | Stable, no recent releases | OTel Collector → Prometheus + Loki + Grafana; consumes Claude Code's native OTel | **Adopt for cost/usage telemetry**, build separately for content analytics. OTel spans don't carry conversational text. |
| `doneyli/claude-code-langfuse-template` | MIT | 99 | Active | Stop-hook → self-hosted Langfuse (Postgres + ClickHouse + Redis + MinIO) | **Reference implementation.** Mature backend via Langfuse; lacks rule-effectiveness eval out of the box. |
| `sujankapadia/claude-code-analytics` | MIT | 8 | Alpha | Local SessionEnd + FTS5 + ChromaDB + dashboard | **Reference.** Whole-stack but at α maturity; OSS prior art for the indexing layer Phase 2a was going to build. |
| `lucemia/claude-session-analyzer` | MIT | 8 | 3 commits | Local Python; computes Read:Edit, self-admitted errors, repeated edits, frustration; replicates anthropic/claude-code#42796 methodology | **Lift modules.** ~70% of AI Sherpa's metric catalogue, already implemented. Treat as reference code, not dependency. |
| `ej31/claude-session-tracker` | Unverified | 42 | v2.9.4 | Auto-files every session as a GitHub Issue/Project | **Crib client code.** Direct prior art for auto-file step. |
| `accidentalrebel/claude-skill-session-retrospective` | MIT | Small | Active | Skill produces markdown retrospectives incl. "what went wrong" | **Crib prompt.** Reference for LLM-polish prompt design (if Phase 2 needs LLM scoring). |

**Anthropic-first-party**

- **Claude Code native OTel export** (`code.claude.com/docs/en/monitoring-usage`): tool calls, hooks, token cost, MCP connections, policy decisions, block events. GA in 2026. **Adopt as the laptop substrate.** Spans conform to the emerging OTel `gen_ai.*` semantic conventions.
- **Anthropic Admin API**: provides per-developer acceptance rate, sessions per day, cost, LOC accepted — *schema unconfirmed* and a Gate A spike target.
- **Anthropic Analytics Dashboard** (`code.claude.com/docs/en/analytics`): admin-level usage metrics; lacks rule-violation drill-down.

**What's notably absent across this category**

Zero projects ship a "did this CLAUDE.md rule fire?" detector. The problem is well-documented (blog.boucle.sh "Why Claude Code Ignores Your Rules"; anthropic/claude-code#42796; dev.to ajbuilds "Your CLAUDE.md is probably broken"); the gap is real. See §8.

---

## 4. LLM observability platforms

Surveyed as backend candidates for the storage + dashboards + alerting layer.

| Platform | License | State 2026 | Self-host on Windows? | Verdict |
|---|---|---|---|---|
| **Langfuse** | **MIT** (all product features, June 2025); EE retains thin compliance | Acquired by ClickHouse 2026; MIT core unchanged | Docker only; Windows via Docker Desktop / WSL2 | **Adopt as the backend.** Custom event ingestion via REST; webhooks fire on `score.created`; native sessions + tagging + custom dashboards |
| **Phoenix (Arize)** | **Elastic License 2.0** | Active; v16.3.0 May 2026 | Single container, Postgres backend, Docker on Windows works | **Backup.** ELv2 prevents productized resale; fine for internal AI Sherpa. Best-in-class data-retention (`PHOENIX_DEFAULT_RETENTION_POLICY_DAYS=7` native) |
| **OpenLLMetry (Traceloop)** | Apache 2.0 | ServiceNow-acquired March 2026; OSS continues | Spec + SDK, not a backend | **Adopt as emitter library** alongside whichever backend wins |
| **Helicone** | Apache 2.0 | Acquired by Mintlify March 2026; cloud in maintenance mode | Proxy-first architecture | **Not applicable** — proxy-first poor fit for ingesting post-hoc JSONL transcripts |
| **LangSmith** | Self-host EE-only, license-key gated | Active | K8s + 16+ vCPU + Postgres + Redis + ClickHouse; ~$2–5k/mo + infra | **Not applicable** — closed-source data plane, doesn't meet open-core requirement |
| **Lunary** | Apache 2.0 | Active | Lightest deploy (one Postgres, one container) | **Backup to Langfuse** — viable if Langfuse falls through, weaker custom-dashboard + webhook story |
| **Literal AI** | OSS, self-host "contact us" | Chainlit team stepped back May 2025 | Risk too high | **Not applicable** |
| **OpenObserve** | AGPLv3 | Active | Unified logs/metrics/traces | **Skip** — AGPL contagion risk if AI Sherpa is ever redistributed |

**Decision shape if Langfuse wins:**

- ~300-line emitter (JSONL → Langfuse `sessionId` / `trace` / `observation`)
- ~600-line evaluator service (poll trace API, compute Read:Edit, self-admitted, etc., write back as `scores`)
- ~100-line webhook → GitHub Issues bridge
- Custom dashboards built in-product
- Retention via ClickHouse `TTL traces.created_at + INTERVAL 7 DAY`
- **Total custom code: ~1,000 lines** vs ~4,000+ in the archived Phase 2a plan

**Blockers documented for the decision:**

- Phoenix's ELv2 prohibits productized hosting; safe for internal AI Sherpa, breaks if AI Sherpa is ever offered to outside parties
- Windows server requires Docker for every credible option
- Langfuse OSS does not include the *managed* 7-day retention policy — you implement TTL DDL
- OTel GenAI semantic conventions are still experimental in 2026; expect attribute renames

---

## 5. Telemetry collection infrastructure

Surveyed as candidates for the laptop-agent and server-gateway layers.

| Tool | Windows installer | File-watcher | Auth | Offline buffer | Verdict |
|---|---|---|---|---|---|
| **OpenTelemetry Collector contrib** | MSI; Chocolatey; silent install `msiexec /qn` | `filelogreceiver` with glob, multiline, rotation-aware | `bearertokenauth` + mTLS (`configtls`) | `file_storage` extension + `sending_queue.storage` (WAL) | **#1 pick** for laptop side. Go binary, ~50–150 MB RAM. |
| **Grafana Alloy** (Promtail's successor; Promtail EOL March 2026) | MSI; WinGet; silent install | `local.file_match` + `loki.source.file` (built on OTel filelogreceiver under the hood) | mTLS, bearer, basic, OAuth2 | Loki WAL or chain through `otelcol.exporter.*` | **#2 pick**, indistinguishable from #1 operationally. Slight edge if Grafana stack is already in use. |
| **Vector** (Datadog OSS) | MSI exists at `packages.timber.io`; Windows tier-2 | File source good; smaller plugin ecosystem | Standard | `disk_buffer` + end-to-end acks | **Skip** for Windows fleet — tier-2 means quirks. |
| **Fluent Bit** | EXE/NSIS installer; runs as Windows service | `tail` input + JSON parser + `exclude_path` | Weaker (no first-class mTLS) | Standard | **Skip** — historical Windows path-globbing quirks, weaker auth. |
| **Filebeat** (Elastic) | Workhorse; runs as Windows service | Mature `filestream` input | Standard | Standard | **Skip** — Elastic license drift; heavier footprint; we're not going to Elastic. |
| **Promtail** | — | — | — | — | **Do not pick** — EOL March 2026. |

**Server-side backend candidates:**

- **OTel Collector gateway + ClickHouse + HyperDX/Grafana** ("ClickStack" pattern): OTLP receiver in, ClickHouse exporter out, 5–10× compression vs row-stores. Single store for logs + traces + metrics. Native vector index (replaces ChromaDB) + full-text/BM25 (replaces SQLite FTS5). **This is the "kill the FastAPI + SQLite + ChromaDB triangle" path.**
- **Grafana LGTM** (Loki + Tempo + Mimir + Grafana): stronger if Grafana is already organizational standard; weaker for "rich aggregate analytics over session content" — Loki is label-indexed, slow for high-cardinality content queries.

**The gap (what's left to write if we adopt the OTel stack):**

- ~150–200 lines of OTTL/transform config mapping JSONL → `gen_ai.*` LogRecords
- ~30-line NDA exclude script (pre-discovery marker or OTTL condition)
- Per-machine opt-out (one config flag)
- Central config push via Intune/SCCM/Jamf or OpAMP supervisor
- Server-side vector embedding job (the only custom Python kept)

Total adopted-stack code under our maintenance: **~200 lines + config**. The archived Phase 2a plan committed to ~1,500 lines + bespoke Windows service + unauthenticated FastAPI.

---

## 6. AI rules / prompt-engineering ecosystem

Surveyed for "how do other AI-coding-tool communities measure rule effectiveness?"

| Project | License | What it measures | Lift-ability |
|---|---|---|---|
| **DeepEval** | Apache 2.0 | Prompt Alignment / Plan Adherence / Role Adherence — LLM-as-judge with per-instruction rubric extraction | **Strong fit.** Parse CLAUDE.md into N atomic instructions, score each one per session — directly portable to the Scorer Registry. |
| **Aider** | Apache 2.0 | Edit acceptance, model+command names, token counts, error events, retry/repair loops; opt-in PostHog client; never sends code/chat content | **Strong fit** as a *privacy/transport* template, not as an analytics product. `aider/analytics.py` ~200 lines is the skeleton. |
| **Inspect AI** (UK AISI) | MIT | Anything you can write a Scorer for; LLM-as-judge first-class; ReAct/agent bridges + tool spans built-in | **Strong fit** for the offline-eval side of the loop. "Rule-as-Scorer" is the cleanest available abstraction. |
| **Continue.dev `dev_data`** | Apache 2.0 (Continue itself) | Per-developer local event store designed to feed back into rule improvement; pivoted mid-2025 to async PR-agent rule enforcement | **Strong fit** for *community*. Same loop AI Sherpa is building — worth engaging the team upstream. |
| **Promptfoo** | MIT | Eval harness; lighter than DeepEval | **Reference.** No coding-rules WG specifically. |
| **Cursor** | Proprietary | Built-in accept-rate analytics | **Not applicable** — no OSS surface to lift from. |
| **Cline** | Apache 2.0 | Telemetry on tool-use; policy hooks | **Reference.** Hook-block frequency pattern is liftable. |
| **OpenHands** | MIT | Agent observability; SystemMessage tracking | **Reference.** Less directly applicable to single-CLI Claude Code. |
| **GitHub Copilot Workspace + Copilot Chat instructions** | Proprietary | Org-level custom-instructions GA April 2026 | **Not applicable** for lifting; useful for tracking what the Copilot crowd is converging on. |

**Emerging standards:**

- **OTel GenAI semantic conventions** (`gen_ai.*`): coalescing fast; still *experimental* in Q1 2026. https://opentelemetry.io/docs/specs/semconv/gen-ai/
- **OpenInference** (Arize): independently-developed; converging with OTel; instrumentations dual-emit.
- **OTel agent-spans + tool-spans + token attributes**: defined but no standard attribute for "instruction/rule identifier" or "rule outcome" yet. **This is the gap AI Sherpa could propose upstream** (e.g. `gen_ai.instruction.id`, `gen_ai.instruction.outcome`).

**Five detector patterns worth lifting from this ecosystem:**

1. **Per-instruction LLM-as-judge** (DeepEval Prompt Alignment): parse each CLAUDE.md rule into an atomic claim, score per session.
2. **Plan-vs-trace divergence** (DeepEval Plan Adherence): extract agent's declared plan at turn 1, diff against actual tool calls.
3. **Edit-revert / repair-loop counter** (Aider analytics): count user `Esc` / re-prompt / file-revert within N seconds of an edit. No judge needed.
4. **Hook-block frequency by rule** (Claude Code hooks + Cline policy hooks): when PreToolUse blocks, log which rule justified it. Inverse: if a "never do X" rule never blocks X, the rule may be internalized or ineffective — disambiguate with sampled judge.
5. **Grader-without-context Outcomes pattern** (Anthropic Agent SDK): nightly job spawns a fresh judge agent that sees only the final diff (not the trace) and scores against each rule. Removes "judge convinced by agent's reasoning" failure mode.

---

## 7. Consolidated adopt-vs-build matrix

This is the answer the four investigations converged on.

| Subsystem | Decision | Specific adoption | New code we own |
|---|---|---|---|
| Laptop session capture | **Adopt** | Anthropic native Claude Code OTel export + OTel Collector contrib MSI | 0 |
| NDA / consent filter | **Build** | OTTL condition in OTel config | ~30 lines |
| Transport (HTTP, mTLS, retry, offline buffer) | **Adopt** | OTel `file_storage` + `bearertokenauth` + `configtls` | 0 (config) |
| Server ingest + storage + index | **Adopt** | Langfuse OSS (MIT) → ClickHouse | 0 |
| Dashboards + alerts + webhooks | **Adopt** | Langfuse custom dashboards + `score.created` webhook | 0 |
| Generic metrics (Read:Edit, self-admitted, repeat-edit) | **Lift modules** | `lucemia/claude-session-analyzer` | ~200 lines vendored |
| Per-rule "did this fire?" Scorers | **Build** (white space — §8) | DeepEval Prompt Alignment as design pattern | ~800 lines |
| Eval framework | **Adopt** | DeepEval (Apache 2.0) or Inspect AI (MIT) | 0 |
| Auto-file Issues to GitHub | **Build thin handler** | Crib client from `ej31/claude-session-tracker` | ~100 lines |
| Release pipeline | **Adopt** | GitHub-native `.github/release.yml` + Releases Atom feed → Google Group feed-to-email | ~50 lines workflow |
| `/ai-sherpa-feedback` slash command + Issue form | **Build** | — | ~200 lines |

**Total adopted-stack code under AI Sherpa maintenance: ~1,200 lines.** The archived Phase 2a plan committed to ~12,700 lines.

---

## 8. The white space: rule-effectiveness detection

**No surveyed project ships "did this CLAUDE.md / Cursor / Continue.dev / Aider rule fire?" detection.** The problem is well-documented in the community:

- [blog.boucle.sh — "Why Claude Code Ignores Your Rules"](https://blog.boucle.sh/posts/why-claude-code-ignores-your-rules/) documents 0% vs 100% violation rates between hooks and CLAUDE.md.
- [anthropic/claude-code#42796](https://github.com/anthropics/claude-code/issues/42796) traces the canonical methodology for the metrics `lucemia/claude-session-analyzer` implements.
- [dev.to ajbuilds — "Your CLAUDE.md is probably broken — 5 silent failure patterns"](https://dev.to/ajbuilds/your-claudemd-is-probably-broken-5-silent-failure-patterns-and-how-to-fix-them-1abn) catalogues the failure modes AI Sherpa wants to detect.
- [thinkingthroughcode.medium.com — "The Silent Failure Mode in Claude Code Hooks"](https://thinkingthroughcode.medium.com/the-silent-failure-mode-in-claude-code-hook-every-dev-should-know-about-0466f139c19f) describes the same problem from the hook side.
- Academic prior art exists ([arXiv 2503.11336 "Rule-Guided Feedback"](https://arxiv.org/pdf/2503.11336); [arXiv 2603.08993 "Arbiter"](https://arxiv.org/pdf/2603.08993)) but as research benchmarks, not deployable tooling.

This means the AI Sherpa contribution is not "build a feedback program for our 150 devs." It is **"build the rule-effectiveness layer the AI-coding-tool ecosystem doesn't have yet, deploy it for our 150 devs first."** That's a more focused build and a more compelling charter — and if scoped right, the Scorer pattern could be proposed back to the OTel GenAI SIG and the Continue.dev `dev_data` community as a shared standard.

---

## 9. Open questions for the next research pass

The 2026-05-30 investigation deliberately stopped at adoption decisions and white-space identification. The following remain open and are worth a second pass during Gate A or Gate D:

1. **Anthropic Admin API actual schema** — the Gate A Spike 2 will answer; the investigation could not confirm without org-admin credentials.
2. **Cursor's `.cursorrules` analytics** — Cursor is proprietary; if they publish rule-effectiveness metrics for their own org rules, that's a forcing function for shared standards.
3. **Continue.dev `dev_data` schema for rule-outcome** — does their schema have a place for "rule fired / rule violated"? If yes, we may be able to consume their schema directly.
4. **`disler/claude-code-hooks-multi-agent-observability` license** — README is silent; confirm before adopting any code.
5. **Anthropic claude-code-sdk eval primitives** — the Agent SDK ships some observability primitives; do they include rule-outcome scoring that AI Sherpa would otherwise build?
6. **OTel GenAI SIG appetite for `gen_ai.instruction.*` semantic conventions** — would they accept an AI-Sherpa-authored proposal, or is the topic out of scope?

Add findings here as they land. This doc is intended as a living reference.

---

## 10. Bibliography

Sources verified during the 2026-05-30 investigations.

### Direct competitors (§3)
- https://github.com/disler/claude-code-hooks-multi-agent-observability
- https://github.com/lucemia/claude-session-analyzer
- https://github.com/ColeMurray/claude-code-otel
- https://github.com/chiphuyen/sniffly
- https://github.com/doneyli/claude-code-langfuse-template
- https://github.com/sujankapadia/claude-code-analytics
- https://github.com/ej31/claude-session-tracker
- https://github.com/accidentalrebel/claude-skill-session-retrospective
- https://github.com/kolkov/ccdiag
- https://github.com/simple10/agents-observe
- https://github.com/NirDiamant/claude-watch
- https://github.com/TechNickAI/claude_telemetry
- https://github.com/yahav10/claude-code-dashboard
- https://github.com/deshraj/Claud-ometer
- https://github.com/withLinda/claude-JSONL-browser
- https://code.claude.com/docs/en/monitoring-usage
- https://code.claude.com/docs/en/analytics
- https://code.claude.com/docs/en/agent-sdk/observability
- https://github.com/anthropics/claude-code/issues/42796
- https://github.com/anthropics/claude-code/issues/26255

### LLM observability platforms (§4)
- https://langfuse.com/self-hosting
- https://langfuse.com/self-hosting/license-key
- https://langfuse.com/docs/observability/data-model
- https://langfuse.com/docs/observability/features/sessions
- https://langfuse.com/docs/observability/features/tags
- https://langfuse.com/docs/metrics/features/custom-dashboards
- https://github.com/orgs/langfuse/discussions/1033
- https://dev.to/beton/langfuse-pricing-teardown-2026-2pi9
- https://github.com/Arize-ai/phoenix
- https://arize.com/docs/phoenix
- https://arize.com/docs/phoenix/settings/data-retention
- https://github.com/traceloop/openllmetry
- https://github.com/traceloop/openllmetry/releases
- https://www.helicone.ai/blog/joining-mintlify
- https://www.langchain.com/pricing
- https://lunary.ai/
- https://www.literalai.com/open-source
- https://openobserve.ai/blog/llm-observability-tools/
- https://futureagi.com/blog/best-self-hosted-llm-observability-2026

### Telemetry collection (§5)
- https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/filelogreceiver/README.md
- https://opentelemetry.io/docs/collector/install/binary/windows/
- https://community.chocolatey.org/packages/opentelemetry-collector-contrib
- https://oneuptime.com/blog/post/2026-02-06-deploy-opentelemetry-collector-windows-service/view
- https://opentelemetry.io/docs/collector/resiliency/
- https://github.com/open-telemetry/opentelemetry-collector/blob/main/exporter/exporterhelper/README.md
- https://github.com/open-telemetry/opentelemetry-collector/blob/main/config/configtls/README.md
- https://grafana.com/docs/alloy/latest/reference/components/local/local.file_match/
- https://grafana.com/docs/alloy/latest/monitor/monitor-logs-from-file/
- https://community.grafana.com/t/promtail-end-of-life-eol-march-2026-how-to-migrate-to-grafana-alloy-for-existing-loki-server-deployments/159636
- https://vector.dev/docs/setup/installation/package-managers/msi/
- https://vector.dev/docs/reference/configuration/sources/file/
- https://docs.fluentbit.io/manual/installation/windows
- https://docs.fluentbit.io/manual/data-pipeline/inputs/tail
- https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-filestream
- https://opentelemetry.io/docs/specs/semconv/gen-ai/
- https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-events/
- https://opentelemetry.io/blog/2026/genai-observability/
- https://clickhouse.com/docs/observability/integrating-opentelemetry
- https://clickhouse.com/resources/engineering/best-open-source-observability-solutions
- https://signoz.io/blog/loki-alternatives/

### AI rules ecosystem (§6)
- https://github.com/confident-ai/deepeval
- https://deepeval.com/docs/metrics-prompt-alignment
- https://deepeval.com/docs/metrics-plan-adherence
- https://deepeval.com/docs/metrics-role-adherence
- https://github.com/UKGovernmentBEIS/inspect_ai
- https://inspect.aisi.org.uk/
- https://hamel.dev/notes/llm/evals/inspect.html
- https://aider.chat/docs/more/analytics.html
- https://aider.chat/docs/usage/conventions.html
- https://deepwiki.com/Aider-AI/aider/12.1-usage-analytics
- https://docs.continue.dev/customize/telemetry
- https://docs.continue.dev/development-data
- https://docs.cline.bot/enterprise-solutions/monitoring/telemetry
- https://thepromptshelf.dev/blog/cline-vs-roo-code-rules-2026/
- https://jellyfish.co/library/cursor-usage-analytics/
- https://genai.qa/blog/promptfoo-vs-deepeval/
- https://arxiv.org/abs/2407.16741
- https://www.openhands.dev/blog/openhands-index
- https://generalanalysis.com/guides/claude-code-control-observability-opentelemetry
- https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk
- https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/
- https://futureagi.com/blog/what-is-openinference-2026
- https://github.blog/changelog/2026-04-02-copilot-organization-custom-instructions-are-generally-available/
- https://docs.github.com/en/copilot/tutorials/customize-code-review
- https://github.com/github/awesome-copilot/blob/main/docs/README.instructions.md
- https://docs.windsurf.com/windsurf/cascade/memories
- https://www.braintrust.dev/articles/agent-observability-complete-guide-2026

### White space (§8)
- https://blog.boucle.sh/posts/why-claude-code-ignores-your-rules/
- https://thinkingthroughcode.medium.com/the-silent-failure-mode-in-claude-code-hook-every-dev-should-know-about-0466f139c19f
- https://dev.to/ajbuilds/your-claudemd-is-probably-broken-5-silent-failure-patterns-and-how-to-fix-them-1abn
- https://arxiv.org/pdf/2503.11336
- https://arxiv.org/pdf/2603.08993
