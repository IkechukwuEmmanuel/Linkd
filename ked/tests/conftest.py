"""Shared pytest fixtures.

These are integration tests against the database configured via DATABASE_URL (a
Postgres+pgvector instance locally and in CI). The app's lifespan creates the
schema on startup, so no separate setup is needed.

Auth is Supabase-only, and CI has no live Supabase, so we override the
``get_current_user`` dependency with a test seam: requests carry an
``X-Test-Email`` header, which is find-or-created into a local ``users`` row
(exactly what the real Supabase→local bridge does) and bound for RLS. The real
Supabase verification path is covered separately in ``test_auth.py`` with a
mocked client.
"""

import uuid
import pytest
from fastapi import Header, HTTPException, status
from fastapi.testclient import TestClient

from src.main import app
from src import db
from src.auth import get_current_user, get_or_create_local_user


def _test_current_user(x_test_email: str = Header(default=None)) -> int:
    """Stand-in for get_current_user keyed by the X-Test-Email header."""
    if not x_test_email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated"
        )
    session = db.SessionLocal()
    try:
        user_id = get_or_create_local_user(x_test_email, session)
    finally:
        session.close()
    db.set_current_user_id(user_id)  # bind for Row-Level Security
    return user_id


@pytest.fixture(scope="session")
def client():
    # The context manager runs the app lifespan (init_db -> schema/migrations/RLS).
    app.dependency_overrides[get_current_user] = _test_current_user
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.pop(get_current_user, None)


def _unique_email() -> str:
    return f"user_{uuid.uuid4().hex[:10]}@example.com"


@pytest.fixture
def new_user(client):
    """Provision a fresh user; return (email, auth_headers)."""
    email = _unique_email()
    headers = {"X-Test-Email": email}
    # Touch a protected endpoint so the local user row is provisioned.
    assert client.get("/auth/me", headers=headers).status_code == 200
    return email, headers


@pytest.fixture
def auth_headers(new_user):
    return new_user[1]
