"""Shared rate limiter (slowapi).

Defined in its own module so both main.py and routers can import the same
limiter instance without a circular import. The key function is user-aware: for
authenticated requests it limits per user id (decoded from the JWT), falling
back to the client IP for anonymous requests.
"""

import logging
from slowapi import Limiter
from slowapi.util import get_remote_address
from starlette.requests import Request

from .config import settings

logger = logging.getLogger(__name__)


def rate_limit_key(request: Request) -> str:
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        token = auth.split(" ", 1)[1].strip()
        try:
            from .auth import verify_token

            return f"user:{verify_token(token)}"
        except Exception:
            pass
    return get_remote_address(request)


limiter = Limiter(
    key_func=rate_limit_key,
    enabled=settings.rate_limit_enabled,
)

# Reusable limit string for expensive (external-API-triggering) endpoints.
EXPENSIVE_LIMIT = f"{settings.rate_limit_requests_per_minute}/minute"
