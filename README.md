```
                                                                      /\
   █████╗ ██╗    ███████╗██╗  ██╗███████╗██████╗ ██████╗  █████╗     /  \
  ██╔══██╗██║    ██╔════╝██║  ██║██╔════╝██╔══██╗██╔══██╗██╔══██╗   / /\ \
  ███████║██║    ███████╗███████║█████╗  ██████╔╝██████╔╝███████║  /_/  \_\
  ██╔══██║██║    ╚════██║██╔══██║██╔══╝  ██╔══██╗██╔═══╝ ██╔══██║
  ██║  ██║██║    ███████║██║  ██║███████╗██║  ██║██║     ██║  ██║
  ╚═╝  ╚═╝╚═╝    ╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝
```

> _Guiding your team's Claude Code expedition._

**AI Sherpa is a one-command installer that sets up Claude Code on your machine
the way our team uses it.** You pick your domain (embedded, web, marketing,
finance, etc.) and the script installs the right plugins, skills, and rules
so Claude already knows the conventions you work in. You don't need to be
an "AI person" to use it — you just need to know your domain. This guide
shows you how.

---

## 1. Install it (5 minutes, one time)

### On Windows

```powershell
git clone <this-repo-url> ai-sherpa
cd ai-sherpa
.\setup.bat
```

### On Mac / Linux / WSL

```bash
git clone <this-repo-url> ai-sherpa
cd ai-sherpa
bash setup.sh
```

The script will:

1. Show a banner with the AI Sherpa logo.
2. Auto-install anything missing (Node.js, Git, Python, Rust if needed).
3. Ask you which domain you're in — type a number 1–11.
4. Install plugins / skills / tools for that domain. Takes 2–5 min.
5. Print a summary. Done.

After it finishes, open a new terminal window. (Setup adds some things to your
PATH that only a fresh terminal will see.)

---

## 2. Pick your domain

You'll be prompted to pick a number. Pick the one closest to what you do day-to-day:

| # | Domain | Pick this if you… |
|---|---|---|
| 1 | Embedded Software | Write C/C++ firmware, work with MCUs, RTOS, Zephyr, FreeRTOS |
| 2 | Web (full-stack) | Build websites / web apps end-to-end (frontend + backend) |
| 3 | Data Science / ML | Work with notebooks, pipelines, models, RAG |
| 4 | DevOps / Platform | Write Terraform, manage K8s, run CI/CD, oncall |
| 5 | Marketing | Write campaign briefs, do SEO, plan content |
| 6 | Sales | Draft outreach, manage deals, work in a CRM |
| 7 | Finance / Accounting | Close books, build models, audit statements |
| 8 | Customer Service | Triage tickets, write KB articles |
| 9 | Procurement / Ops | Manage vendors, run RFPs, document processes |
| 10 | AI / ML Agents | Build LLM apps, design agent flows, run evals |
| 11 | Frontend + UI/UX | Focus only on UI work, design systems, accessibility |

Picking the "wrong" one isn't a disaster — you can re-run setup with a
different number anytime.

---

## 3. Start using Claude

Open a terminal **in your project folder** and run:

```bash
claude
```

That's it. You're now in a chat with Claude that already knows your domain rules.

### Talk to it like a smart new teammate

The single biggest unlock: **don't treat Claude like Google**. Treat it like
a senior engineer / analyst who's smart but new to your project. They need
context, examples, and constraints to do good work.

**Weak prompt:**
> Fix this bug.

**Strong prompt:**
> This Zephyr app crashes 30 seconds after BLE pairing. We're using
> nRF5340dk, Zephyr 3.5, the GATT service is in `src/gatt_service.c`.
> The k_oops appears at `bt_conn_unref`. I think it's a use-after-free
> on the connection pointer. Show me where the bug likely is, then
> propose a fix I can verify.

The second one gives Claude what it needs to be useful: the platform, the
versions, where to look, your hypothesis, and what kind of answer you want.

---

## 4. Try these to see what's loaded

Once you're in `claude`, try these to confirm the right things are installed
for your domain:

```
/help                # lists every command available right now
/plugin              # shows installed plugins
```

Then ask a domain-specific question and watch a skill auto-load:

| If you picked | Try asking |
|---|---|
| Embedded (1) | "How do I add a custom STM32 board to my Zephyr project?" |
| Web (2) | "Audit my homepage for Core Web Vitals." |
| Data (3) | "Help me optimize this slow SQL query." |
| DevOps (4) | "Write a Kubernetes deployment for a Node.js service with autoscaling." |
| Marketing (5) | "Draft an SEO brief for an article about ARM Cortex-M debugging." |
| Sales (6) | "Help me write a cold outreach email to a VP of Engineering at a robotics company." |
| Finance (7) | "Walk me through month-end close for a SaaS startup." |
| AI (10) | "Set up prompt caching on this long system prompt." |
| Frontend (11) | "Make this React component WCAG 2.2 AA compliant." |

When you ask one of these, you'll see Claude pick up a "skill" — a
pre-built piece of expertise that activates because your prompt matched
its description. You don't have to invoke it by name; mentioning the
topic is enough.

---

## 5. Do's and Don'ts when working with AI

These apply to every Claude session, regardless of domain.

### ✅ DO

| Do | Why |
|---|---|
| **Give Claude context** — paste relevant code, file paths, error messages, version numbers, constraints | Claude can't see your project until you show it. Without context, you get generic answers. |
| **State your constraints up front** — "no dynamic memory allocation", "must compile with MSVC", "production environment, can't restart" | Claude will respect them. Add them at the start, not after it's already written something. |
| **Ask for tradeoffs, not just answers** — "What are the two best ways to do X, with pros/cons?" | Surfaces decisions you'd otherwise miss. |
| **Verify before trusting** — actually run the code; check the link Claude cited; rerun the test | Claude can hallucinate API names, function signatures, RFC numbers. Trust but verify. |
| **Use `/code-review` after substantive changes** | Catches bugs, security issues, simplifications. Available globally. |
| **Use `/clear` when switching to a new task** | Long conversations get noisy and Claude gets distracted. Fresh context = better answers. |
| **Read the suggested commands before running them** | Claude can suggest `rm -rf` or destructive git ops with good intent but bad impact. Eyes on every command. |
| **Push back when an answer feels off** | "That doesn't match the docs I just linked" or "we said no third-party deps" — Claude course-corrects well. |
| **Mention a specific skill by name** when auto-activation isn't picking it up | E.g., "Use the **board-bringup** skill to help me port…" |

### ❌ DON'T

| Don't | Why |
|---|---|
| **Don't paste secrets** — API keys, passwords, `.env` contents, customer PII, private SSH keys | Claude is a remote service. Anything you paste leaves your machine. Setup blocks reads of `.env`, `*.pem`, etc., but copy-pasting bypasses that. |
| **Don't skip review on safety-critical code** — ISRs, register access, boot code, DMA setup, motor control loops | Claude is good at logic; not the final authority on real-time behavior or signal integrity. Always do hardware-in-the-loop verification. |
| **Don't assume Claude knows your private codebase** | It doesn't. Show it the relevant files explicitly. The `code-review-graph` tool (auto-installed) helps Claude understand structure, but it's not omniscient. |
| **Don't run Claude's suggested destructive commands** (force push, hard reset, drop table) **without reading them** | Claude doesn't know which side-effects matter. You do. |
| **Don't use on NDA / confidential projects without confirming** | Some projects can't have code shared with an LLM. Check with your manager. Claude asks at session start; answer honestly. |
| **Don't accept "it should work"** as evidence | Ask for the test that proves it works. Run it. Read the output. |
| **Don't believe outdated examples blindly** | Claude was trained on a snapshot of the internet. Library APIs change. If something looks wrong, check the actual docs. |
| **Don't expect Claude to read your mind on style preferences** | If you want kebab-case, 80-col wrapping, no semicolons in JS — say so. Once per task is enough. |

---

## 6. Tricks the team uses

Small things that punch above their weight:

- **Start every new task with a single sentence about the goal.** "I want to add X to Y so that Z." Then paste context. Then ask for help.
- **For bugs, share the error message verbatim**, including the stack. Don't paraphrase.
- **For new code, ask Claude to write the test first**, then the implementation. Test-driven prompting catches a lot of nonsense.
- **For refactors, ask "what's the minimum change?"** before "here's a better design." Keeps PRs small and reviewable.
- **For research, ask Claude to cite docs / RFCs / source.** If it can't, double-check the claim manually.
- **For PRs, run `/code-review`** before opening. Catches things you'd otherwise field in review comments.
- **Use the `/verify` command** when you've made changes — it runs a sanity check (depending on your domain).
- **Type `! <command>` in the Claude prompt** to run a shell command and have Claude see the output. Useful for "what's in this directory?" or "what does this script say?"
- **Compact the session at ~70% context usage.** Claude Code shows your token usage near the prompt. When it hits roughly 70%, run **`/compact`** — Claude summarizes the conversation so far and continues with that summary, freeing up space for the rest of your task. Don't wait until Claude auto-compacts near 100%; the manual call gives a cleaner summary because you can hint what to keep ("compact but preserve the file layout we agreed on"). Different from `/clear`, which wipes the conversation entirely.

---

## 7. When things go wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| `claude: command not found` after setup | Setup ran but PATH didn't update yet | Open a new terminal. If still missing, re-run setup. |
| Claude says "no skill found" for an obvious topic | The skill description didn't match your phrasing | Mention the skill name explicitly. See `docs/skills-inventory.md` for what's installed. |
| Setup printed a yellow `OPTIONAL STEPS SKIPPED` block | A non-critical install (usually Python or Rust toolchain on a locked machine) failed | Read the suggested manual command. Plugins still work without it. |
| Setup printed a red `SETUP INCOMPLETE` block | A required plugin failed to register | Re-run setup. If it persists, the marketplace may be temporarily down. |
| Claude is suggesting outdated APIs | Library moved since the model's training cutoff | Paste the current docs and ask Claude to use those. |
| You want a clean slate | Whatever | `setup.bat --uninstall` (type `uninstall` to confirm), then re-run setup. |
| You picked the wrong domain | Just re-run setup | The interactive prompt lets you pick a new domain. Old plugins stay; `--uninstall` first for a truly clean switch. |

Detailed troubleshooting in [`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## 8. Where to learn more

- **[User Guide](docs/user-guide.md)** — deeper walkthrough of install scenarios (native vs WSL+Windows hybrid), update + uninstall flow, per-domain details
- **[Do's & Don'ts Reference Card](docs/dos-and-donts.md)** — printable cheat sheet
- **[Skills & Plugins Inventory](docs/skills-inventory.md)** — what each plugin and skill actually does, with links to every `SKILL.md` on GitHub
- **[Admin Guide](docs/admin-guide.md)** — for whoever curates `plugins.json` and decides what gets installed

---

## 9. Who to ask

- For tooling / install / setup issues: open a GitHub Issue on this repo.
- For domain-specific best practices ("how does our team handle X?"): ask your team lead first — they may already have it in `domains/<x>/CLAUDE.md`.
- For Claude itself acting weird: rerun with `/clear` and try again. If it's still wrong, share the prompt + response with the team channel.

Welcome to the expedition. ⛰️
