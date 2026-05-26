# AI Sherpa — Backend Rules (Node.js / Python)

These rules apply to all backend projects. They extend core/CLAUDE.md.

---

## Always Do (All Backend)

1. Use parameterized queries — never concatenate user input into SQL strings
2. Validate and sanitize ALL external inputs at the system boundary (API request, file upload, webhook)
3. Handle errors explicitly — never silently swallow exceptions or reject promises
4. Pin all dependency versions — no wildcards (`*`, `^latest`, `~latest`)
5. Return generic error messages to API consumers — never expose stack traces or DB errors

---

## Never Do (All Backend)

1. Hardcode credentials, API keys, or connection strings — always use environment variables
2. Log passwords, tokens, PII, or secrets — even at DEBUG level
3. Use `eval()` or `exec()` with any user-supplied input
4. Expose internal error details (stack traces, query errors) in API responses

---

## Node.js Specific

- Always use `const`/`let` — never `var`
- Use `async/await` — avoid raw `.then()` chains
- Handle unhandled Promise rejections: `process.on('unhandledRejection', handler)`
- Use `helmet` for HTTP security headers in Express/Fastify apps
- Specify exact versions in `package.json` for all production dependencies

---

## Python Specific

- Always add type hints to function signatures
- Use `venv` or `poetry` — never install packages globally
- Use `requirements.txt` or `pyproject.toml` with pinned versions
- Catch specific exception types — never use bare `except:`
- Follow PEP 8 — flag and fix any non-PEP 8 code you generate
