# Canonical Skill Descriptions — ai-sherpa-<domain>

These exact one-line descriptions go into the `description:` frontmatter field of each `domains/<name>/SKILL.md`. Authored 2026-06-10 alongside `2026-06-10-domain-skills-only-design.md`. Update here AND in the SKILL.md when changing.

| Skill name | Description (single line) |
|---|---|
| `ai-sherpa-ai` | Use when working on any AI / LLM application task — Claude API, OpenAI, Anthropic SDK, RAG, vector database, embeddings, agent orchestration, prompt engineering, evals, MLOps, model training, fine-tuning, LangChain. Provides AI-specific guardrails and effectiveness boundaries. |
| `ai-sherpa-backend` | Use when working on any backend service task — REST API, GraphQL, gRPC, microservice, database, ORM, queue, message broker, auth, session, JWT, server-side, business logic, Node.js, Express, FastAPI, Django, Spring, .NET. Provides backend security guardrails and framework conventions. |
| `ai-sherpa-data` | Use when working on any data engineering / data science task — SQL, NoSQL, dbt, Spark, Airflow, pandas, ETL, data pipeline, data warehouse, data lake, schema migration, data quality, analytics, machine learning model. Provides data-handling guardrails and pipeline conventions. |
| `ai-sherpa-devops` | Use when working on any DevOps / platform / SRE task — Kubernetes, Helm, Terraform, Ansible, CI/CD, GitOps, ArgoCD, observability, Prometheus, Grafana, incident response, on-call, cloud infrastructure, AWS, GCP, Azure. Provides infrastructure-as-code guardrails and operational conventions. |
| `ai-sherpa-embedded` | Use when working on any embedded / firmware / RTOS task — C, C++, Zephyr, FreeRTOS, bare-metal, MCU, microcontroller, board bringup, devicetree, Kconfig, GPIO, sensor, BLE, CAN, USB, flashing, JLink, OpenOCD, MISRA, hardware, peripheral, interrupt. Provides toolchain lookup, hardware constraints, and embedded-specific patterns. |
| `ai-sherpa-frontend` | Use when working on any frontend / UI accessibility / performance task — React, Vue, Angular, Next.js, Svelte, HTML, CSS, Tailwind, shadcn, accessibility, a11y, WCAG, ARIA, Core Web Vitals, responsive design, component library, design system. Provides accessibility guardrails and frontend security rules. |
| `ai-sherpa-uiux` | Use when working on any UI design / UX task — wireframe, mockup, prototype, Figma, design system, design tokens, user research, usability, information architecture, visual design, interaction design, design review. Provides UI/UX design conventions and review patterns. |
| `ai-sherpa-web` | Use when working on any full-stack web task — React, Vue, Angular, Next.js, Node.js, Express, FastAPI, Django, Spring, .NET, HTML, CSS, Tailwind, shadcn, frontend, backend, API endpoint, component, accessibility, UI, form, authentication. Provides full-stack security guardrails, accessibility rules, and framework conventions. |

## Description-writing rule

Each description must enumerate the domain's framework and keyword vocabulary broadly enough that any task in the domain triggers the skill. If a description turns out to under-fire in practice, broaden it in a follow-up PR (Risk #1 in the spec).
