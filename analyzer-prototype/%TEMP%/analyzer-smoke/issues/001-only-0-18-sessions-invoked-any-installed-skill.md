# [skill-fix] Only 0/18 sessions invoked any installed skill

**Scenario:** scenario-1 (see roadmap §3)
**Domain:** any
**Severity:** normal
**Confidence:** low

## Suggested change

Of 18 analyzed sessions, only **0** invoked any installed skill. This is a low-confidence aggregate signal that installed skill `description:` fields may not match real prompts. Per-session matching against skill descriptions is deferred to Phase 2a.

**Suggested change:** review each installed skill's `description:` field; tighten or remove any that are not firing in practice.

## Sample sessions

_(no sample sessions)_
