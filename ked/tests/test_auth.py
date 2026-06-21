"""Unit tests for the real Supabase auth path (mocked Supabase client).

The integration tests use a dependency override that bypasses Supabase; these
exercise ``_resolve_supabase_user`` and the rate-limit key helper directly.
"""

import uuid
import jwt
import pytest
from fastapi import HTTPException

from src import auth as auth_mod
from src.supabase_client import SupabaseManager


class _FakeUser:
    def __init__(self, email):
        self.email = email


class _FakeResp:
    def __init__(self, email):
        self.user = _FakeUser(email)


class _FakeAuth:
    def __init__(self, email=None, raise_=False):
        self._email = email
        self._raise = raise_

    def get_user(self, token):
        if self._raise:
            raise Exception("invalid token")
        return _FakeResp(self._email)


class _FakeClient:
    def __init__(self, auth):
        self.auth = auth


def test_resolve_supabase_user_maps_to_local_id(monkeypatch, client):
    email = f"vt_{uuid.uuid4().hex[:8]}@example.com"
    monkeypatch.setattr(
        SupabaseManager,
        "get_client",
        classmethod(lambda cls: _FakeClient(_FakeAuth(email=email))),
    )
    uid = auth_mod._resolve_supabase_user("any-token")
    uid2 = auth_mod._resolve_supabase_user("any-token")
    assert isinstance(uid, int)
    assert uid == uid2  # same identity -> same local id (idempotent bridge)


def test_resolve_supabase_user_rejects_bad_token(monkeypatch, client):
    monkeypatch.setattr(
        SupabaseManager,
        "get_client",
        classmethod(lambda cls: _FakeClient(_FakeAuth(raise_=True))),
    )
    with pytest.raises(HTTPException) as exc:
        auth_mod._resolve_supabase_user("bad-token")
    assert exc.value.status_code == 401


def test_resolve_supabase_user_rejects_empty_token():
    with pytest.raises(HTTPException) as exc:
        auth_mod._resolve_supabase_user("")
    assert exc.value.status_code == 401


def test_supabase_user_key_decodes_sub():
    token = jwt.encode({"sub": "abc-123"}, "irrelevant-secret", algorithm="HS256")
    assert auth_mod.supabase_user_key(token) == "user:abc-123"


def test_supabase_user_key_handles_garbage():
    assert auth_mod.supabase_user_key("not-a-jwt") is None
