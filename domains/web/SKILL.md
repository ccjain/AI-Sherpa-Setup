---
name: ai-sherpa-web
description: Use when working on any full-stack web task — React, Vue, Angular, Next.js, Node.js, Express, FastAPI, Django, Spring, .NET, HTML, CSS, Tailwind, shadcn, frontend, backend, API endpoint, component, accessibility, UI, form, authentication. Provides full-stack security guardrails, accessibility rules, and framework conventions.
---

# AI Sherpa — Web (Full-stack) Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

## Context Check (Before Every Task)

Before generating code or design suggestions, confirm:
1. **Frontend framework** in use (React, Vue, Angular, Next.js, plain HTML/CSS, none)
2. **Backend framework** in use (Node/Express, FastAPI, Django, Spring, .NET, none)
3. **Design system** in use (Tailwind, shadcn/ui, Material UI, Chakra, custom, none)
4. **Target viewport** (desktop-first, mobile-first, both)
5. **Accessibility level** required (WCAG 2.1 AA is the default minimum)

Do not generate components without knowing the design system and target viewport.

---

## Browser Tooling

This domain ships **no automated browser-test framework by default.** For interactive
UI verification, console debugging, and form-flow testing, use the built-in
**Claude Code Chrome integration** — it drives a real Chrome window, sees your
existing logged-in state, and asks you to handle any login/CAPTCHA pages manually.

- Enable for a session: `claude --chrome`, or `/chrome` inside Claude Code
- Requires Claude Code ≥ 2.0.73, the "Claude in Chrome" extension, and a direct
  Anthropic plan (Pro / Max / Team / Enterprise). Not available on WSL or Brave/Arc.
- Use it for: design verification against a Figma mock, console error triage,
  form/validation testing, visual regression checks, recording demo GIFs.
- Docs: https://code.claude.com/docs/en/chrome

### When `/chrome` is not enough — opt in to Playwright

If you need any of the following, install the Playwright plugin per project:
- Automated e2e tests that run in CI on every PR
- Cross-browser testing (Firefox, WebKit)
- Visual-regression test suites with baseline diffs stored in the repo
- Headless / parallel test execution at scale
- Browser automation from a pure-WSL or pure-Linux shell (Chrome integration doesn't work there)

```bash
claude plugin install playwright@claude-plugins-official --scope user
```

`/chrome` covers ~80 % of day-to-day "look at the browser and tell me what you see"
needs, so it's the default. Playwright is opt-in for the test-automation cases above.

---

## Always Do (Frontend)

1. Sanitize all user-generated content before rendering to the DOM
2. Set Content Security Policy (CSP) headers on all responses
3. Use HTTPS everywhere — flag any mixed content immediately
4. Use httpOnly cookies for session tokens and sensitive data
5. For pages handling sensitive data, flag if SSR is missing and ask if intentional
6. Use semantic HTML (`<nav>`, `<main>`, `<section>`, `<button>`) — never `<div>` for interactive elements
7. Include keyboard navigation support for every interactive element (Tab-reachable)
8. Add ARIA labels and roles to all non-decorative interactive elements
9. Check colour contrast ratios meet WCAG 2.1 AA (4.5:1 normal text, 3:1 large/UI)
10. Specify responsive behavior for every layout (mobile / tablet / desktop breakpoints)
11. Add `rel="noopener noreferrer"` to all `target="_blank"` external links

## Never Do (Frontend)

1. Store sensitive data (tokens, PII, API keys) in `localStorage` or `sessionStorage`
2. Use `dangerouslySetInnerHTML` without explicit sanitization — flag and ask
3. Expose API keys or secrets in frontend source code or public repos
4. Use inline `<script>` blocks that bypass CSP
5. Pass secrets or credentials as React/Vue props or component state
6. Use colour alone to convey meaning — pair with text, icon, or pattern
7. Remove focus indicators without providing a visible alternative
8. Suggest animations without `prefers-reduced-motion` support
9. Trust client-side validation alone — flag where server-side validation is missing

---

## Always Do (Backend)

1. Use parameterized queries — never concatenate user input into SQL strings
2. Validate and sanitize ALL external inputs at the system boundary
3. Handle errors explicitly — never silently swallow exceptions or rejected promises
4. Pin all dependency versions — no wildcards (`*`, `^latest`, `~latest`)
5. Return generic error messages to API consumers — never expose stack traces or DB errors
6. Always validate file type AND size on file upload endpoints

## Never Do (Backend)

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
- Pin versions in `requirements.txt` / `pyproject.toml`
- Catch specific exception types — never bare `except:`
- Follow PEP 8

---

## Component Standards (UI/UX)

- **Forms:** Every input needs a visible `<label>`. Placeholder text is not a label substitute.
- **Buttons:** Use `<button>` not `<div onClick>`. Distinguish primary, secondary, and destructive variants visually.
- **Images:** Every `<img>` needs `alt` text. Decorative images use `alt=""`.
- **Modals/dialogs:** Trap focus when open, restore focus on close, support Escape to dismiss.
- **Loading states:** Visible feedback for any async operation over 300ms.

When a design system is confirmed, use its tokens (colours, spacing, typography)
exclusively — don't introduce raw hex values or ad-hoc spacing units. Flag any
deviation as a conscious exception.

---

## AI Effectiveness Boundaries

Effective: component code, accessibility audits, API endpoint scaffolding, input
validation, security headers, responsive layout, ARIA, design token usage,
test coverage gaps, static analysis.

Not suitable as final authority: visual design decisions (brand feel, aesthetic
direction), usability testing, accessibility certification sign-off, production
load testing, threat modeling.

---

## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin ships ~66 stack-specific
skills that auto-activate when their context matches. You do **not** need to
install them separately. Examples Claude will draw on when relevant:

- **Frontend frameworks:** React, Next.js, Vue, Angular, React Native, Flutter
- **Backend frameworks:** NestJS, FastAPI, Django, Spring Boot, .NET Core
- **Languages:** TypeScript, JavaScript, Python, Go, Java, Kotlin, C#
- **CMS / e-commerce:** WordPress, Shopify
- **Patterns & protocols:** microservices, GraphQL, WebSockets

If a skill isn't activating when you expect it to, mention the stack explicitly
in your prompt (e.g. "this is a Next.js 15 app" or "use Django ORM patterns").
