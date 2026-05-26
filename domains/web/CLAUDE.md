# AI Sherpa — Web / Frontend Rules

These rules apply to all web and frontend projects (React, Vue, Angular, HTML/CSS/JS).
They extend the global rules in core/CLAUDE.md.

---

## Always Do (Web)

1. Sanitize all user-generated content before rendering to the DOM
2. Set Content Security Policy (CSP) headers on all responses
3. Use HTTPS everywhere — flag any mixed content immediately
4. Use httpOnly cookies for session tokens and sensitive data
5. Prefer server-side rendering for pages that handle sensitive data

---

## Never Do (Web)

1. Store sensitive data (tokens, PII, API keys) in `localStorage` or `sessionStorage`
2. Use `dangerouslySetInnerHTML` without explicit sanitization — flag and ask developer
3. Expose API keys or secrets in frontend source code or public repos
4. Use inline `<script>` blocks that bypass CSP
5. Pass secrets or credentials as React/Vue props or component state

---

## Security Defaults

- Always add `rel="noopener noreferrer"` to external links (`target="_blank"`)
- Always validate file type AND size on file upload inputs
- Never trust client-side validation alone — flag where server-side validation is missing
