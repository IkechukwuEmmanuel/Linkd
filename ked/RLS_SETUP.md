# Row-Level Security (RLS) — tenant isolation

Linkd isolates every user's data at two layers:

1. **Application layer (primary):** every query filters `WHERE user_id = <current user>`.
2. **Database layer (defense-in-depth):** Postgres RLS policies on the per-user
   tables, keyed off the `app.current_user_id` GUC.

## How it works

- `src/db.py` defines `current_user_id_var` (a `ContextVar`). The HTTP auth
  dependency (`auth.get_current_user`) and the Celery contact task set it to the
  authenticated user id.
- An SQLAlchemy `begin` listener copies it into the `app.current_user_id` GUC at
  the start of every transaction (`set_config(..., is_local=true)`).
- `_apply_rls()` enables **and FORCEs** RLS on the per-user tables with a
  fail-closed policy:
  `user_id = NULLIF(current_setting('app.current_user_id', true), '')::int`
  (unset/empty GUC → matches no rows, never errors).

Tables covered: `user_persona`, `interest_nodes`, `conversations`, `jobs`,
`persona_feedback`, `interaction_metrics`, `contacts`, `contact_interactions`,
`notifications`.

## IMPORTANT: RLS only takes effect under a non-superuser role

A **superuser/owner** role bypasses RLS even when it is FORCEd. The default
local role (`linkd`) is a superuser, so the app runs unchanged and isolation is
enforced only at the application layer. To get the database-level guarantee in
production, the **API** must connect as a dedicated **non-superuser** role:

```sql
-- Run once as a superuser/owner:
CREATE ROLE linkd_app LOGIN PASSWORD '<from-secrets-manager>';
GRANT USAGE ON SCHEMA public TO linkd_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO linkd_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO linkd_app;
-- Future tables/sequences:
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO linkd_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO linkd_app;
```

Then point the API at it:

```
DATABASE_URL=postgresql://linkd_app:<password>@<host>:5432/linkd_db
```

## Background workers run privileged

`reminder_tasks` (`send_follow_up_reminders`, `update_relationship_strength`,
`delete_expired_audio`) operate **across all tenants**, which RLS would block
under the app role. Run Celery workers with the **privileged** role
(`linkd`/owner, which bypasses RLS). Schema migrations/`init_backend.py` must
also run as the owner.

## Verified

With `linkd_app` (non-superuser) + FORCE RLS:

| GUC `app.current_user_id` | rows visible in `contacts` |
|---|---|
| `1` | only user 1's |
| `2` | only user 2's |
| unset | none (fail-closed) |
