"""Unit tests for the retry/backoff helper."""

import pytest

from src.resilience import retry_call, is_retryable


def test_succeeds_after_transient_failures():
    calls = {"n": 0}

    def flaky():
        calls["n"] += 1
        if calls["n"] < 3:
            raise RuntimeError("temporary network blip")
        return "ok"

    result = retry_call(flaky, attempts=3, base_delay=0, label="test")
    assert result == "ok"
    assert calls["n"] == 3


def test_non_retryable_raises_immediately():
    calls = {"n": 0}

    def bad_key():
        calls["n"] += 1
        raise ValueError("API key not valid. Please pass a valid API key.")

    with pytest.raises(ValueError):
        retry_call(bad_key, attempts=5, base_delay=0, label="test")
    assert calls["n"] == 1  # not retried


def test_exhausts_attempts_then_raises():
    calls = {"n": 0}

    def always_fail():
        calls["n"] += 1
        raise RuntimeError("still down")

    with pytest.raises(RuntimeError):
        retry_call(always_fail, attempts=3, base_delay=0, label="test")
    assert calls["n"] == 3


def test_is_retryable_classification():
    assert is_retryable(RuntimeError("connection reset"))
    assert not is_retryable(RuntimeError("401 Unauthorized"))
    assert not is_retryable(RuntimeError("API_KEY_INVALID"))
