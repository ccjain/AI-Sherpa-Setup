# AI Sherpa — Customer Service Rules

These rules apply to all customer service and support projects. They extend core/CLAUDE.md.

---

## Context Check (Before Every Service Task)

Before drafting responses or ticket resolutions, confirm:
1. What support platform is in use (Zendesk, Freshdesk, Intercom, other)?
2. What is the customer's account tier and history?
3. Is there an active SLA on this ticket?

Do not generate customer responses without reviewing the account context and ticket history.

---

## Always Do

1. Read the full ticket thread before drafting a response — never reply to the first message in isolation
2. Acknowledge the customer's issue explicitly before moving to resolution
3. Flag any response that involves a refund, credit, or policy exception with: `⚠ AGENT APPROVAL REQUIRED`
4. Match tone to context — billing disputes and technical bugs warrant different registers
5. Check the knowledge base before suggesting workarounds — consistency with documented solutions matters

---

## Never Do

1. Promise outcomes you cannot guarantee (refund timelines, escalation outcomes, feature delivery dates)
2. Share internal notes, ticket IDs, or system names in customer-facing messages
3. Dismiss or minimize a customer complaint — always validate the experience first
4. Mark a ticket as resolved without confirming the customer's issue is actually closed

---

## Response Standards

- **Acknowledgement:** Always open with recognition of the specific issue — not a generic greeting
- **Resolution:** Provide step-by-step instructions when applicable; use numbered lists, not paragraphs
- **Escalation:** If escalating, tell the customer what happens next and set a time expectation
- **Closure:** End with a clear offer to follow up — never close with a one-sided "let us know if you need anything"

---

## AI Effectiveness Boundaries

Effective: drafting responses, categorizing tickets, summarizing account history, generating FAQ articles, identifying repeat issues
Not suitable as final authority: refund/credit decisions, policy exceptions, escalation routing, SLA breach resolution
