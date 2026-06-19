"""Shared pytest fixtures.

These are integration tests: they run the real FastAPI app against the database
configured via DATABASE_URL (a Postgres+pgvector instance locally and in CI).
The app's lifespan creates the schema on startup, so no separate setup is needed.
"""

import uuid
import pytest
from fastapi.testclient import TestClient

from src.main import app


@pytest.fixture(scope="session")
def client():
    # The context manager runs the app lifespan (init_db -> schema/migrations/RLS).
    with TestClient(app) as c:
        yield c


def _unique_email() -> str:
    return f"user_{uuid.uuid4().hex[:10]}@example.com"


@pytest.fixture
def new_user(client):
    """Sign up a fresh user; return (email, auth_headers)."""
    email = _unique_email()
    resp = client.post(
        "/auth/signup", json={"email": email, "password": "secret123"}
    )
    assert resp.status_code in (200, 201), resp.text
    token = resp.json()["token"]
    return email, {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_headers(new_user):
    return new_user[1]
