import os
import re
import logging
from sqlalchemy import create_engine, event, text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

from .config import settings

logger = logging.getLogger(__name__)

# SQLAlchemy database URL
DATABASE_URL = settings.database_url

# Log database connection info (masking sensitive parts)
if DATABASE_URL:
    masked_url = DATABASE_URL.split("@")[-1] if "@" in DATABASE_URL else DATABASE_URL
    logger.info(f"Using PostgreSQL database at {masked_url}")

# create engine with pgvector extension support
engine = create_engine(DATABASE_URL, echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


# ---------------------------------------------------------------------------
# Row-Level Security (RLS) request context
#
# `current_user_id_var` carries the authenticated user id for the current
# request/task. On every transaction we copy it into the Postgres GUC
# `app.current_user_id`, which the RLS policies read. Set via set_current_user_id()
# (auth dependency for HTTP, task wrapper for Celery). When unset, the GUC is
# empty and the (missing_ok) policies match no rows — fail-closed, never error.
#
# NOTE: a superuser/owner DB role BYPASSES RLS even with FORCE enabled. The app
# therefore only gains DB-level isolation when it connects as a NON-superuser
# role (see _apply_rls docstring). The default local role is a superuser, so the
# app keeps working unchanged; the mechanism is exercised by the isolation test.
# ---------------------------------------------------------------------------
import contextvars

current_user_id_var: "contextvars.ContextVar" = contextvars.ContextVar(
    "current_user_id", default=None
)


def set_current_user_id(user_id):
    """Bind the current user id for RLS. Returns a token for optional reset."""
    return current_user_id_var.set(user_id)


def reset_current_user_id(token):
    try:
        current_user_id_var.reset(token)
    except Exception:
        pass


@event.listens_for(engine, "begin")
def _set_rls_user(conn):
    """At each transaction start, push the request's user id into the GUC."""
    uid = current_user_id_var.get()
    val = str(uid) if uid is not None else ""
    try:
        # is_local=true -> scoped to this transaction; reset automatically.
        conn.exec_driver_sql(
            "SELECT set_config('app.current_user_id', %s, true)", (val,)
        )
    except Exception as e:  # never let GUC setup break a transaction
        logger.debug(f"Could not set app.current_user_id GUC: {e}")


# ensure pgvector extension is available when the connection is first created
@event.listens_for(engine, "connect")
def connect(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    try:
        cursor.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        dbapi_connection.commit()
    except Exception as e:
        logger.warning(f"Could not create vector extension: {e}")
        dbapi_connection.rollback()
    finally:
        cursor.close()


def init_db():
    """Initialize the database: create tables, apply RLS, and execute migrations."""
    from . import models  # import models to register them with Base

    # Create all tables first
    Base.metadata.create_all(bind=engine)
    logger.info("Created tables from ORM models")

    # Execute migration SQL files
    _execute_migrations()
    
    # Apply RLS policies
    _apply_rls()
    logger.info("Database initialization complete")


def _split_sql_statements(sql: str) -> list:
    """Split a SQL script into individual statements on top-level semicolons.

    Unlike a naive ``sql.split(";")``, this respects:
      - dollar-quoted strings ($$ ... $$ and $tag$ ... $tag$), so PL/pgSQL
        function/trigger bodies (which contain their own semicolons) stay intact,
      - single-quoted string literals (with '' escapes),
      - line comments (-- ...) and block comments (/* ... */).

    Comment-only / blank fragments are dropped so the executor never receives an
    empty query.
    """
    statements = []
    buf = []
    i, n = 0, len(sql)
    in_line_comment = in_block_comment = in_single = False
    dollar_tag = None  # e.g. "$$" or "$func$"

    while i < n:
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < n else ""

        if in_line_comment:
            buf.append(ch)
            if ch == "\n":
                in_line_comment = False
            i += 1
        elif in_block_comment:
            buf.append(ch)
            if ch == "*" and nxt == "/":
                buf.append(nxt)
                i += 2
                in_block_comment = False
            else:
                i += 1
        elif in_single:
            buf.append(ch)
            if ch == "'":
                if nxt == "'":  # escaped quote
                    buf.append(nxt)
                    i += 2
                    continue
                in_single = False
            i += 1
        elif dollar_tag is not None:
            if ch == "$" and sql.startswith(dollar_tag, i):
                buf.append(dollar_tag)
                i += len(dollar_tag)
                dollar_tag = None
            else:
                buf.append(ch)
                i += 1
        elif ch == "-" and nxt == "-":
            in_line_comment = True
            buf.append(ch)
            i += 1
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            buf.append(ch)
            buf.append(nxt)
            i += 2
        elif ch == "'":
            in_single = True
            buf.append(ch)
            i += 1
        elif ch == "$":
            # Try to read a dollar-quote opening tag: $ [A-Za-z0-9_]* $
            j = i + 1
            while j < n and (sql[j].isalnum() or sql[j] == "_"):
                j += 1
            if j < n and sql[j] == "$":
                dollar_tag = sql[i : j + 1]
                buf.append(dollar_tag)
                i = j + 1
            else:
                buf.append(ch)
                i += 1
        elif ch == ";":
            stmt = "".join(buf).strip()
            if not _is_blank_sql(stmt):
                statements.append(stmt)
            buf = []
            i += 1
        else:
            buf.append(ch)
            i += 1

    tail = "".join(buf).strip()
    if not _is_blank_sql(tail):
        statements.append(tail)
    return statements


def _is_blank_sql(stmt: str) -> bool:
    """True if a statement contains no executable SQL (only comments/whitespace)."""
    if not stmt.strip():
        return True
    no_block = re.sub(r"/\*.*?\*/", "", stmt, flags=re.S)
    no_line = re.sub(r"--[^\n]*", "", no_block)
    return not no_line.strip()


def _execute_migrations():
    """Execute all SQL migration files in the migrations directory."""
    migrations_dir = os.path.join(os.path.dirname(__file__), "migrations")
    if not os.path.isdir(migrations_dir):
        logger.warning(f"Migrations directory not found: {migrations_dir}")
        return

    migration_files = sorted([f for f in os.listdir(migrations_dir) if f.endswith(".sql")])

    with engine.connect() as conn:
        for migration_file in migration_files:
            filepath = os.path.join(migrations_dir, migration_file)
            try:
                with open(filepath, "r") as f:
                    sql_content = f.read()
                # Dollar-quote-aware split so PL/pgSQL bodies stay intact.
                statements = _split_sql_statements(sql_content)
                for statement in statements:
                    conn.execute(text(statement))
                conn.commit()
                logger.info(f"Executed migration: {migration_file}")
            except Exception as e:
                logger.error(f"Error executing migration {migration_file}: {e}")
                conn.rollback()


# Tables isolated per-user via RLS. The fail-closed condition uses the
# missing_ok form of current_setting so an unset/empty GUC yields NULL (matches
# no rows) instead of raising — important for non-superuser connections.
_RLS_CONDITION = "user_id = NULLIF(current_setting('app.current_user_id', true), '')::int"
_RLS_TABLES = [
    "user_persona",
    "interest_nodes",
    "conversations",
    "jobs",
    "persona_feedback",
    "interaction_metrics",
    "contacts",
    "contact_interactions",
    "notifications",
]


def _apply_rls():
    """Apply row-level security policies and FORCE them.

    FORCE ROW LEVEL SECURITY makes even the table owner subject to RLS. Note,
    however, that a *superuser* role still bypasses RLS entirely — so DB-level
    isolation is only active when the application connects as a NON-superuser
    role (e.g. a dedicated ``linkd_app`` role with table privileges but no
    superuser/BYPASSRLS). Background jobs that operate across tenants
    (reminder_tasks) should keep using a privileged role. App-level
    ``WHERE user_id = ?`` filtering remains the primary guard; RLS is
    defense-in-depth.
    """
    with engine.connect() as conn:
        for table in _RLS_TABLES:
            policy_name = f"user_isolation_{table}"
            try:
                conn.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;"))
                conn.execute(text(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY;"))
                conn.execute(text(f"DROP POLICY IF EXISTS {policy_name} ON {table};"))
                conn.execute(
                    text(
                        f"CREATE POLICY {policy_name} ON {table} "
                        f"USING ({_RLS_CONDITION}) WITH CHECK ({_RLS_CONDITION});"
                    )
                )
                conn.commit()
                logger.info(f"Applied + forced RLS policy: {policy_name} on {table}")
            except Exception as e:
                logger.warning(f"Could not apply RLS policy {policy_name}: {e}")
                try:
                    conn.rollback()
                except Exception:
                    pass


# Redis cache for Phase 2 (Celery task states and temporary data)
try:
    import redis
    # Use full URL if provided, otherwise construct from host/port
    if settings.redis_url:
        redis_cache = redis.from_url(
            settings.redis_url,
            db=2,  # Use DB 2 for application cache (0=broker, 1=result backend)
            decode_responses=True,
            socket_connect_timeout=5,
        )
        logger.info(f"Connected to Redis using URL from REDIS_URL")
    else:
        redis_cache = redis.Redis(
            host=settings.redis_host,
            port=settings.redis_port,
            db=2,  # Use DB 2 for application cache (0=broker, 1=result backend)
            decode_responses=True,
            socket_connect_timeout=5,
        )
        logger.info(f"Connected to Redis at {settings.redis_host}:{settings.redis_port}")
    # Test connection
    redis_cache.ping()
except Exception as e:
    logger.warning(f"Could not connect to Redis: {e}. Caching disabled.")
    redis_cache = None
