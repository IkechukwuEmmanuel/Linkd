"""Lightweight resilience helpers for external API calls.

Provides bounded retries with exponential backoff. Non-retryable client errors
(invalid API key, bad request, auth) are surfaced immediately rather than
retried, so misconfiguration fails fast instead of looping.
"""

import time
import logging

logger = logging.getLogger(__name__)

# Substrings that indicate a permanent client-side error — never worth retrying.
_NON_RETRYABLE = (
    "api key not valid",
    "api_key_invalid",
    "invalid_argument",
    "unauthorized",
    "permission denied",
    "permission_denied",
    "not found",
    "400",
    "401",
    "403",
    "404",
)


def is_retryable(exc: Exception) -> bool:
    msg = str(exc).lower()
    return not any(s in msg for s in _NON_RETRYABLE)


def retry_call(
    fn,
    *,
    attempts: int = 3,
    base_delay: float = 0.5,
    max_delay: float = 8.0,
    label: str = "external call",
):
    """Call ``fn`` with bounded exponential-backoff retries.

    Args:
        fn: zero-arg callable performing the request.
        attempts: maximum number of attempts (>= 1).
        base_delay/max_delay: backoff bounds in seconds.
        label: name used in log messages.

    Returns the result of ``fn``; re-raises the last exception if all attempts
    fail or the error is non-retryable.
    """
    last_exc = None
    for i in range(max(1, attempts)):
        try:
            return fn()
        except Exception as e:  # noqa: BLE001 - we re-raise below
            last_exc = e
            if not is_retryable(e):
                logger.warning(f"{label}: non-retryable error, not retrying: {e}")
                raise
            if i < attempts - 1:
                delay = min(max_delay, base_delay * (2 ** i))
                logger.warning(
                    f"{label}: attempt {i + 1}/{attempts} failed ({e}); "
                    f"retrying in {delay:.1f}s"
                )
                time.sleep(delay)
            else:
                logger.error(f"{label}: all {attempts} attempts failed: {e}")
    raise last_exc
