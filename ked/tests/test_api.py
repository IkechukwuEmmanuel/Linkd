"""API integration tests for auth, contacts, notifications, and isolation."""


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json().get("database") == "ok"


def test_signup_and_me(client, new_user):
    email, headers = new_user
    me = client.get("/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["data"]["email"] == email


def test_signin(client):
    email = f"signin_{__import__('uuid').uuid4().hex[:8]}@example.com"
    assert client.post(
        "/auth/signup", json={"email": email, "password": "secret123"}
    ).status_code in (200, 201)
    r = client.post(
        "/auth/signin", json={"email": email, "password": "secret123"}
    )
    assert r.status_code in (200, 201)
    assert r.json()["token"]


def test_wrong_password_rejected(client):
    email = f"wp_{__import__('uuid').uuid4().hex[:8]}@example.com"
    client.post("/auth/signup", json={"email": email, "password": "secret123"})
    r = client.post(
        "/auth/signin", json={"email": email, "password": "WRONG"}
    )
    assert r.status_code in (400, 401)


def test_requires_auth(client):
    assert client.get("/contacts/").status_code in (401, 403)


def test_contacts_crud(client, auth_headers):
    # create
    r = client.post(
        "/contacts/",
        json={"name": "Ada Lovelace", "company": "AE", "interests": ["math"]},
        headers=auth_headers,
    )
    assert r.status_code in (200, 201), r.text
    cid = r.json()["data"]["id"]

    # list contains it
    r = client.get("/contacts/", headers=auth_headers)
    assert r.status_code == 200
    assert any(c["id"] == cid for c in r.json()["data"])

    # get one
    r = client.get(f"/contacts/{cid}", headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["data"]["name"] == "Ada Lovelace"

    # star
    r = client.post(f"/contacts/{cid}/star", headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["data"]["is_starred"] is True

    # search
    r = client.get("/contacts/search", params={"q": "Ada"}, headers=auth_headers)
    assert r.status_code == 200
    assert any(c["id"] == cid for c in r.json()["data"])

    # delete
    r = client.delete(f"/contacts/{cid}", headers=auth_headers)
    assert r.status_code in (200, 204)

    # gone
    r = client.get("/contacts/", headers=auth_headers)
    assert all(c["id"] != cid for c in r.json()["data"])


def test_tenant_isolation(client):
    import uuid

    def signup():
        email = f"iso_{uuid.uuid4().hex[:8]}@example.com"
        token = client.post(
            "/auth/signup", json={"email": email, "password": "secret123"}
        ).json()["token"]
        return {"Authorization": f"Bearer {token}"}

    h1, h2 = signup(), signup()
    cid = client.post(
        "/contacts/", json={"name": "User1 Secret"}, headers=h1
    ).json()["data"]["id"]

    # user2 must not see user1's contact in list...
    ids2 = [c["id"] for c in client.get("/contacts/", headers=h2).json()["data"]]
    assert cid not in ids2

    # ...nor by direct id fetch
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
    # DEMO_PASSWORD unset in test env -> demo login disabled.
    r = client.post("/auth/demo-signin")
    assert r.status_code == 403


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
    import uuid

    email = f"del_{uuid.uuid4().hex[:8]}@example.com"
    token = client.post(
        "/auth/signup", json={"email": email, "password": "secret123"}
    ).json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    # create some data
    client.post("/contacts/", json={"name": "Doomed"}, headers=headers)
    # delete account
    r = client.delete("/auth/me", headers=headers)
    assert r.status_code in (200, 204)
    # the token's user no longer exists -> /auth/me should 404
    assert client.get("/auth/me", headers=headers).status_code == 404
    # cannot sign in anymore
    assert client.post(
        "/auth/signin", json={"email": email, "password": "secret123"}
    ).status_code in (400, 401)
