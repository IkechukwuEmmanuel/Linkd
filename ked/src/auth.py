"""JWT authentication and authorization utilities."""

import logging
from datetime import datetime, timedelta
from typing import Optional
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from .config import settings

logger = logging.getLogger(__name__)
security = HTTPBearer()


class JWTConfig:
    """JWT configuration."""
    algorithm = "HS256"
    
    @classmethod
    def get_secret_key(cls) -> str:
        """Get JWT secret key from settings."""
        if not settings.jwt_secret_key:
            raise ValueError("JWT_SECRET_KEY not configured in environment")
        return settings.jwt_secret_key


def create_access_token(user_id: int, expires_delta: Optional[timedelta] = None) -> str:
    """Create a JWT access token.
    
    Args:
        user_id: User ID to encode in token
        expires_delta: Custom expiration time
        
    Returns:
        Encoded JWT token
    """
    if expires_delta is None:
        expires_delta = timedelta(hours=settings.jwt_expiration_hours)
    
    expire = datetime.utcnow() + expires_delta
    payload = {
        "sub": str(user_id),
        "exp": expire,
        "iat": datetime.utcnow(),
    }
    
    token = jwt.encode(
        payload,
        JWTConfig.get_secret_key(),
        algorithm=JWTConfig.algorithm,
    )
    return token


def verify_token(token: str) -> int:
    """Verify JWT token and return user_id.
    
    Args:
        token: JWT token string
        
    Returns:
        user_id from token
        
    Raises:
        HTTPException: If token is invalid or expired
    """
    try:
        payload = jwt.decode(
            token,
            JWTConfig.get_secret_key(),
            algorithms=[JWTConfig.algorithm],
        )
        user_id: int = int(payload.get("sub"))
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: user_id not found",
            )
        return user_id
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
        )
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )


async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)) -> int:
    """Dependency to extract and verify user_id from JWT token.
    
    Args:
        credentials: Bearer token from request header
        
    Returns:
        user_id
        
    Raises:
        HTTPException: If token is invalid
    """
    token = credentials.credentials
    if settings.auth_provider == "supabase":
        user_id = _resolve_supabase_user(token)
    else:
        user_id = verify_token(token)
    # Bind the user id for Row-Level Security on this request. Runs in the
    # endpoint's execution context so it propagates to the DB session.
    try:
        from . import db
        db.set_current_user_id(user_id)
    except Exception:
        pass
    return user_id


def get_or_create_local_user(email: str, db_session) -> int:
    """Find or create the local users row for a Supabase-authenticated identity.

    Supabase is the auth source of truth; the integer ``users.id`` remains the
    primary key used across the schema (contacts, personas, RLS, ...). The local
    row stores no usable password (auth happens at Supabase).
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
    """Verify a Supabase JWT and map it to the local integer user id."""
    from .supabase_client import SupabaseManager
    from . import db as _db

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
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    session = _db.SessionLocal()
    try:
        return get_or_create_local_user(email, session)
    finally:
        session.close()
