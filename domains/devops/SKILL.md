---
name: ai-sherpa-devops
description: Use when working on any DevOps / platform / SRE task — Kubernetes, Helm, Terraform, Ansible, CI/CD, GitOps, ArgoCD, observability, Prometheus, Grafana, incident response, on-call, cloud infrastructure, AWS, GCP, Azure. Provides infrastructure-as-code guardrails and operational conventions.
---

# AI Sherpa — DevOps / Platform Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

## Always Do (DevOps)

1. Use Infrastructure-as-Code (Terraform, Ansible, Pulumi) — never make manual cloud console changes
2. Estimate blast radius before applying any infrastructure change — state it explicitly
3. Document a rollback plan before deleting or modifying existing infrastructure
4. Store all secrets in a secrets manager (Vault, AWS Secrets Manager, GitHub Secrets) — never in code or config files
5. Tag all cloud resources with environment, owner, and cost-centre

---

## Never Do (DevOps)

1. Hardcode environment-specific values (IP addresses, region names, account IDs, credentials) in IaC files
2. Apply `terraform apply` or equivalent without first running and reviewing `terraform plan`
3. Delete infrastructure (databases, queues, storage buckets) without an explicit rollback plan approved by a human
4. Store secrets in environment variables in CI/CD pipeline YAML files — use the platform's secret store
5. Give IAM roles or service accounts more permissions than they need (principle of least privilege)
6. Add secrets or credentials as plaintext values in `docker-compose.yml` — always use environment variable references (`${VAR_NAME}`) pointing to the platform's secret store

---

## GitHub Actions Specific

- Always pin GitHub Actions to a specific SHA, not a mutable tag (`uses: actions/checkout@abc1234` not `@v3`)
- Never print secrets to workflow logs — use `::add-mask::` for sensitive values
- Store all API keys and tokens as GitHub Secrets — never in workflow YAML

---

## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin includes skills for **Kubernetes**,
**Terraform**, and **Atlassian/Jira** that auto-activate when working with those
tools. No additional install is needed. Mention the tooling explicitly in your prompt
if a skill isn't activating when you expect it to.
