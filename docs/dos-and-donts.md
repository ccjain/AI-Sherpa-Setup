# AI Sherpa — Do's & Don'ts Reference

These rules are enforced in all AI Sherpa-configured projects via CLAUDE.md. Rules marked **[ALL]** apply to every domain. Domain-specific rules are additive.

---

## [ALL DOMAINS] — Universal Rules

### Pre-Flight Check (Run Before EVERY Session)

**Step 1 — NDA & Confidentiality**
Ask the developer:
> "Before we start — can this project's code be shared with Anthropic's API? Does this project have any NDA, confidentiality agreement, or export control restrictions?"

Also scan the repository for: `NDA.md`, `NDA.txt`, `CONFIDENTIAL.md`, `CONFIDENTIAL.txt`, any file with "confidential", "proprietary", "nda", or "trade-secret" in the filename, or a LICENSE file containing "proprietary" or "all rights reserved".

If found, stop and report the confidentiality file before continuing. Never assume permission — explicit developer confirmation required every session.

**Step 2 — Architecture Understanding**
Before any task, read and understand the existing architecture. Use graphify to explore the codebase (graphify is the codebase knowledge-graph tool). If the architecture is unclear or undocumented, ask the developer to explain it before writing any code.

### Always Do

1. Complete the Pre-Flight Check before starting any session
2. Write tests before or alongside new code
3. Request code review before marking a task complete — use `/requesting-code-review`
4. Plan before implementing — use `/writing-plans` for non-trivial tasks
5. State what you are about to do before doing it
6. Prefer editing existing files over creating new ones
7. Flag uncertainty explicitly — never guess silently
8. Confirm task understanding with the developer if requirements are ambiguous

### Never Do

1. Run destructive commands (rm -rf, DROP TABLE, force-push, reset --hard) without explicit developer confirmation
2. Commit secrets, credentials, API keys, or passwords
3. Read, display, or log contents of `.env`, `*.key`, `*.pem`, or credential files
4. If a command prints secrets to stdout — stop and do not include the output in your response
5. Skip tests or mark work complete without running and verifying
6. Generate code for unknown APIs without checking their documentation first
7. Make architectural changes without a written plan reviewed by a human
8. Add features beyond what was explicitly requested (YAGNI)
9. Add error handling for scenarios that are provably impossible given the current system design — if unsure, ask before skipping
10. Add comments explaining WHAT code does — only WHY if non-obvious
11. Push to main/master directly
12. Assume a task is done without running it

### Secrets Protection

`.claudeignore` is unreliable for blocking file access. Protection is enforced via `settings.json` deny rules. As an additional layer, never read or reference the content of any file matching: `.env`, `.env.*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`, files in `secrets/`, `credentials/`, `.aws/`, `.ssh/`.

---

## [EMBEDDED] — C/C++, Firmware, RTOS

### Architecture Check (Before Every Embedded Task)

Before writing any code, ask the developer if not already documented:
1. Which toolchain is in use? (GCC ARM / IAR / Keil / MPLAB / other)
2. Which RTOS or bare-metal framework? (FreeRTOS / Zephyr / bare-metal / other)
3. Target hardware constraints — RAM, flash size, CPU clock speed
4. Any MISRA-C compliance requirement?

Do not assume or guess hardware context. Proceed only once confirmed.

### Always Do

1. Annotate ISRs with their timing constraints and expected execution time
2. Prefer iterative over recursive — always consider stack depth impact
3. Reference the project's datasheet or HAL before suggesting register access
4. State explicitly: "This suggestion requires hardware-in-the-loop testing to verify"

### Never Do

1. Use dynamic memory allocation (malloc/free) unless developer explicitly approves
2. Suggest hardware register access without a datasheet/HAL reference
3. Claim code correctness without hardware-in-the-loop testing
4. Apply MISRA-C suggestions to non-safety-critical modules without asking first

### Hardware-Critical Flag

Any change to the following must be flagged with `⚠ HUMAN REVIEW REQUIRED — hardware-critical change` before proceeding:
- Interrupt service routines (ISRs)
- Memory-mapped hardware register access
- Real-time scheduling or timing logic
- Boot/startup code
- Safety-critical control loops
- DMA configuration
- Power management sequences

### AI Effectiveness Boundaries

**Effective:** logic bugs, unit tests, code style, test coverage gaps, static analysis

**Not suitable as final authority:** timing analysis, hardware-specific optimisation, real-time behaviour, physical signal integrity

---

## [WEB / FRONTEND] — React, Vue, Angular, HTML/CSS

### Always Do

1. Sanitize all user-generated content before rendering to the DOM
2. Set Content Security Policy (CSP) headers on all responses
3. Use HTTPS everywhere — flag any mixed content immediately
4. Use httpOnly cookies for session tokens and sensitive data
5. For pages handling sensitive data, flag if the project lacks server-side rendering and ask the developer if that is intentional

### Never Do

1. Store sensitive data (tokens, PII, API keys) in `localStorage` or `sessionStorage`
2. Use `dangerouslySetInnerHTML` without explicit sanitization — flag and ask developer
3. Expose API keys or secrets in frontend source code or public repos
4. Use inline `<script>` blocks that bypass CSP
5. Pass secrets or credentials as React/Vue props or component state

### Security Defaults

- Always add `rel="noopener noreferrer"` to external links (`target="_blank"`)
- Always validate file type AND size on file upload inputs
- Never trust client-side validation alone — flag where server-side validation is missing

---

## [BACKEND] — Node.js, Python

### Always Do (All Backend)

1. Use parameterized queries — never concatenate user input into SQL strings
2. Validate and sanitize ALL external inputs at the system boundary (API request, file upload, webhook)
3. Handle errors explicitly — never silently swallow exceptions or reject promises
4. Pin all dependency versions — no wildcards (`*`, `^latest`, `~latest`)
5. Return generic error messages to API consumers — never expose stack traces or DB errors

### Never Do (All Backend)

1. Hardcode credentials, API keys, or connection strings — always use environment variables
2. Log passwords, tokens, PII, or secrets — even at DEBUG level
3. Use `eval()` or `exec()` with any user-supplied input
4. Expose internal error details (stack traces, query errors) in API responses

### Node.js Specific

- Always use `const`/`let` — never `var`
- Use `async/await` — avoid raw `.then()` chains
- Handle unhandled Promise rejections: `process.on('unhandledRejection', handler)`
- Use `helmet` for HTTP security headers in Express/Fastify apps
- Specify exact versions in `package.json` for all production dependencies

### Python Specific

- Always add type hints to function signatures
- Use `venv` or `poetry` — never install packages globally
- Use `requirements.txt` or `pyproject.toml` with pinned versions
- Catch specific exception types — never use bare `except:`
- Follow PEP 8 — flag and fix any non-PEP 8 code you generate

---

## [DATA SCIENCE / ML] — Python, Notebooks, Pipelines

### Always Do

1. Check dataset size before loading (`df.shape`, `wc -l`, or file size check) — never load a full dataset without confirming it fits in memory
2. Version data and models alongside code (use DVC, MLflow, or equivalent)
3. Use environment variables or config files for file paths — never hardcode
4. Flag any risk of data leakage between train/test splits when reviewing ML pipelines
5. Document data sources and schema in code comments when they are non-obvious

### Never Do

1. Hardcode absolute file paths — use `pathlib.Path` or config variables
2. Commit large data files or model weights to Git — use DVC or cloud storage
3. Use the same data split for both hyperparameter tuning and final evaluation (data leakage)
4. Suppress warnings from ML libraries without understanding their cause
5. Process or load datasets that may contain PII without first asking the developer to confirm the data is anonymized and approved for use

### Code Quality

- Always use type hints in Python functions
- Always use `venv` or `poetry` — never install packages globally
- Pin all package versions in `requirements.txt` or `pyproject.toml`
- Prefer reproducible random seeds — set `random.seed()`, `np.random.seed()`, `torch.manual_seed()`

---

## [DEVOPS / PLATFORM] — Terraform, Ansible, CI/CD

### Always Do

1. Use Infrastructure-as-Code (Terraform, Ansible, Pulumi) — never make manual cloud console changes
2. Estimate blast radius before applying any infrastructure change — state it explicitly
3. Document a rollback plan before deleting or modifying existing infrastructure
4. Store all secrets in a secrets manager (Vault, AWS Secrets Manager, GitHub Secrets) — never in code or config files
5. Tag all cloud resources with environment, owner, and cost-centre

### Never Do

1. Hardcode environment-specific values (IP addresses, region names, account IDs, credentials) in IaC files
2. Apply `terraform apply` or equivalent without first running and reviewing `terraform plan`
3. Delete infrastructure (databases, queues, storage buckets) without an explicit rollback plan approved by a human
4. Store secrets in environment variables in CI/CD pipeline YAML files — use the platform's secret store
5. Give IAM roles or service accounts more permissions than they need (principle of least privilege)
6. Add secrets or credentials as plaintext values in `docker-compose.yml` — always use environment variable references (`${VAR_NAME}`) pointing to the platform's secret store

### GitHub Actions Specific

- Always pin GitHub Actions to a specific SHA, not a mutable tag (`uses: actions/checkout@abc1234` not `@v3`)
- Never print secrets to workflow logs — use `::add-mask::` for sensitive values
- Store all API keys and tokens as GitHub Secrets — never in workflow YAML
