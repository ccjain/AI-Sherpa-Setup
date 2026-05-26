# AI Sherpa — Data Science / ML Rules

These rules apply to all data science and ML projects. They extend core/CLAUDE.md.

---

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
