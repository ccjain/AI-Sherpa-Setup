import numpy as np
from analyzer.embeddings import make_embeddings_fn


def test_embeddings_fn_returns_2d_float_array():
    fn = make_embeddings_fn()
    out = fn(["hello world", "goodbye world"])
    assert isinstance(out, np.ndarray)
    assert out.ndim == 2
    assert out.shape[0] == 2
    assert out.shape[1] > 0


def test_embeddings_fn_is_idempotent_within_a_session():
    fn = make_embeddings_fn()
    a = fn(["test"])
    b = fn(["test"])
    np.testing.assert_array_almost_equal(a, b)
