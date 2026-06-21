"""Schema / DB-object tests against the configured database.

Replaces the previous SQLite-based test, which could not work (the schema uses
pgvector `vector` columns and PostgreSQL RLS). Skips gracefully if the configured
database is not PostgreSQL.
"""

import pytest
from sqlalchemy import text

from src import db


def _is_postgres() -> bool:
    return db.engine.url.get_backend_name().startswith("postgres")


def test_core_tables_exist():
    db.init_db()
    with db.engine.connect() as conn:
        rows = conn.execute(
            text("SELECT tablename FROM pg_tables WHERE schemaname='public'")
            if _is_postgres()
            else text("SELECT name FROM sqlite_master WHERE type='table'")
        ).fetchall()
    names = {r[0] for r in rows}
    for t in ("users", "user_persona", "interest_nodes", "conversations", "contacts"):
        assert t in names


def test_similarity_function_created():
    if not _is_postgres():
        pytest.skip("similarity functions require PostgreSQL")
    db.init_db()
    with db.engine.connect() as conn:
        rows = conn.execute(
            text("SELECT proname FROM pg_proc WHERE proname='compute_top_synapses'")
        ).fetchall()
    assert rows, "compute_top_synapses function should exist after migrations"


def test_rls_forced_on_contacts():
    if not _is_postgres():
        pytest.skip("RLS requires PostgreSQL")
    db.init_db()
    with db.engine.connect() as conn:
        row = conn.execute(
            text("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname='contacts'")
        ).first()
    assert row is not None
    assert row[0] is True and row[1] is True, "contacts must have RLS enabled and forced"
