# Linkd — Production Deployment Runbook

This consolidates the operational requirements introduced across the hardening
work. Follow it top to bottom for a correct, secure deployment.

> ⚠️ The single most important step is **RLS role separation** (step 4). Skipping
> it silently disables database-level tenant isolation.

---

## 1. Prerequisites

- PostgreSQL 16 with the **pgvector** extension.
- Redis (Celery broker + result backend + app cache).
- A Supabase project (audio storage + the `recordings` table).
- API keys: Deepgram, Google Gemini, and (optional) Serper.dev.
- Python 3.12 for the backend; Flutter (stable) for the client.

## 2. Backend dependencies

Use the locked set for reproducible, audited installs:

```bash
cd ked
python3.12 -m venv venv && source venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements.lock      # exact, reproducible
# (requirements.txt holds the high-level/direct deps)
```

`ffmpeg` must be installed as a system binary (audio preprocessing):
`apt-get install -y ffmpeg`.

## 3. Configuration (.env)

Copy `ked/.env.example` to `ked/.env` and set real values. Required in
production (startup fails closed otherwise):

- `DATABASE_URL` — **must point at the non-superuser app role** (see step 4).
- `DEEPGRAM_API_KEY`, `GEMINI_API_KEY`.
- `AUTH_PROVIDER` — `supabase` if the client signs in via Supabase Auth
  (tokens are verified and bridged to a local integer `users.id`); `local`
  uses the built-in JWT flow. Firebase Auth is not used.
- `JWT_SECRET_KEY` — strong random value, required for the `local` provider
  (`python -c "import secrets;print(secrets.token_urlsafe(32))"`).
- `ENVIRONMENT=production`.
- `REDIS_URL` (or `REDIS_HOST`/`REDIS_PORT`).
- Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- Optional: `SENTRY_DSN`, `SERPER_API_KEY`, `AWS_*`, `DEMO_PASSWORD`
  (leave empty to keep `/auth/demo-signin` disabled).

## 4. Database roles & RLS (critical)

`init_backend.py` runs migrations and FORCEs Row-Level Security, but a
**superuser/owner bypasses RLS**. Create a dedicated non-superuser role for the
API so isolation is actually enforced (full detail in `ked/RLS_SETUP.md`):

```sql
CREATE ROLE linkd_app LOGIN PASSWORD '<from-secrets>';
GRANT USAGE ON SCHEMA public TO linkd_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO linkd_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO linkd_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO linkd_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO linkd_app;
```

- **API** connects as `linkd_app` (RLS enforced).
- **Migrations and Celery workers** connect as the privileged owner role
  (workers run cross-tenant jobs that RLS would otherwise block).

## 5. Initialize the schema

Run once as the **owner** role (not `linkd_app`):

```bash
DATABASE_URL=postgresql://<owner>:...@host/linkd_db python init_backend.py
```

This creates tables, the pgvector similarity functions, triggers, and the
FORCEd RLS policies.

### Supabase recordings table

The `recordings` table lives in Supabase, not local Postgres. In the Supabase
SQL editor run `ked/src/migrations/005_recordings_updates.sql` and the index it
documents. Ensure `recordings.user_id` is an integer/text column (not a UUID),
to match the integer `users.id` used everywhere else.

## 6. Run the services

```bash
# API (connects as linkd_app)
uvicorn src.main:app --host 0.0.0.0 --port 8000

# Celery workers (connect as the privileged owner role)
celery -A src.celery_app worker -Q transcription -c 1 --loglevel=info
celery -A src.celery_app worker -Q enrichment --pool=gevent -c 10 --loglevel=info
celery -A src.celery_app worker -Q synthesis,default -c 2 --loglevel=info

# Celery beat (reminders, relationship decay, audio cleanup)
celery -A src.celery_app beat --loglevel=info
```

Health check: `GET /health` returns `{"status":"healthy","database":"ok"}`.

## 7. Mobile client

```bash
cd lin
flutter pub get
flutter build apk \
  --dart-define=API_BASE_URL=https://api.yourdomain.com \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon/publishable key>
# or flutter build ios / appbundle
```

Auth: when `SUPABASE_URL` + `SUPABASE_ANON_KEY` are provided, the client signs
in via **Supabase Auth** and sends the Supabase token to the backend (set
`AUTH_PROVIDER=supabase` there). Without them it falls back to the built-in
local-JWT flow. Firebase Auth is not used. Firebase is only initialized for
messaging/analytics if you configure it (`firebase_options.dart` has
placeholders) — otherwise it is a harmless no-op.

## 8. CI

`.github/workflows/ci.yml` runs the backend test suite (against pgvector+redis
services) plus `flutter analyze`/`flutter test` and a `pip-audit` scan on every
push/PR.

## 9. Still required before GA (not yet done)

- Verify the full voice→contact pipeline with **live** Deepgram/Gemini keys.
- Real Firebase project configuration.
- Decide whether social scraping (LinkedIn/IG/TikTok — ToS-sensitive) ships.
- Cost controls/quotas on Gemini/Deepgram; load testing of the async pipeline.
- Backups + migration versioning (consider Alembic) and a dead-letter queue.
