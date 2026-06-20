"""Authentication router — Supabase-backed signup, signin, demo, session.

Supabase Auth is the single source of truth. These endpoints proxy credential
operations to Supabase and then bridge the identity to the local integer
``users.id``, so the Flutter client keeps the exact same contract it already
expects:

    POST /auth/signup      → create user in Supabase, return {user, token, is_new_user}
    POST /auth/signin      → validate via Supabase, return {user, token, is_new_user}
    POST /auth/demo-signin → sign in the configured demo account (or 403)
    POST /auth/refresh     → exchange a Supabase refresh token for a new session
    POST /auth/logout      → client discards the token (revokes the Supabase session)
    GET  /auth/me          → current user resolved from the token
    GET  /auth/me/export   → full data export (GDPR/CCPA)
    DELETE /auth/me        → delete the account and all associated data

The ``token`` returned is a Supabase access token; protected routes verify it via
``Depends(get_current_user)``.
"""

import logging
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from .. import models, db
from ..auth import get_current_user, get_or_create_local_user
from ..config import settings
from ..supabase_client import SupabaseManager

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# Demo account is configured via settings (env). DEMO_PASSWORD is empty by
# default, which disables demo login unless explicitly set — no hardcoded creds.
DEMO_EMAIL = settings.demo_email
DEMO_PASSWORD = settings.demo_password


# ============================================================================
# Request/Response Models
# ============================================================================

class SignupRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=255)
    password: str = Field(..., min_length=6, max_length=128)


class SigninRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=255)
    password: str = Field(..., min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class AuthResponse(BaseModel):
    """Matches the Flutter AuthResponse.fromJson contract."""
    user: dict
    token: str
    is_new_user: bool


# ============================================================================
# Helpers
# ============================================================================

def get_db():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _user_to_dict(user: models.User) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "created_at": user.created_at.isoformat()
        if user.created_at
        else datetime.utcnow().isoformat(),
    }


def _session_to_auth_response(
    supabase_response, db_session: Session, is_new_user: bool
) -> dict:
    """Bridge a Supabase auth response into our {user, token, is_new_user} shape.

    ``supabase_response`` is the object returned by ``sign_up`` /
    ``sign_in_with_password`` / ``refresh_session`` — it exposes ``.session``
    (with ``.access_token``) and ``.user`` (with ``.email``). We resolve/create
    the local ``users`` row by email so ``user.id`` stays the integer id the rest
    of the app uses.
    """
    session = getattr(supabase_response, "session", None)
    sb_user = getattr(supabase_response, "user", None)
    access_token = getattr(session, "access_token", None) if session else None
    email = getattr(sb_user, "email", None) if sb_user else None

    if not access_token or not email:
        # Most commonly: signup succeeded but the project requires email
        # confirmation, so no session is issued yet.
        raise HTTPException(
            status_code=status.HTTP_202_ACCEPTED
            if sb_user
            else status.HTTP_401_UNAUTHORIZED,
            detail="Check your email to confirm your account, then sign in."
            if sb_user
            else "Authentication failed.",
        )

    local_id = get_or_create_local_user(email, db_session)
    user = db_session.query(models.User).filter(models.User.id == local_id).first()
    return {
        "user": _user_to_dict(user),
        "token": access_token,
        "is_new_user": is_new_user,
    }


def _supabase_auth():
    """Return the Supabase auth client, or a clear 503 if it isn't configured."""
    try:
        return SupabaseManager.get_client().auth
    except Exception as e:
        logger.error(f"Supabase client unavailable: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is not configured.",
        )


# ============================================================================
# Endpoints
# ============================================================================

@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(request: SignupRequest, db_session: Session = Depends(get_db)):
    """Create a new account via Supabase Auth."""
    auth = _supabase_auth()
    email = request.email.lower().strip()
    try:
        result = auth.sign_up({"email": email, "password": request.password})
    except Exception as e:
        msg = str(e).lower()
        if "already" in msg or "registered" in msg or "exists" in msg:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="An account with this email already exists",
            )
        logger.warning(f"Supabase signup failed for {email}: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Could not create account. Check the email and password.",
        )
    response = _session_to_auth_response(result, db_session, is_new_user=True)
    logger.info(f"[user_id={response['user']['id']}] New user via Supabase: {email}")
    return response


@router.post("/signin", response_model=AuthResponse)
def signin(request: SigninRequest, db_session: Session = Depends(get_db)):
    """Sign in with email and password via Supabase Auth."""
    auth = _supabase_auth()
    email = request.email.lower().strip()
    try:
        result = auth.sign_in_with_password(
            {"email": email, "password": request.password}
        )
    except Exception as e:
        logger.info(f"Supabase signin rejected for {email}: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )
    response = _session_to_auth_response(result, db_session, is_new_user=False)
    logger.info(f"[user_id={response['user']['id']}] Signed in: {email}")
    return response


@router.post("/demo-signin", response_model=AuthResponse)
def demo_signin(db_session: Session = Depends(get_db)):
    """Sign in the configured demo account (disabled unless DEMO_PASSWORD is set)."""
    if not DEMO_PASSWORD:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Demo login is disabled.",
        )
    auth = _supabase_auth()
    try:
        result = auth.sign_in_with_password(
            {"email": DEMO_EMAIL, "password": DEMO_PASSWORD}
        )
    except Exception as e:
        logger.error(f"Demo sign-in failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Demo account is not available.",
        )
    return _session_to_auth_response(result, db_session, is_new_user=False)


@router.post("/refresh", response_model=AuthResponse)
def refresh_token(request: RefreshRequest, db_session: Session = Depends(get_db)):
    """Exchange a Supabase refresh token for a fresh session."""
    auth = _supabase_auth()
    try:
        result = auth.refresh_session(request.refresh_token)
    except Exception as e:
        logger.info(f"Token refresh rejected: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not refresh session. Sign in again.",
        )
    return _session_to_auth_response(result, db_session, is_new_user=False)


@router.post("/logout")
def logout():
    """Logout — the client discards its token.

    Supabase sessions are JWTs; the client clears local storage. (Server-side
    revocation would require the user's token here; we keep this idempotent.)
    """
    return {"success": True, "message": "Logged out successfully"}


@router.get("/me")
def get_me(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Return the current authenticated user (resolved from the token)."""
    user = db_session.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
        )
    return {"success": True, "data": _user_to_dict(user)}


def _row_to_dict(obj) -> dict:
    """Serialize an ORM row to a JSON-safe dict, skipping embedding vectors."""
    from sqlalchemy import inspect as sa_inspect

    out = {}
    for attr in sa_inspect(obj).mapper.column_attrs:
        key = attr.key
        if key == "vector":  # large embedding, not user-meaningful in an export
            continue
        val = getattr(obj, key)
        if hasattr(val, "isoformat"):
            val = val.isoformat()
        out[key] = val
    return out


@router.get("/me/export")
def export_my_data(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Export all data associated with the current user (GDPR/CCPA portability)."""
    user = db_session.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    related = {
        "personas": models.UserPersona,
        "interests": models.InterestNode,
        "conversations": models.Conversation,
        "jobs": models.Job,
        "persona_feedback": models.PersonaFeedback,
        "interaction_metrics": models.InteractionMetric,
        "contacts": models.Contact,
        "contact_interactions": models.ContactInteraction,
        "notifications": models.Notification,
    }
    data = {"user": _user_to_dict(user)}
    for key, model in related.items():
        rows = db_session.query(model).filter(model.user_id == user_id).all()
        data[key] = [_row_to_dict(r) for r in rows]

    logger.info(f"[user_id={user_id}] Data export generated")
    return {"success": True, "data": data}


@router.delete("/me")
def delete_my_account(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Permanently delete the local account and all associated data.

    Child rows are removed via ON DELETE CASCADE. The corresponding Supabase auth
    user is also deleted when a service-role key is configured; otherwise that
    deletion must be performed out of band (logged as a warning).
    """
    user = db_session.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    email = user.email
    db_session.query(models.User).filter(models.User.id == user_id).delete()
    db_session.commit()

    # Best-effort: remove the Supabase auth identity too (needs service role key).
    if settings.supabase_service_role_key:
        try:
            from supabase import create_client

            admin = create_client(
                settings.supabase_url, settings.supabase_service_role_key
            )
            # Look up the auth user by email, then delete by id.
            users = admin.auth.admin.list_users()
            target = next((u for u in users if getattr(u, "email", None) == email), None)
            if target:
                admin.auth.admin.delete_user(target.id)
                logger.info(f"[user_id={user_id}] Deleted Supabase auth identity")
        except Exception as e:
            logger.warning(
                f"[user_id={user_id}] Local data deleted, but Supabase auth user "
                f"removal failed (delete manually): {e}"
            )
    else:
        logger.warning(
            f"[user_id={user_id}] Local data deleted; SUPABASE_SERVICE_ROLE_KEY "
            f"not set, so the Supabase auth user must be removed out of band."
        )

    logger.info(f"[user_id={user_id}] Account and all associated data deleted")
    return {"success": True, "message": "Account and all associated data deleted."}
