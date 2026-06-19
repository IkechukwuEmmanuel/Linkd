-- Migration 005: recordings table updates
--
-- The `recordings` table lives in SUPABASE (not local PostgreSQL). The
-- transcription tasks (src/tasks/transcription_tasks.py) and the ingest
-- contact write-back (src/tasks/contact_tasks.py) write to columns that the
-- original recordings schema (see SUPABASE_SETUP_CHECKLIST.md) does not define.
--
-- Without these columns every transcription silently logs a warning and the
-- /ingest/status/{job_id} endpoint cannot report a contact_id.
--
-- IMPORTANT: Run this in the Supabase SQL editor against your Supabase project,
-- not via the local migration runner.

-- NOTE: /ingest now authenticates with the local JWT (integer user id), so the
-- recordings.user_id column must hold an integer identity (TEXT or BIGINT), not
-- a Supabase auth UUID. If your recordings.user_id is currently a uuid column,
-- migrate it to text/bigint to match the integer users.id used everywhere else.

ALTER TABLE recordings ADD COLUMN IF NOT EXISTS transcript_json JSONB;
ALTER TABLE recordings ADD COLUMN IF NOT EXISTS contact_id INTEGER;
ALTER TABLE recordings ADD COLUMN IF NOT EXISTS event_name VARCHAR(255);

-- Helpful index for status polling by job_id (set during ingest).
CREATE INDEX IF NOT EXISTS idx_recordings_job_id ON recordings (job_id);
