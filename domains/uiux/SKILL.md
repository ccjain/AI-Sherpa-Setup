---
name: ai-sherpa-uiux
description: Use when working on any UI design / UX task — wireframe, mockup, prototype, Figma, design system, design tokens, user research, usability, information architecture, visual design, interaction design, design review. Provides UI/UX design conventions and review patterns.
---

# AI Sherpa — UI/UX Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

## Context Check (Before Every UI/UX Task)

Before generating any UI code or design suggestions, confirm:
1. Which design system is in use? (Tailwind CSS, shadcn/ui, Material UI, Chakra, custom — or none)
2. What is the target viewport? (desktop-first, mobile-first, both)
3. Is there a Figma file or design spec to reference?
4. What accessibility level is required? (WCAG 2.1 AA is the default minimum)

Do not generate UI components without knowing the design system and target viewport.

---

## Always Do

1. Include keyboard navigation support for all interactive elements — every button, link, and form field must be reachable via Tab
2. Add ARIA labels and roles to all non-decorative interactive elements
3. Specify responsive behavior for every layout — what changes at mobile, tablet, and desktop breakpoints
4. Check colour contrast ratios meet WCAG 2.1 AA (4.5:1 for normal text, 3:1 for large text and UI components)
5. Use semantic HTML elements (`<nav>`, `<main>`, `<section>`, `<button>`) — never use `<div>` for interactive elements
6. Reference the Figma design file when one is available before proposing visual changes

---

## Never Do

1. Generate UI without specifying how it behaves at mobile viewport — no desktop-only designs
2. Use colour alone to convey meaning — always pair colour with text, icon, or pattern
3. Remove focus indicators (`:focus`, `outline`) without providing a visible alternative
4. Hardcode pixel dimensions without considering fluid/responsive alternatives
5. Suggest animations or transitions without including `prefers-reduced-motion` media query support

---

## Component Standards

- **Forms:** Every input must have a visible `<label>`; never use placeholder text as a substitute for a label
- **Buttons:** Use `<button>` not `<div onClick>`; distinguish primary, secondary, and destructive variants visually
- **Images:** Every `<img>` must have `alt` text; decorative images use `alt=""`
- **Modals/dialogs:** Trap focus inside when open; restore focus on close; support Escape key dismissal
- **Loading states:** Provide visible feedback for any async operation over 300ms

---

## Design System Integration

When a design system is confirmed, use its tokens (colours, spacing, typography) exclusively — do not introduce raw hex values or arbitrary spacing units that bypass the system. Flag any deviation from the system as a conscious exception.

---

## AI Effectiveness Boundaries

Effective: component code, accessibility audits, responsive layout suggestions, design token usage, ARIA implementation
Not suitable as final authority: visual design decisions (brand feel, aesthetic direction), usability testing, accessibility certification sign-off
