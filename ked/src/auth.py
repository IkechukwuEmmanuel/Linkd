"""Supabase-backed authentication.

Supabase Auth is the single source of truth for credentials and sessions. Every
protected request carries a Supabase access token (a JWT issued by Supabase); we
verify it against Supabase and bridge the identity to the integer ``users.id``
used everywhere else in the schema (contacts, personas, RLS, ...).

There is no local password store and no local JWT signing — Supabase owns that.
"""

import logging

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from .config import settings

logger = logging.getLogger(__name__)
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> int:
    """FastAPI dependency: verify the Supabase token and return the local user id.

    Raises 401 on a missing/expired/invalid token.
    """
    user_id = _resolve_supabase_user(credentials.credentials)
    # Bind the user id for Row-Level Security on this request. Runs in the
    # endpoint's execution context so it propagates to the DB session.
    try:
        from . import db
        db.set_current_user_id(user_id)
    except Exception:
        pass
    return user_id


def get_or_create_local_user(email: str, db_session) -> int:
    """Find or create the local ``users`` row for a Supabase identity.

    Supabase is the auth source of truth; the integer ``users.id`` remains the
    primary key used across the schema. The local row stores no usable password.
    """
    from . import models

    email = (email or "").strip().lower()
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Supabase identity is missing an email",
        )
    user = db_session.query(models.User).filter(models.User.email == email).first()
    if user is None:
        user = models.User(email=email, hashed_password="!supabase-managed!")
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        logger.info(f"[user_id={user.id}] Provisioned local user from Supabase identity")
    return user.id


def _resolve_supabase_user(token: str) -> int:
    """Verify a Supabase access token and map it to the local integer user id."""
    from .supabase_client import SupabaseManager
    from . import db as _db

    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        client = SupabaseManager.get_client()
        response = client.auth.get_user(token)
        if not response or not getattr(response, "user", None):
            raise ValueError("invalid Supabase token")
        email = response.user.email
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Supabase token verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    session = _db.SessionLocal()
    try:
        return get_or_create_local_user(email, session)
    finally:
        session.close()


def supabase_user_key(token: str) -> str | None:
    """Best-effort, stable per-user key for rate limiting.

    Decodes the Supabase JWT WITHOUT verifying the signature — we only need a
    stable identifier to bucket requests, not a trust decision (the real
    verification happens in [get_current_user]). Returns None if the token can't
    be parsed, so the caller can fall back to the client IP.
    """
    try:
        payload = jwt.decode(token, options={"verify_signature": False})
        sub = payload.get("sub")
        return f"user:{sub}" if sub else None
    except Exception:
        return None
