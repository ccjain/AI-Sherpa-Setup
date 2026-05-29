# Feedback on `2026-05-30-program-v2.md`

**Date:** 2026-05-30
**Status:** Engineering review of the v2 program brief
**Purpose:** Honest engineering judgment on whether v2 is ready to move to Gate A, what's strong, what I'd refine, what's still missing.

---

## 1. Top-line verdict

**Adopt the v2 with the refinements in §3 of this doc.** I'd move to Gate A.

The v2 is a substantially better program brief than the v1 bundle. It directly addresses the architect review's central critique — "you're rebuilding infrastructure that exists" — by adopting Langfuse + OTel Collector + GitHub-native release tooling for ~80% of the planned plumbing, and concentrating the build investment on **the one genuine white space (per-rule effectiveness measurement)** that nobody in the AI-coding-tool ecosystem currently fills.

Critical numbers to compare:

| Dimension | v1 bundle | v2 brief |
|---|---|---|
| Total new code under our maintenance | ~12,700 lines of plan | ~1,200 lines |
| Phase structure | 4 phases, all proceed regardless | 5 gates, each with kill criteria |
| Schema contracts pinned before build | No | Day 1 (Gate B exit) |
| Falsifiable kill criteria | None | Every gate |
| Operational artifacts (rollback, on-call, runbooks) | Mostly absent | Required exits at every gate |
| "Intranet only" treated as security control | Yes (defect) | No (mTLS + bearer mandated at Gate E) |
| Architect review concerns addressed (of 26 we accepted fully) | — | ~22 of 26 directly addressed; remainder noted below |

The v2 also makes one architectural contribution that the v1 bundle never articulated: **the Scorer Registry as the per-rule effectiveness measurement layer**. The v1 plan called these "detectors" and bundled them with infrastructure; v2 cleanly separates the white space (Scorer Registry, ~800 lines) from the adopted commodity layers. That separation is what makes the build narrow enough to be defensible.

---

## 2. What's genuinely strong (with specifics)

### 2.1 The gate-not-phase reframing

v1 had Phase 0.5 → 1 → 1.5 → 2a → 2b with each phase's deliverables predetermined. Reality intrudes, you proceed anyway. v2 has Gate A (spike) → B (Phase 1) → C (stabilize) → D (Phase 2 scope) → E (Phase 2 build), each with **explicit exit criteria** AND **explicit kill criteria**.

Example: Gate C's kill criterion ("if backlog age > 5 days for 2 consecutive weeks, Phase 2 deferred until they hold") is the single change that prevents the firehose-into-clogged-sink scenario the architect review flagged as risk #10. The v1 plan would have shipped Phase 2 on a fixed timeline regardless.

### 2.2 The adopt-vs-build matrix (§3 table)

The matrix is concrete and falsifiable. Each row names: the layer, the decision, the source, and the cost we accept. This is the document the architect review was implicitly asking for. Specifically:

- **Laptop session capture → OTel Collector contrib MSI + Anthropic native OTel.** Correct adoption. Anthropic publishes Claude Code OTel exporter docs at `code.claude.com/docs/en/monitoring-usage`. The MSI is real and deployable via Intune/SCCM.
- **Transport (mTLS + bearer + offline buffer) → OTel Collector built-in.** Replaces the v1 plan's hand-rolled HTTP POST with no auth. Single largest security improvement.
- **Server ingest + storage + index → Langfuse OSS.** Replaces FastAPI + SQLite FTS5 + ChromaDB tier. ClickHouse + Langfuse is a real OSS combination; MIT-licensed; the architect review explicitly cited this kind of substitution.
- **Release pipeline → GitHub-native `.github/release.yml`.** Replaces Apps Script + bash + jq + pandoc + custom mailer. Real native feature; works.
- **Per-rule effectiveness → Build (Scorer Registry).** This is the kept-build, and it's the right one.

### 2.3 Hard separation between spike outputs and Phase 1 deliverables

§2's hard rule: *"nothing in §5 (committed deliverables) depends on the outcome of these spikes."*

This is the right discipline. v1 had three detectors that load-beared on an unconfirmed Admin API schema. v2 says: Phase 1 ships independently; Phase 2 *scope* depends on spike outputs but Phase 1 *does not*.

### 2.4 The "what we explicitly are NOT going to do" list (§9)

Naming the rejected items is as important as naming the deliverables. The list is sharp:

- "Build a FastAPI ingest service" — and then naming why: OTel Collector is the ingest.
- "Build a SQLite FTS5 index or ChromaDB embedding tier" — ClickHouse covers both.
- "Build a Google Apps Script mailer with a shared secret" — Atom feed covers it.
- "Treat 'intranet only' as a security control" — direct correction of v1's most-cited defect.

The list functions as a scope-creep tripwire: when someone proposes adding a piece during implementation, the question is "is this on the not-doing list?"

### 2.5 Operational use cases UC5–UC8

The v1 requirements summary missed every operational scenario. v2 adds:

- **UC5 yank a bad release** — `setup --update --pin=v2026.05.31` + `gh release delete` + postmortem.
- **UC6 consent revocation** — one config flag stops uploads; `ai-sherpa wipe-me` triggers server-side delete.
- **UC7 right-to-access** — `ai-sherpa what-do-you-have-on-me` returns JSON snapshot.
- **UC8 server outage** — laptop OTel Collectors buffer via `file_storage` extension; resume on reconnect.

These are stakeholder-facing operational guarantees that the v1 program would have hand-waved through. UC7 specifically is what makes the difference between "platform team builds infrastructure" and "platform team builds infrastructure that respects developer agency."

### 2.6 Length discipline as a feature

The 500-line cap (hard 700 ceiling) is a structural constraint that prevents the previous failure mode where specs slipped into implementation detail. Future scope additions must be argued back to fit, not just appended. This is closer to how durable architecture docs work.

### 2.7 The Scorer Registry framing

This is the conceptual contribution that I think will hold up the longest. Per-rule "did this fire?" measurement is:

- **Genuinely white space.** Continue.dev's `dev_data` initiative tracks usage events but not rule effectiveness. Langfuse evals score prompts/completions but don't track CLAUDE.md rule firing. Anthropic's OTel export covers tools/hooks but not rule applicability.
- **Implementable in ~800 lines.** A Scorer takes (session, rule) → bool/float. The registry is `{rule_id: scorer_fn}`. Webhook handler iterates over the registry per session.
- **Publishable upstream.** §7 acknowledges this: "We publish our Scorer-registry pattern as a proposal post-Gate E." That's the kind of contribution that earns long-term mindshare in the OTel GenAI SIG and Continue.dev dev_data community.

---

## 3. What I'd refine or push back on (with specifics)

These are the items I'd want addressed inside Gate A's scope or as small additions to v2 before Gate B begins. None of them are blockers; all are pinnable in a few hours.

### 3.1 Langfuse fit for Claude Code session shape — needs explicit spike

§2 spikes 1 and 2 cover content coverage and Admin API schema. They do not explicitly cover whether **Langfuse's trace model maps cleanly to Claude Code session data.**

Langfuse is designed for LLM application observability (prompts → LLM → completions, with nested generations and tool calls). Claude Code emits tool_use, tool_result, file_edit, and skill_invoked events whose shape may or may not map naturally to Langfuse's `Trace` / `Span` / `Generation` / `Score` concepts.

**Recommendation:** add a Spike 4 to §2: "Map a real Claude Code session into Langfuse's trace model end-to-end. Does the result look like a Langfuse trace, or are we shoe-horning?" 1 day. If the answer is "we're shoe-horning," the implication is that Langfuse covers ingest + storage + retention but the *application* layer (dashboards, queries, alerts) may not be reusable as-is. Worth knowing before Gate E commits.

### 3.2 OTel content coverage spike is the load-bearing one

§2 Spike 1 ("does the native OTel export carry enough content for content-level detectors") is correctly identified as the highest-leverage unknown. But the brief understates the failure mode.

If Spike 1 says "OTel coverage is metric-level only; transcript content is not in spans," then:

- The Scorer Registry needs transcript content to compute Read:Edit ratio, repeat-edit, self-admitted errors.
- The brief says "we need JSONL ingest pipe in parallel with OTel" — but that brings back the FastAPI + storage that v2 explicitly rejects in §9.

**Recommendation:** in Spike 1's exit criteria, state explicitly: *"if content-level detection is not feasible via OTel alone, what is the fallback architecture and at what scope cost?"* Don't leave the fallback as a TODO that resurfaces in Gate D.

### 3.3 GitHub Projects v2 column rules in YAML — mechanism not pinned

§5.2 commits to:

> *"GitHub Projects board with column rules versioned in `.github/projects/feedback-board.yml` (NOT the GitHub UI, which is unversioned)"*

GitHub Projects v2 has an API (`gh project field-create`, `gh project item-add`, etc.) but **does not natively read board configuration from a YAML file in the repo.** A custom Action would have to parse the YAML and call the API.

**Recommendation:** name the mechanism explicitly — either *"a one-shot Action that reads `.github/projects/feedback-board.yml` and applies it via the Projects v2 API"* (and budget the ~100 lines for it), or *"document the board structure in repo; accept that the UI is the source of truth; reconcile manually quarterly."* The current text reads like a feature that exists; it doesn't.

### 3.4 Atom-feed-to-email via Google Workspace — verify before commit

§5.3 commits to:

> *"the announce channel is the GitHub Releases Atom feed (/releases.atom) subscribed by the existing ai-sherpa-announce@<org> Google Group via Workspace's built-in feed-to-email."*

Google Groups historically supported RSS/Atom feed subscription as a "topic source." The feature has been deprecated and partially restored across years. Whether it works *today* in the specific Workspace edition the org uses is not guaranteed.

**Recommendation:** add a 30-minute verification step in Gate A: confirm the org's Workspace allows feed-to-email Group subscription. If not, the fallback (a tiny GitHub Action posting to the Group via Workspace API) is ~30 lines and within v2 scope — but the brief should name the fallback explicitly so it doesn't become a Gate B blocker.

### 3.5 mTLS on 150 Windows laptops — non-trivial; scope it

§9 mandates "mTLS + bearer tokens are not optional in Gate E." This is the right security posture. But mTLS on Windows laptops requires:

- A client cert per machine (issued at enrollment)
- A cert distribution mechanism (Intune-pushed, AD-distributed, or installed by setup script)
- A revocation path when a laptop is decommissioned

For 150 devs across multiple machines per dev, the certificate lifecycle is real ops work — not "set bearertokenauth in the OTel config."

**Recommendation:** Spike 3 (ops capability) should explicitly cover certificate distribution mechanism, not just "Docker or VM." Without this, Gate E will discover at week 12 that the security posture commits to ops work nobody has scoped.

### 3.6 Spike B (Admin API) exit thresholds not specified

§2 Spike 2: *"Does the Anthropic Admin API deliver per-developer acceptance rate, sessions, cost, LOC accepted?"* The exit criterion is *"compare actual schema to what the previous Phase 2a plan assumed."*

If the actual schema delivers 80% of the assumed fields, does that pass? 50%? 20%? **The criterion is "compare," not "decide."**

**Recommendation:** specify per-field criticality. E.g., *"acceptance rate per developer is required; missing field = Spike 2 fails. LOC accepted is desired but optional; missing = adjust Gate E scope."* Without this, the spike output is a description, not a decision.

### 3.7 JSON-schema validation against GitHub Issue forms — mechanism not pinned

§5.4 commits to:

> *"CI validates the Issue form output against feedback_issue.schema.json on every PR that touches .github/ISSUE_TEMPLATE/."*

GitHub Issue forms are validated by GitHub at submission time against the form's own YAML schema, not against an external JSON Schema. To validate "the Issue body output matches our schema" you'd need:

- A round-trip test (submit a fake Issue, capture body, validate against JSON Schema) — non-trivial in CI
- Or a static lint that converts the form YAML to a JSON Schema equivalent and asserts compatibility

**Recommendation:** name the mechanism. If it's the round-trip test, budget the work. If it's a static lint, name the tool. Currently this is a feature, not a process.

### 3.8 The `ai-sherpa` CLI is implicitly new

UC6 and UC7 introduce commands `ai-sherpa wipe-me` and `ai-sherpa what-do-you-have-on-me`. The brief doesn't acknowledge that **AI Sherpa has no `ai-sherpa` CLI today.** It has `setup.bat` / `setup.sh` / `setup.ps1` for install, plus the Phase 0.5 `python -m analyzer`.

The commands as named imply:
- A new top-level CLI binary
- A way for it to reach the Langfuse instance (URL config? service discovery?)
- An auth model for "is this dev allowed to query their own data?"

**Recommendation:** either commit to building the `ai-sherpa` CLI (with scope) as part of Gate B's deliverables, or rename UC6/UC7 to use existing tooling (e.g., `setup --revoke-telemetry`; `setup --export-my-data`). The latter is simpler.

### 3.9 Rollback semantics still have a race window

§6 risk #2 says:

> *"`setup --update` prints 'Was: vX → Now: vY' and refuses to update if VERSION is rolled back since last check"*

This protects future updates. It does not protect the dev who ran `setup --update` between when v2026.06.01 was published and when it was yanked. That dev is on the bad version with no signal.

**Recommendation:** add a "force re-pin on bad release" mechanism. Options:
- Newsletter-style "URGENT" Atom entry that setup checks for at startup
- A separate `BAD_VERSIONS` file in the repo that setup respects regardless of pin
- An out-of-band Slack/email notification path for yanked-release events

The brief acknowledges the risk; the mitigation is incomplete.

### 3.10 Continue.dev `dev_data` reference is loosely connected

§1's evidence table lists *"Continue.dev's dev_data initiative is the closest analog and is OSS."* §7 lists upstream collaboration with Continue's dev_data community.

But the brief doesn't say what we *use* from dev_data. Is it:
- A schema we adopt for our Scorer Registry payloads?
- A community we publish to but don't consume?
- An OTel-compatible event format we should align our spans with?

**Recommendation:** clarify in §3 the adopt-vs-build matrix. If Continue's dev_data schema is reusable for our Scorer payloads, adopt explicitly. If it's just an inspiration, say so. Today it reads like a reference that nothing actually depends on.

---

## 4. What's still missing (additions to v2)

These are gaps where v2 is silent but should have a position.

### 4.1 Testing strategy

The brief doesn't say what CI looks like for the Scorer Registry. Unit tests of individual scorers? Integration tests against a Langfuse instance? Property-based tests for fingerprint stability across schema changes?

For the ~800 lines of Scorer Registry code, the testing investment is at minimum 1.5x. Without a testing strategy in the brief, the implementation gates have nothing to enforce code quality against.

**Recommendation:** add a §5.7 "Testing posture" with at least: (a) Scorer Registry unit test coverage target; (b) integration test against a Langfuse compose stack in CI; (c) golden-output fingerprint regression tests.

### 4.2 Cost monitoring

The brief drops `cost_report.py` and says *"Langfuse evals can be cost-capped via standard config."* This is true for **Langfuse LLM-as-judge eval costs** but doesn't cover:

- Anthropic API costs if the Scorer Registry calls Claude for any reason (e.g., "is this prompt a recurring pattern?")
- Self-hosted Langfuse infrastructure costs (ClickHouse VM, OTel Collector gateway VM, disk)
- Managed Langfuse Cloud monthly bill if §11 question 4 lands on "managed"

A single page of expected monthly cost (decomposed by component) belongs in the brief. Without it, "Gate D scope decision" is being made without a budget envelope.

**Recommendation:** add §6.x cost envelope: *"expected monthly cost at steady state, decomposed."* Use ranges, not point estimates.

### 4.3 The relationship between Phase 1 Issues and Phase 2 Langfuse traces

Phase 1 ships manual feedback Issues. Phase 2 ships auto-filed Issues from Langfuse-detected patterns. Both flow into the same triage queue.

But the **back-reference** — when triaging a manual feedback Issue, can the central team query Langfuse for "have we seen this pattern in telemetry?" — is unspecified. This is a real workflow gap. The whole point of "single triage queue, two sources" is that the triager can pivot between them.

**Recommendation:** specify in §5.2 either: (a) the Issue body links to a Langfuse query/dashboard for the relevant signal, OR (b) the relationship is one-way (Langfuse → Issues only) and acknowledged.

### 4.4 The brief is silent on Phase 0.5 prototype's future

§10 says: *"the Phase 0.5 prototype code; reference for what detectors can compute, not what thresholds are correct."*

But the prototype was committed code, not just a reference. Does Phase 1 keep the `analyzer-prototype/` directory? Does Phase 2 use its detectors as the basis for Scorer Registry implementations? Or does it become an archive?

**Recommendation:** name the prototype's fate. Three plausible paths:
- "Archive `analyzer-prototype/` after Gate E; lessons documented in this brief."
- "`analyzer-prototype/` remains as a developer self-analysis tool, separate from the production Scorer Registry."
- "The prototype's detector implementations are lifted into the Scorer Registry as Phase 2 scaffolding."

Without naming it, the directory becomes ambiguous repo cruft.

### 4.5 Brief doesn't address how the v1 archived docs are handled in PRs

§10 says: *"Move to `docs/superpowers/archive/2026-05-30-pre-v2/` in the same commit that lands this brief."*

That's the right move. But it doesn't say:
- Whether the archived docs are commit-replayed (preserving full git blame history) or moved
- How they're surfaced from search (search-skip vs. search-include with prominent banner)
- Whether links to the archived docs from elsewhere in the codebase are auto-rewritten or accepted as dangling

**Recommendation:** add a small subsection: archive mechanics. 3 lines covering preservation of history, search-skip header, link rewriting.

---

## 5. Recommendation

Move to Gate A.

The v2 brief is ~80% ready as-is; the remaining ~20% is the refinements above (mostly mechanism-pinning, not redesigns). Two of those refinements (Langfuse-Claude-session-fit spike, OTel content-coverage fallback architecture) are load-bearing enough that I'd want them explicit before Gate A starts.

Specifically I would:

1. **Land the v2 brief as the program of record.** Move the v1 archive in the same commit.
2. **Update §2 (spikes) to add Spike 4 (Langfuse trace model fit) and tighten Spike 1 exit criteria to name the fallback architecture.**
3. **Update §3 / §5 with the mechanism pins from this doc:** Projects v2 board config Action, Atom-feed-to-email verification, JSON-schema validation mechanism, CLI scope, certificate distribution mechanism.
4. **Add §5.7 testing posture and §6.x cost envelope.**

Total refinement work: ~2 hours of editing the brief. Then Gate A starts and runs for 5 working days.

The v2 is the right shape. The refinements make it implementable without surprises.

---

## 6. One caveat worth saying out loud

The architect review's broader rhetorical claim — *"inward-facing infrastructure dressed as DX initiative"* — applies less to v2 than to v1, but doesn't fully vanish.

v2 is still a program that **the central team operates** to **produce rules that the central team approves** to **ship to 150 developers**. The dev's relationship to the system is still primarily "subject of measurement that occasionally files feedback."

The Scorer Registry is the right architectural contribution. It is not by itself a developer-experience contribution. To close that gap, the program would need (at minimum) one of:

- Faster feedback-to-fix latency (manual feedback fixed within 48h, not 1 week)
- Devs can see "here's what your feedback contributed to" via a public changelog with attribution
- A self-serve "ai-sherpa why?" CLI that explains why Claude did what it did using local + Langfuse data

None of these are in v2. They could be — and probably should be in a Gate D follow-on or a Gate F.

This isn't a v2 critique; it's an honest observation about the program's center of gravity. v2 is correct about what the central team should build. It does not yet articulate what each individual developer gets back, beyond "a better version next week."

That's worth saying because the architect review was correct that this matters, and v2 doesn't directly answer it.
