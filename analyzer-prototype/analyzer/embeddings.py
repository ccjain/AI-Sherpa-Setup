"""Lazy-loaded local sentence-transformer.

`make_embeddings_fn()` returns a callable that turns a list of strings
into a 2-D numpy array. The model loads on the first call and is reused
on subsequent calls within the same Python process.
"""
from __future__ import annotations
from typing import Callable
import numpy as np

_MODEL = None
_MODEL_NAME = "BAAI/bge-small-en-v1.5"


def make_embeddings_fn() -> Callable[[list[str]], np.ndarray]:
    def fn(texts: list[str]) -> np.ndarray:
        global _MODEL
        if _MODEL is None:
            from sentence_transformers import SentenceTransformer
            _MODEL = SentenceTransformer(_MODEL_NAME)
        if not texts:
            return np.zeros((0, 0))
        return np.asarray(_MODEL.encode(texts, normalize_embeddings=True))
    return fn
