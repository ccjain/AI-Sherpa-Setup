---
name: ai-sherpa-data
description: Use when working on any data engineering / data science task — SQL, NoSQL, dbt, Spark, Airflow, pandas, ETL, data pipeline, data warehouse, data lake, schema migration, data quality, analytics, machine learning model. Provides data-handling guardrails and pipeline conventions.
---

# AI Sherpa — Data Science / ML Rules

These rules apply in addition to the global guidelines in `core/CLAUDE.md`.

## Always Do (Data Science)

1. Check dataset size before loading (`df.shape`, `wc -l`, or file size check) — never load a full dataset without confirming it fits in memory
2. Version data and models alongside code (use DVC, MLflow, or equivalent)
3. Use environment variables or config files for file paths — never hardcode
4. Flag any risk of data leakage between train/test splits when reviewing ML pipelines
5. Document data sources and schema in code comments when they are non-obvious

---

## Never Do (Data Science)

1. Hardcode absolute file paths — use `pathlib.Path` or config variables
2. Commit large data files or model weights to Git — use DVC or cloud storage
3. Use the same data split for both hyperparameter tuning and final evaluation (data leakage)
4. Suppress warnings from ML libraries without understanding their cause
5. Process or load datasets that may contain PII without first asking the developer to confirm the data is anonymized and approved for use

---

## Code Quality

- Always use type hints in Python functions
- Always use `venv` or `poetry` — never install packages globally
- Pin all package versions in `requirements.txt` or `pyproject.toml`
- Prefer reproducible random seeds — set `random.seed()`, `np.random.seed()`, `torch.manual_seed()`

---

## Bundled Stack Skills

The globally installed `fullstack-dev-skills` plugin includes skills for **pandas**,
**Spark**, **Postgres**, **RAG systems**, and **model fine-tuning** that auto-activate
when working with those technologies. No additional install is needed. Mention the
stack explicitly in your prompt if a skill isn't activating when you expect it to.
