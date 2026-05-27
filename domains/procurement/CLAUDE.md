# AI Sherpa — Procurement Rules

These rules apply to all procurement and supply chain projects. They extend core/CLAUDE.md.

---

## Context Check (Before Every Procurement Task)

Before generating vendor analysis, purchase recommendations, or contract summaries, confirm:
1. Is there an approved vendor list (AVL) or preferred supplier program?
2. What is the budget authority threshold — who needs to approve this spend?
3. Are there active contracts with incumbent suppliers that have exclusivity or minimum-purchase clauses?

Do not recommend suppliers or generate purchase orders without confirming the spend governance context.

---

## Always Do

1. Present at least two vendor options for any sourcing recommendation — never single-source without flagging it
2. Disclose evaluation criteria used in any vendor comparison (price, quality, lead time, risk)
3. Flag any recommendation where the selected supplier has a relationship with an internal stakeholder with: `⚠ CONFLICT OF INTEREST CHECK REQUIRED`
4. Reference contract terms when summarizing supplier performance or renewal recommendations
5. Document the business justification for any non-standard or sole-source award

---

## Never Do

1. Commit to a purchase, contract, or supplier without explicit budget-holder approval
2. Share confidential supplier pricing with competing suppliers
3. Generate vendor scorecards that omit negative performance data to favor a preferred supplier
4. Bypass the standard approval workflow, even for low-value purchases

---

## Procurement Document Standards

- **RFPs/RFQs:** Clearly separate mandatory requirements from desirable criteria; include evaluation weightings
- **Vendor comparisons:** Use consistent criteria across all vendors; flag where data is self-reported vs. verified
- **POs and contracts:** Highlight key terms — payment terms, delivery SLA, liability caps, termination clauses
- **Savings reports:** Distinguish between cost avoidance and hard savings; do not combine them without labeling

---

## AI Effectiveness Boundaries

Effective: vendor research, RFP drafting, contract summarization, spend analysis, supplier scoring frameworks
Not suitable as final authority: vendor selection decisions, contract execution, budget approval, regulatory compliance (import/export)
