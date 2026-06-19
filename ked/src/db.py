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


def _apply_rls():
    """Apply row-level security policies.

    Note: These are also defined in the migration files, but we can re-apply them here
    as an extra safety measure.
    """
    policies = [
        (
            "user_persona",
            "user_isolation_user_persona",
            "user_id = current_setting('app.current_user_id')::int",
        ),
        (
            "interest_nodes",
            "user_isolation_interest_nodes",
            "user_id = current_setting('app.current_user_id')::int",
        ),
        (
            "conversations",
            "user_isolation_conversations",
            "user_id = current_setting('app.current_user_id')::int",
        ),
        (
            "jobs",
            "user_isolation_jobs",
            "user_id = current_setting('app.current_user_id')::int",
        ),
        (
            "persona_feedback",
            "user_isolation_persona_feedback",
            "user_id = current_setting('app.current_user_id')::int",
        ),
        (
            "interaction_metrics",
            "user_isolation_interaction_metrics",
            "user_id = current_setting('app.current_user_id')::int",
        ),
    ]

    with engine.connect() as conn:
        for table, policy_name, policy_condition in policies:
            try:
                # Enable RLS on the table
                conn.execute(text(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY;"))
                
                # Try to drop existing policy first (for idempotency)
                try:
                    conn.execute(text(f"DROP POLICY IF EXISTS {policy_name} ON {table};"))
                except Exception:
                    pass  # Policy may not exist
                
                # Create policy
                conn.execute(
                    text(
                        f"CREATE POLICY {policy_name} ON {table} "
                        f"USING ({policy_condition});"
                    )
                )
                conn.commit()
                logger.info(f"Applied RLS policy: {policy_name} on {table}")
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
