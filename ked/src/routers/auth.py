"""Authentication router — signup, signin, demo access, token management.

Provides all auth endpoints that the Flutter client expects:
- POST /auth/signup     → create user, return JWT
- POST /auth/signin     → validate credentials, return JWT
- POST /auth/demo-signin → create/retrieve demo account
- POST /auth/refresh    → refresh JWT token
- POST /auth/logout     → client-side token invalidation
- GET  /auth/me         → current user from JWT
"""

import logging
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field, EmailStr
from passlib.context import CryptContext

from .. import models, db
from ..auth import create_access_token, get_current_user
from ..config import settings
from ..exceptions import ValidationError, UnauthorizedError

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["auth"])

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Demo account is configured via settings (env). DEMO_PASSWORD is empty by
# default, which disables demo login unless explicitly set — no hardcoded creds.
DEMO_EMAIL = settings.demo_email
DEMO_PASSWORD = settings.demo_password


# ============================================================================
# Request/Response Models
# ============================================================================

class SignupRequest(BaseModel):
    """Signup request body."""
    email: str = Field(..., min_length=5, max_length=255)
    password: str = Field(..., min_length=6, max_length=128)


class SigninRequest(BaseModel):
    """Signin request body."""
    email: str = Field(..., min_length=5, max_length=255)
    password: str = Field(..., min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    """Token refresh request."""
    token: str


class AuthResponse(BaseModel):
    """Auth response matching Flutter AuthResponse.fromJson expectations."""
    user: dict
    token: str
    is_new_user: bool


# ============================================================================
# Helper Functions
# ============================================================================

def get_db():
    session = db.SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _user_to_dict(user: models.User) -> dict:
    """Convert User ORM object to dict matching Flutter User.fromJson."""
    return {
        "id": user.id,
        "email": user.email,
        "created_at": user.created_at.isoformat() if user.created_at else datetime.utcnow().isoformat(),
    }


def _create_auth_response(user: models.User, is_new_user: bool) -> dict:
    """Create standardized auth response."""
    token = create_access_token(user.id)
    return {
        "user": _user_to_dict(user),
        "token": token,
        "is_new_user": is_new_user,
    }


# ============================================================================
# Endpoints
# ============================================================================

@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def signup(
    request: SignupRequest,
    db_session: Session = Depends(get_db),
):
    """Create a new user account.

    Args:
        request: SignupRequest with email and password

    Returns:
        AuthResponse with user info, JWT token, and is_new_user=True

    Raises:
        ValidationError: If email already exists
    """
    # Check if email already exists
    existing_user = db_session.query(models.User).filter(
        models.User.email == request.email.lower().strip()
    ).first()

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    try:
        # Create user with hashed password
        hashed_pw = pwd_context.hash(request.password)
        user = models.User(
            email=request.email.lower().strip(),
            hashed_password=hashed_pw,
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)

        logger.info(f"[user_id={user.id}] New user created: {user.email}")

        return _create_auth_response(user, is_new_user=True)

    except HTTPException:
        raise
    except Exception as e:
        db_session.rollback()
        logger.error(f"Signup failed for {request.email}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create account",
        )


@router.post("/signin", response_model=AuthResponse)
def signin(
    request: SigninRequest,
    db_session: Session = Depends(get_db),
):
    """Sign in with email and password.

    Args:
        request: SigninRequest with email and password

    Returns:
        AuthResponse with user info, JWT token, and is_new_user=False

    Raises:
        HTTPException: If credentials are invalid
    """
    user = db_session.query(models.User).filter(
        models.User.email == request.email.lower().strip()
    ).first()

    if not user or not pwd_context.verify(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    logger.info(f"[user_id={user.id}] User signed in: {user.email}")

    return _create_auth_response(user, is_new_user=False)


@router.post("/demo-signin", response_model=AuthResponse)
def demo_signin(
    db_session: Session = Depends(get_db),
):
    """Sign in with a demo account. Creates the account if it doesn't exist.

    Returns:
        AuthResponse with demo user info and JWT token
    """
    # Demo login is disabled unless a demo password is explicitly configured.
    if not DEMO_PASSWORD:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Demo login is disabled.",
        )

    # Check if demo user exists
    user = db_session.query(models.User).filter(
        models.User.email == DEMO_EMAIL
    ).first()

    is_new_user = False

    if not user:
        # Create demo user
        hashed_pw = pwd_context.hash(DEMO_PASSWORD)
        user = models.User(
            email=DEMO_EMAIL,
            hashed_password=hashed_pw,
        )
        db_session.add(user)
        db_session.commit()
        db_session.refresh(user)
        is_new_user = True
        logger.info(f"[user_id={user.id}] Demo user created")

    logger.info(f"[user_id={user.id}] Demo sign-in")

    return _create_auth_response(user, is_new_user=is_new_user)


@router.post("/refresh", response_model=AuthResponse)
def refresh_token(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Refresh JWT token using the current valid token.

    Args:
        user_id: Extracted from current JWT token via Depends

    Returns:
        AuthResponse with refreshed JWT token
    """
    user = db_session.query(models.User).filter(
        models.User.id == user_id
    ).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    logger.info(f"[user_id={user_id}] Token refreshed")

    return _create_auth_response(user, is_new_user=False)


@router.post("/logout")
def logout():
    """Logout — client should discard the token.

    Server-side token invalidation is handled by token expiration.
    Client clears local storage on receipt of success response.

    Returns:
        Success confirmation
    """
    return {
        "success": True,
        "message": "Logged out successfully",
    }


@router.get("/me")
def get_me(
    user_id: int = Depends(get_current_user),
    db_session: Session = Depends(get_db),
):
    """Get current authenticated user info.

    Args:
        user_id: Extracted from JWT token

    Returns:
        User info
    """
    user = db_session.query(models.User).filter(
        models.User.id == user_id
    ).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    return {
        "success": True,
        "data": _user_to_dict(user),
    }
