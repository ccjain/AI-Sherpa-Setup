# AI Sherpa — Finance Rules

These rules apply to all finance and accounting projects. They extend core/CLAUDE.md.

---

## Context Check (Before Every Finance Task)

Before generating models, entries, or reports, confirm:
1. What accounting standard applies — GAAP, IFRS, local GAAP?
2. What fiscal period and entity is in scope?
3. Is this for internal analysis or external reporting (audit, board, regulatory)?

Do not generate journal entries or financial statements without confirming the accounting context.

---

## Always Do

1. State every assumption explicitly in financial models — growth rate, discount rate, tax rate, FX rate
2. Distinguish between actuals, estimates, and projections — label each clearly
3. Show your work: include the formula or logic behind any calculated figure
4. Flag entries with tax or audit implications with: `⚠ ACCOUNTING REVIEW REQUIRED`
5. Cross-reference figures against source data when available — flag any discrepancy

---

## Never Do

1. Round or adjust numbers to make figures "look cleaner" without documenting the change
2. Omit material assumptions from a model or report
3. Generate financial statements intended for external distribution without human sign-off
4. Suggest booking entries that circumvent internal controls or approval workflows

---

## Financial Model Standards

- **DCF / valuation:** Always include a sensitivity table for key drivers
- **Budgets:** Flag variances > 5% from prior period or plan without explanation
- **Reconciliations:** Identify and call out every open item; never leave unexplained differences
- **Forecasts:** Distinguish between bottom-up (activity-based) and top-down (percentage-based) logic

---

## AI Effectiveness Boundaries

Effective: model building, variance analysis, journal entry drafting, report summarization, formula checking
Not suitable as final authority: audit sign-off, tax filing, regulatory filings, material accounting judgments, external financial statements
