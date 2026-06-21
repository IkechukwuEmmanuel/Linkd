# Supabase Integration Deployment Checklist

> **Schema model (read first).** Linkd uses a two-database split: relational
> core data lives in **local Postgres** (`users` has an integer `SERIAL` id),
> while `recordings`, `user_profiles`, and the audio storage bucket live in
> **Supabase**. The `/ingest` endpoints authenticate with the **local integer
> JWT** (not a Supabase Auth uuid — see `src/routers/ingest.py` and migration
> `005_recordings_updates.sql`). Therefore the Supabase `user_id` columns are
> `BIGINT`, NOT `uuid references auth.users`. Because the backend uses the
> **service-role key** (which bypasses RLS) and there is no Supabase-Auth user
> context, RLS is enabled as **deny-all** (no `auth.uid()` policies — those
> would be meaningless against integer ids). Audio is stored in the
> **`interactions`** bucket, not `recordings`.
>
> The SQL in Step 3 is already applied to the configured project via the
> Supabase MCP migration `linkd_app_schema_integer_userid`; it is reproduced
> here so the setup is reproducible on a fresh project.

## Step 1: Install Dependencies

```bash
cd /workspaces/Linkd/ked
pip install -r requirements.txt
```

**Verification**:
```bash
python -c "import supabase; print('✓ Supabase installed')"
```

---

## Step 2: Configure Environment Variables

### Local Development (.env file)

```bash
# Verify Supabase Auth tokens and bridge them to local integer user rows.
AUTH_PROVIDER=supabase

# From Supabase Dashboard → Settings → API
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
# service_role is REQUIRED in production: the backend writes storage/DB past
# the deny-all RLS with this key.
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Railway Production

1. Go to **Railway Dashboard**
2. Select your project
3. Go to **Settings → Shared Variables**
4. Add these variables:
   ```
   AUTH_PROVIDER = supabase
   SUPABASE_URL = https://your-project.supabase.co
   SUPABASE_ANON_KEY = <your-anon-key>
   SUPABASE_SERVICE_ROLE_KEY = <your-service-role-key>
   ```

---

## Step 3: Create Supabase Resources

### A. Create Database Tables

Go to **Supabase Dashboard → SQL Editor** and run:

```sql
-- Create user_profiles table.
-- user_id is BIGINT to match the local integer users.id (NOT a Supabase uuid).
create table if not exists user_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id bigint not null,
  email text not null,
  display_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id)
);

-- Create recordings table.
-- user_id is BIGINT (local integer identity). storage_url is nullable: the
-- row is inserted with status 'processing' before the background upload sets
-- it. transcript_json / contact_id / event_name are written by the
-- transcription + contact write-back tasks (see migration 005).
create table if not exists recordings (
  id uuid primary key default gen_random_uuid(),
  user_id bigint not null,
  recording_id uuid not null,
  mode text not null check (mode in ('live', 'recap')),
  duration_seconds integer not null check (duration_seconds > 0),
  file_size integer not null,
  storage_url text,
  status text default 'uploaded' check (status in ('processing', 'uploaded', 'completed', 'failed')),
  metadata jsonb,
  job_id uuid,
  transcript_json jsonb,
  contact_id integer,
  event_name varchar(255),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id, recording_id)
);

-- Create indexes
create index if not exists idx_user_profiles_user_id on user_profiles(user_id);
create index if not exists idx_recordings_user_id on recordings(user_id);
create index if not exists idx_recordings_status on recordings(status);
create index if not exists idx_recordings_created_at on recordings(created_at desc);
create index if not exists idx_recordings_job_id on recordings(job_id);
```

### B. Create Storage Bucket

In **Supabase Dashboard → Storage**:

1. Click **+ New bucket**
2. Name: `interactions`  (this is the source-of-truth audio bucket the
   backend uploads to and deletes from — see `src/routers/ingest.py`)
3. Visibility: **Private**
4. Click **Create bucket**

### C. Enable Row-Level Security

The backend talks to Supabase with the **service-role key**, which bypasses
RLS, and there is no Supabase-Auth user context (auth is local integer JWT).
So RLS is enabled as a **deny-all** safety net: anon/`authenticated` roles get
no access, and only the service role can read/write. There are intentionally
**no `auth.uid()` policies** — `auth.uid()` is a uuid and could never match an
integer `user_id`.

> Note: the project also has an event trigger `public.rls_auto_enable()` that
> automatically enables RLS on any new `public` table, so the `alter table`
> lines below may already be in effect.

In **Supabase Dashboard → SQL Editor**, run:

```sql
-- Enable RLS on tables (deny-all to anon/authenticated; service role bypasses RLS).
alter table user_profiles enable row level security;
alter table recordings enable row level security;
```

If you later migrate the backend to Supabase Auth (uuid identities), revisit
this: change the `user_id` columns to `uuid references auth.users(id)` and add
per-user `auth.uid() = user_id` table policies plus the matching
`storage.objects` policies for the `interactions` bucket.

---

## Step 4: Test the Integration

### A. Start the Backend

```bash
cd /workspaces/Linkd/ked
python -m uvicorn src.main:app --reload
```

Expected output:
```
✓ Linkd backend started (development mode)
✓ Database initialized successfully
```

### B. Test Ingest Service Status (No Auth Required)

```bash
curl http://localhost:8000/ingest/status
```

Expected response:
```json
{
  "success": true,
  "service": "ingest",
  "status": "ready",
  "max_upload_size_mb": 50,
  "supported_formats": ["wav", "mp3", "ogg"]
}
```

### C. Get a Supabase Auth Token

With `AUTH_PROVIDER=supabase` (the production setting), `/ingest` verifies a
**Supabase Auth JWT** and bridges it to the local integer `users.id` by email
(see `_resolve_supabase_user` / `get_or_create_local_user` in `src/auth.py`).
So obtain the token from Supabase Auth, not the backend's local routes.

```python
from supabase import create_client

client = create_client(
    "https://<project>.supabase.co",
    "<anon-key>",
)

# Sign up once (email confirmation may be required by your project's Auth
# settings — confirm the user, or disable "Confirm email" in
# Dashboard -> Authentication -> Providers -> Email for testing), then sign in:
client.auth.sign_up({"email": "you@yourdomain.com", "password": "Password123!"})
resp = client.auth.sign_in_with_password(
    {"email": "you@yourdomain.com", "password": "Password123!"}
)
print(resp.session.access_token)   # <- Bearer token for /ingest
```

The backend verifies this token via `client.auth.get_user(token)`; the first
request for a new email auto-provisions a local `users` row (the integer id
that owns `recordings`/`contacts`/etc.).

> If you instead run with `AUTH_PROVIDER=local`, get the token from the
> backend's own `POST /auth/signup` (returns a `token` field) — the integer id
> is encoded directly in that JWT and no Supabase token is involved.

### D. Test Protected Ingest Endpoint

```bash
# 1. Create a test audio file
ffmpeg -f lavfi -i sine=f=440:d=5 -q:a 9 -acodec libmp3lame -ac 1 -ar 22050 test.wav

# 2. Upload to ingest endpoint
TOKEN="your-supabase-jwt-token"

curl -X POST http://localhost:8000/ingest/audio \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@test.wav" \
  -F "mode=recap" \
  -F "duration_seconds=5"
```

Expected response:
```json
{
  "success": true,
  "recording_id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": 42,
  "storage_url": null,
  "job_id": "660e8400-e29b-41d4-a716-446655440111",
  "message": "Ingest started (uploading + transcription dispatched)"
}
```

`storage_url` is `null` here because the upload runs in the background;
`user_id` is the integer local id. Poll `GET /ingest/status/{job_id}` (or
re-fetch the recording) to see `storage_url` and `status` once the upload and
transcription complete.

### E. Test Authentication Protection

Try without token (should fail with 401):
```bash
curl -X POST http://localhost:8000/ingest/audio \
  -F "file=@test.wav"
```

Expected response:
```json
{
  "detail": "Missing authentication token"
}
```

---

## Step 5: Verify Database & Storage

### A. Check Database Records

In **Supabase Dashboard → SQL Editor**:

```sql
select * from recordings;
```

Should show your uploaded recording with all metadata.

### B. Check Storage Files

In **Supabase Dashboard → Storage → interactions**:

You should see files organized as:
```
interactions/
└── {user_id}/
    └── recordings/
        └── {recording_id}.{ext}
```

---

## Step 6: Deploy to Railway

### A. Add Environment Variables

In Railway Dashboard:

1. Go to your project
2. **Settings → Shared Variables** (or Variables tab)
3. Add:
   ```
   SUPABASE_URL=<from-supabase-dashboard>
   SUPABASE_ANON_KEY=<from-supabase-dashboard>
   SUPABASE_SERVICE_ROLE_KEY=<from-supabase-dashboard>
   ```

### B. Deploy

```bash
git add .
git commit -m "Add Supabase integration with protected ingest endpoint"
git push origin main
```

Railway will automatically deploy.

### C. Verify Production Deployment

```bash
# Get your Railway domain/URL
curl https://your-railway-app.up.railway.app/ingest/status
```

---

## Verification Checklist

- [ ] Supabase library installed (`pip install supabase`)
- [ ] Environment variables configured (SUPABASE_URL, SUPABASE_ANON_KEY)
- [ ] Database tables created (user_profiles, recordings) with BIGINT user_id
- [ ] Storage bucket created (interactions)
- [ ] RLS enabled (deny-all; service-role-only)
- [ ] `/ingest/status` endpoint returns 200 OK
- [ ] `/ingest/audio` endpoint requires authentication (401 without token)
- [ ] Token authentication works (201 with valid token)
- [ ] Files uploaded to Supabase storage
- [ ] Database records created for uploads
- [ ] Railway environment variables configured
- [ ] Production deployment working

---

## Troubleshooting

### "Supabase configuration missing"

```bash
# Check environment variables
echo $SUPABASE_URL
echo $SUPABASE_ANON_KEY

# Verify in .env file
cat .env | grep SUPABASE
```

### "Invalid authentication token"

- Token expired? Get a new one from Supabase auth
- Token from different project? Check URLs match
- Decode token to verify: `jwt.io`

### "Storage permission denied"

- The backend must use the **service-role key** (`SUPABASE_SERVICE_ROLE_KEY`) —
  the anon key cannot write past the deny-all RLS.
- Confirm the `interactions` bucket exists.

### Files not appearing in storage

1. The upload runs in the background, so the initial ingest response has
   `storage_url: null` — re-fetch the recording after a moment.
2. Verify bucket name is `interactions`.
3. Check file path format: `{user_id}/recordings/{recording_id}.{ext}`

---

## Summary

✅ **Components Integrated**:
- Supabase client initialization
- JWT authentication protection
- Storage upload/download/delete (`interactions` bucket)
- Database CRUD operations
- Deny-all RLS (service-role-only) for security
- Protected ingest endpoint (local integer JWT)

✅ **Endpoints Available**:
- `POST /ingest/audio` - Ingest audio with Supabase auth
- `GET /ingest/recording/{id}` - Get recording metadata
- `GET /ingest/recordings` - List user's recordings
- `DELETE /ingest/recording/{id}` - Delete recording
- `GET /ingest/status` - Health check (no auth)

✅ **Ready for Production**:
- All endpoints secured with JWT (local integer identity)
- Database schema (BIGINT user_id) with deny-all RLS
- Private `interactions` storage bucket
- Error handling implemented
- Logging in place

**Next Steps**:
1. Implement frontend Supabase auth integration
2. Create audio recording UI with offline support
3. Setup Celery tasks for audio processing
4. Add metrics/monitoring for storage usage

