# AI Sherpa — Frontend + UI/UX Rules

These rules apply to frontend and UI/UX work — narrower than the full-stack
`web` domain. Use this domain when the focus is design systems, component
libraries, accessibility, performance, browser compatibility, or visual
craft. They extend the global rules in `core/CLAUDE.md` — do not remove
global rules.

---

## Context Check (Before Every Frontend Task)

Before writing code, confirm if not already documented:

1. Framework + version? (React 19, Vue 3, Svelte 5, vanilla HTML/CSS, etc.)
2. Styling system? (Tailwind v4, CSS Modules, styled-components, vanilla
   CSS, design tokens from a system)
3. Component library? (shadcn/ui, Radix, Headless UI, MUI, Ant Design, none)
4. Target browsers / devices? (latest evergreens only? IE11? mobile first?)
5. Accessibility bar? (WCAG 2.2 AA is the baseline; some products go higher)

Don't infer the stack from `package.json` alone — ask what's actually
in use.

---

## Accessibility — Always Do

1. **Semantic HTML first.** Use `<button>` for actions, `<a href>` for
   navigation, `<nav>`, `<main>`, `<article>`, `<aside>`, `<h1>`…`<h6>`
   in order. Reach for ARIA only when semantic HTML can't express the
   pattern.
2. **Every interactive element is keyboard reachable** and shows a visible
   focus ring. Tab order matches reading order.
3. **Color is never the only signal.** Pair it with text, icon, or pattern.
4. **All images and icons have alt text** (or `alt=""` for decorative).
   Form fields have associated `<label>`. Buttons have accessible names.
5. **Run an automated audit** (axe-core, Lighthouse a11y, jsx-a11y lint)
   before declaring a change done. Aim for 0 violations.

---

## Performance — Always Do

1. **Measure before/after.** Lighthouse or Web Vitals (LCP, INP, CLS).
   Don't claim a perf win without a number.
2. **Lazy-load below the fold.** Images, iframes, heavy components.
3. **Code-split route-level.** Don't ship the admin bundle to logged-out
   visitors.
4. **Avoid blocking JS in `<head>`.** Use `defer` or `async` where the
   script doesn't need to run synchronously.
5. **Watch the bundle.** State the size delta when you add a dependency.

---

## Design System Discipline — Always Do

1. **Use design tokens, never hardcoded colors / spacing / fonts.** If a
   token doesn't exist for what you need, surface the gap — don't invent
   a one-off value.
2. **Compose, don't extend.** Build from primitive components rather than
   subclassing or copy-pasting variants.
3. **Match the existing patterns.** If the codebase uses a Button with
   `variant="ghost"`, don't invent `variant="light"` for the same idea.
4. **Spacing comes from the scale.** Tailwind spacing tokens, CSS custom
   properties, or your tokens module — never magic numbers.

---

## Never Do (Frontend)

1. **Never disable a11y warnings without explanation.** If you suppress an
   `eslint-plugin-jsx-a11y` rule or an axe finding, add a comment with the
   reason and a remediation plan.
2. **Never ship a UI that breaks at 320px width** unless the spec
   explicitly excludes mobile. Test the narrowest viewport early, not at
   the end.
3. **Never use `dangerouslySetInnerHTML` / `v-html` / equivalent on
   untrusted content** without explicit sanitization. Note the
   sanitization strategy in code.
4. **Never assume English-only.** Strings go through i18n if the product
   ships in multiple locales — don't bake copy into the component.

---

## AI Effectiveness Boundaries

**Effective:** component scaffolding, prop-typing, a11y audits, design-token
substitution, layout debugging, perf audit triage, animation timing,
microcopy drafts, regex for CSS extraction.

**Not suitable as final authority:** visual design judgment (taste, brand
voice), final accessibility certification (use a real audit + user testing),
brand-tone copy decisions (involve a writer), motion appropriateness for
users with vestibular disorders (respect `prefers-reduced-motion`).

---

## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin includes React, Vue,
Next.js, TypeScript, and JavaScript skills that auto-activate when working
in those frameworks.

If you picked the `frontend` domain (this one), you also get:
- `addyosmani/web-quality-skills` — Lighthouse, Core Web Vitals, a11y, SEO,
  best-practices skills from Addy Osmani (Google Chrome team).
- `bitjaru/styleseed` — shadcn + Tailwind v4 + Radix design system,
  48 components + brand skins.

Mention a topic explicitly (`"Using Core Web Vitals, …"`) if a skill isn't
activating when you expect it to.
