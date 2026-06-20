<div align="center">

# Linkd

**AI-powered relationship intelligence — remember everyone you meet.**

![Flutter](https://img.shields.io/badge/Frontend-Flutter%20%7C%20Dart-02569B?logo=flutter)
![FastAPI](https://img.shields.io/badge/Backend-FastAPI%20%7C%20Python%203.12-009688?logo=fastapi)
![Celery](https://img.shields.io/badge/Pipeline-Celery%20%7C%20Redis-37814A?logo=celery)
![Supabase](https://img.shields.io/badge/Data-Supabase%20%7C%20pgvector-3FCF8E?logo=supabase)
![AI](https://img.shields.io/badge/AI-Deepgram%20%7C%20Gemini-FF6F00)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Overview

Linkd turns a quick voice note into a lasting professional memory.

After meeting someone, you record a short note about the conversation. Linkd
transcribes it, extracts the people and details that matter (name, company,
interests, opportunities), and compares them against **your own profile** to
surface where you genuinely overlap — then drafts a thoughtful follow-up.

Instead of scattered notes and forgotten introductions, you get a searchable,
private memory of your network.

> **Privacy first.** Captures are private to the user and isolated at the
> database level with row-level security.

---

## Key Features

| Capability | What it does |
| --- | --- |
| **Voice capture** | Record a short note; Deepgram transcribes it (with speaker diarization for live conversations). |
| **AI relationship profiles** | Gemini extracts name, company, role, interests, opportunities, and a summary into a structured contact card. |
| **Overlap matching** | Contact interests are embedded and ranked against your profile facets with pgvector; Gemini explains the shared ground. |
| **Follow-up intelligence** | A suggested, context-aware follow-up message is drafted for each new contact. |
| **Searchable network memory** | Find anyone by name, company, interest, or event. |
| **Your facets (PEP)** | Your Personal Enrichment Profile, modeled as weighted, confidence-scored facets built from a voice pitch or LinkedIn import. |

---

## Architecture

Linkd is a mono-repo with a Flutter mobile client and a FastAPI backend backed
by an asynchronous Celery pipeline.

```
                         ┌──────────────────────────┐
   Flutter app (lin/) ── │  FastAPI API (ked/)      │
   record + poll         │  • Supabase-token auth   │
                         │  • /ingest, /contacts…   │
                         └──────────┬───────────────┘
                                    │ enqueue (Redis broker)
                                    ▼
                         ┌──────────────────────────┐
                         │  Celery workers (ked/)   │
                         │  1. Deepgram  → transcript│
                         │  2. Gemini    → entities  │
                         │  3. pgvector  → overlap   │
                         │  4. Gemini    → follow-up │
                         └──────────┬───────────────┘
                                    ▼
                    Contact card persisted → client polls
                    /ingest/status/{job_id} for the result
```

**Stack**

- **Frontend** — Flutter / Dart (iOS + Android)
- **API** — FastAPI (Python 3.12), Supabase-token auth, rate limiting, `/health`
- **Async pipeline** — Celery with a Redis broker/result backend
- **Speech-to-text** — Deepgram (`nova-2`)
- **AI extraction & embeddings** — Google Gemini (`gemini-2.0-flash`, `text-embedding-004`)
- **Data** — Supabase (PostgreSQL + `pgvector`); integer `users.id` is the identity everywhere, bridged from the Supabase auth user

---

## Repository Structure

```
Linkd
├── lin/                  # Flutter mobile application
│   └── lib/              # presentation, domain, data layers
├── ked/                  # FastAPI backend + Celery pipeline
│   ├── src/
│   │   ├── routers/      # API endpoints (auth, ingest, contacts, …)
│   │   ├── tasks/        # Celery tasks (transcription, contact, enrichment…)
│   │   ├── services/     # Deepgram, Gemini, pgvector overlap, scrapers
│   │   ├── migrations/   # SQL schema + pgvector similarity procedures
│   │   ├── celery_app.py # broker/queues/routing/beat
│   │   └── main.py       # FastAPI app
│   ├── Dockerfile.api / Dockerfile.worker / Procfile
│   └── requirements-{common,api,worker,dev}.txt
└── .github/workflows/    # CI (backend + Flutter) and Android APK build
```

---

## Prerequisites

- Python **3.12+** and `pip`
- Flutter SDK (run `flutter doctor` to verify)
- A reachable **Redis** instance and a **Supabase** project (PostgreSQL + `pgvector`)
- API keys for **Deepgram** and **Google Gemini**
- Optional: Docker (for the containerized backend) and `ffmpeg` (audio
  preprocessing — bundled in the Docker images)

---

## Getting Started

### 1. Clone

```bash
git clone https://github.com/justicethinker/Linkd.git
cd Linkd
```

### 2. Backend (`ked/`)

```bash
cd ked
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt        # everything, incl. test tooling

cp .env.example .env                        # then fill in real values
```

Required environment variables (see `ked/.env.example` for the full list):

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL (Supabase) connection string |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Supabase Auth (token verification) — **required** |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-side writes past RLS + full account deletion |
| `DEEPGRAM_API_KEY` | Speech-to-text |
| `GEMINI_API_KEY` | Entity extraction + embeddings |
| `REDIS_URL` *or* `REDIS_HOST`/`REDIS_PORT` | Celery broker/result backend |
| `CORS_ORIGINS` | Comma-separated allowed origins (or a JSON list) |

Run the API and the worker (two processes):

```bash
# Terminal 1 — API
uvicorn src.main:app --reload          # http://localhost:8000  (docs at /docs)

# Terminal 2 — Celery workers + beat
bash start_workers.sh
```

> The Celery worker is **not optional**: contact cards are created by the worker.
> `start_workers.sh` consumes the `transcription`, `enrichment`, and `default`
> queues and starts the beat scheduler for follow-up reminders.

### 3. Mobile client (`lin/`)

```bash
cd lin
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

> Use `10.0.2.2` (not `localhost`) to reach a backend on your host machine from
> the Android emulator. Point `API_BASE_URL` at your deployed URL for release builds.

---

## Testing

The backend suite runs against Postgres + Redis (auth is mocked, so no live
Supabase is needed):

```bash
cd ked
docker run -d --name linkd_pg -e POSTGRES_USER=linkd -e POSTGRES_PASSWORD=linkd \
  -e POSTGRES_DB=linkd_db -p 5432:5432 pgvector/pgvector:pg16
docker run -d --name linkd_redis -p 6379:6379 redis:7-alpine

export DATABASE_URL="postgresql://linkd:linkd@localhost:5432/linkd_db" \
       REDIS_HOST=localhost ENVIRONMENT=development \
       DEEPGRAM_API_KEY=dummy GEMINI_API_KEY=dummy
pytest
```

Frontend checks: `cd lin && flutter analyze && flutter test`.

---

## Deployment

The backend ships container images and a `Procfile` for platforms that run one
service per process type (Railway / Render / Fly.io, etc.):

- **`ked/Dockerfile.api`** — the FastAPI service (`web`)
- **`ked/Dockerfile.worker`** — the Celery worker (`worker`), plus a `beat` process

Dependencies are split (`requirements-common/-api/-worker.txt`) so the API image
excludes the worker's heavy scraping stack. The Android release build is produced
per-ABI by `.github/workflows/android-apk.yml` (`arm64-v8a` suits most modern
devices).

---

## Contributing

1. Fork the repository and create a feature branch:
   ```bash
   git checkout -b feature/your-feature
   ```
2. Commit your changes and open a Pull Request.

Please run the backend tests and `flutter analyze` before submitting.

---

## License

Distributed under the **MIT License** — see the `LICENSE` file for details.

## Contact

**Justice Thinker** · justicethinker2@gmail.com · [github.com/justicethinker](https://github.com/justicethinker)
