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
-- IMPORTANT: Run this in the Supabase SQL editor against your Supabase project.
-- The local migration runner also executes this file, so it uses
-- `ALTER TABLE IF EXISTS` — a harmless no-op locally (where `recordings` does
-- not exist) and effective on Supabase (where it does).
--
-- NOTE: /ingest now authenticates with the local JWT (integer user id), so the
-- recordings.user_id column must hold an integer identity (TEXT or BIGINT), not
-- a Supabase auth UUID. If your recordings.user_id is currently a uuid column,
-- migrate it to text/bigint to match the integer users.id used everywhere else.
--
-- Also run this index manually in Supabase (CREATE INDEX has no "IF EXISTS
-- <table>" guard, so it is omitted from the auto-run statements below):
--   CREATE INDEX IF NOT EXISTS idx_recordings_job_id ON recordings (job_id);

ALTER TABLE IF EXISTS recordings ADD COLUMN IF NOT EXISTS transcript_json JSONB;
ALTER TABLE IF EXISTS recordings ADD COLUMN IF NOT EXISTS contact_id INTEGER;
ALTER TABLE IF EXISTS recordings ADD COLUMN IF NOT EXISTS event_name VARCHAR(255);
