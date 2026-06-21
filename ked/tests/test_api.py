"""API integration tests for auth bridging, contacts, notifications, isolation.

Auth is Supabase-only; the test seam (see conftest) maps an ``X-Test-Email``
header to a local user. Credential endpoints (signup/signin) proxy to Supabase
and so can't be exercised without a live Supabase — their "not configured"
behavior is asserted here, and the real token-verification path is unit-tested
with a mock in ``test_auth.py``.
"""

import uuid


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json().get("database") == "ok"


def test_me_provisions_and_returns_user(client, new_user):
    email, headers = new_user
    me = client.get("/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["data"]["email"] == email


def test_requires_auth(client):
    assert client.get("/contacts/").status_code in (401, 403)


def test_signin_has_no_local_password_fallback(client, monkeypatch):
    # Credentials are validated by Supabase only — there is no local password
    # store. When Supabase is unavailable, the proxy reports 503 rather than
    # silently authenticating anyone.
    from src.supabase_client import SupabaseManager

    def _unavailable(cls):
        raise ValueError("Supabase not configured")

    monkeypatch.setattr(SupabaseManager, "get_client", classmethod(_unavailable))
    r = client.post(
        "/auth/signin", json={"email": "x@example.com", "password": "secret123"}
    )
    assert r.status_code == 503
    assert "token" not in r.json()


def test_contacts_crud(client, auth_headers):
    r = client.post(
        "/contacts/",
        json={"name": "Ada Lovelace", "company": "AE", "interests": ["math"]},
        headers=auth_headers,
    )
    assert r.status_code in (200, 201), r.text
    cid = r.json()["data"]["id"]

    r = client.get("/contacts/", headers=auth_headers)
    assert r.status_code == 200
    assert any(c["id"] == cid for c in r.json()["data"])

    r = client.get(f"/contacts/{cid}", headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["data"]["name"] == "Ada Lovelace"

    r = client.post(f"/contacts/{cid}/star", headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["data"]["is_starred"] is True

    r = client.get("/contacts/search", params={"q": "Ada"}, headers=auth_headers)
    assert r.status_code == 200
    assert any(c["id"] == cid for c in r.json()["data"])

    r = client.delete(f"/contacts/{cid}", headers=auth_headers)
    assert r.status_code in (200, 204)

    r = client.get("/contacts/", headers=auth_headers)
    assert all(c["id"] != cid for c in r.json()["data"])


def test_tenant_isolation(client):
    h1 = {"X-Test-Email": f"iso_{uuid.uuid4().hex[:8]}@example.com"}
    h2 = {"X-Test-Email": f"iso_{uuid.uuid4().hex[:8]}@example.com"}

    cid = client.post(
        "/contacts/", json={"name": "User1 Secret"}, headers=h1
    ).json()["data"]["id"]

    ids2 = [c["id"] for c in client.get("/contacts/", headers=h2).json()["data"]]
    assert cid not in ids2

    r = client.get(f"/contacts/{cid}", headers=h2)
    assert r.status_code in (403, 404)


def test_notifications_empty(client, auth_headers):
    r = client.get("/notifications/", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["unread_count"] == 0
    assert body["data"] == []


def test_insights_summary(client, auth_headers):
    r = client.get("/insights/summary", headers=auth_headers)
    assert r.status_code == 200
    assert "total_contacts" in r.json()["data"]


def test_demo_signin_disabled_by_default(client):
    # DEMO_PASSWORD unset in test env -> demo login disabled (checked before
    # any Supabase call).
    r = client.post("/auth/demo-signin")
    assert r.status_code == 403


def test_supabase_user_bridge_is_idempotent(client):
    # The Supabase->local bridge should find-or-create one user per email
    # (case-insensitive), so repeated logins map to the same integer id.
    from src.auth import get_or_create_local_user
    from src import db as _db

    email = f"sb_{uuid.uuid4().hex[:8]}@example.com"
    session = _db.SessionLocal()
    try:
        uid1 = get_or_create_local_user(email, session)
        uid2 = get_or_create_local_user(email.upper(), session)
        assert uid1 == uid2
    finally:
        session.close()


def test_export_my_data(client, auth_headers):
    client.post(
        "/contacts/", json={"name": "Exported Person"}, headers=auth_headers
    )
    r = client.get("/auth/me/export", headers=auth_headers)
    assert r.status_code == 200
    data = r.json()["data"]
    assert "user" in data and "contacts" in data
    assert any(c["name"] == "Exported Person" for c in data["contacts"])


def test_delete_my_account(client):
    from src import db as _db, models

    email = f"del_{uuid.uuid4().hex[:8]}@example.com"
    headers = {"X-Test-Email": email}
    # Provision the user + some data, then delete the account.
    client.post("/contacts/", json={"name": "Doomed"}, headers=headers)
    r = client.delete("/auth/me", headers=headers)
    assert r.status_code in (200, 204)

    # The local row (and its cascaded children) must be gone. We verify via the
    # DB directly because the next authenticated request would re-provision it
    # (that's why DELETE /me also removes the Supabase identity in production).
    session = _db.SessionLocal()
    try:
        assert (
            session.query(models.User).filter(models.User.email == email).first()
            is None
        )
    finally:
        session.close()
