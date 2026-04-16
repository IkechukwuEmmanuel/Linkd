import logging
import uuid
import signal
import sys
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, status, Depends
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from .routers import onboarding, interactions, feedback, jobs, async_interactions, uploads, ingest
from . import db
from .config import settings
from .exceptions import LinkdException, to_http_exception

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Initialize rate limiter with custom key function
def get_rate_limit_key(request: Request):
    """Get rate limit key: prioritize user_id from JWT, fallback to IP."""
    # Try to extract user_id from JWT token (if authenticated)
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        try:
            from .auth import verify_token
            token = auth_header.replace("Bearer ", "")
            user_id = verify_token(token)
            return f"user:{user_id}"
        except:
            pass
    
    # Fallback to IP-based rate limiting
    return f"ip:{get_remote_address(request)}"

limiter = Limiter(key_func=get_rate_limit_key)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic."""
    # Startup: Initialize database
    try:
        db.init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize database: {e}")
        sys.exit(1)
    
    logger.info(f"✓ Linkd backend started ({settings.environment} mode)")
    
    yield
    
    # Shutdown logic
    logger.info("Shutting down Linkd backend...")
    try:
        # Get pool stats before disposal
        pool = db.engine.pool
        logger.info(
            f"✓ Database connection pool stats - "
            f"Size: {pool.size()}, "
            f"Checked out: {pool.checkedout()}"
        )
        
        db.engine.dispose()
        logger.info("✓ Database connection pool closed")
    except Exception as e:
        logger.warning(f"Error closing database connection: {e}")


app = FastAPI(
    title="Linkd Backend API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    openapi_url="/openapi.json",
)

# Add rate limiter to app
app.state.limiter = limiter

# Add rate limit exception handler
@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    """Handle rate limit exceeded."""
    correlation_id = getattr(request.state, "correlation_id", "unknown")
    logger.warning(f"[{correlation_id}] Rate limit exceeded: {exc.detail}")
    return JSONResponse(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        content={
            "error": "Rate limit exceeded",
            "details": {
                "correlation_id": correlation_id,
                "message": exc.detail,
            },
        },
    )

# Add CORS middleware with production-ready configuration
cors_origins = settings.get_cors_origins()

if cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
        allow_headers=["*"],
        expose_headers=["X-Correlation-ID"],
        max_age=3600,  # Cache preflight requests for 1 hour
    )
    logger.info(
        f"CORS enabled for {len(cors_origins)} origin(s): "
        f"{', '.join(cors_origins[:3])}{'...' if len(cors_origins) > 3 else ''}"
    )
else:
    if settings.environment == "production":
        logger.warning(
            "WARNING: No CORS origins configured for production environment. "
            "Set CORS_ORIGINS environment variable to enable CORS. "
            "Format: CORS_ORIGINS=https://app.example.com,https://api.example.com"
        )
    else:
        logger.info(f"CORS disabled (default for {settings.environment} environment)")


# Middleware to attach correlation_id and request logging
@app.middleware("http")
async def add_correlation_id_and_log(request: Request, call_next):
    """Add correlation ID and log HTTP requests."""
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    request.state.correlation_id = correlation_id
    
    # Log request
    logger.info(
        f"[{correlation_id}] {request.method} {request.url.path} - "
        f"Client: {request.client.host if request.client else 'unknown'}"
    )
    
    try:
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        logger.info(f"[{correlation_id}] Response: {response.status_code}")
        return response
    except Exception as e:
        logger.error(
            f"[{correlation_id}] Unhandled exception: {type(e).__name__}: {e}",
            exc_info=True,
        )
        raise


# Global exception handlers
@app.exception_handler(LinkdException)
async def linkd_exception_handler(request: Request, exc: LinkdException):
    """Handle LinkdException."""
    logger.warning(
        f"[{request.state.correlation_id}] {type(exc).__name__}: {exc.message}"
    )
    http_exc = to_http_exception(exc)
    return JSONResponse(
        status_code=http_exc.status_code,
        content=http_exc.detail,
    )


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Handle uncaught exceptions."""
    correlation_id = getattr(request.state, "correlation_id", "unknown")
    logger.error(
        f"[{correlation_id}] Unexpected error: {type(exc).__name__}: {exc}",
        exc_info=True,
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "details": {"correlation_id": correlation_id},
        },
    )


# Include routers
app.include_router(onboarding.router)
app.include_router(interactions.router)
app.include_router(feedback.router)
app.include_router(jobs.router)
app.include_router(async_interactions.router)  # Phase 2: Async workflow endpoints
app.include_router(uploads.router)  # Advanced upload handling with offline support

app.include_router(ingest.router)  # Protected ingest endpoint with Supabase auth

@app.get("/", tags=["health"])
def root():
    """Root endpoint."""
    return {
        "message": "Linkd backend is running",
        "environment": settings.environment,
        "version": "1.0.0",
    }


@app.get("/health", tags=["health"])
def health():
    """Health check endpoint."""
    try:
        # Check database connection
        with db.engine.connect() as conn:
            conn.execute(db.text("SELECT 1"))
        return {
            "status": "healthy",
            "database": "ok",
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "unhealthy",
                "database": "error",
                "error": str(e),
            },
        )


# Graceful shutdown handlers
def signal_handler(sig, frame):
    """Handle shutdown signals."""
    logger.info(f"Received signal {sig}, shutting down...")
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

