import os
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, model_validator


class Settings(BaseSettings):
    model_config = ConfigDict(
        extra="ignore",
        env_file=os.path.join(os.path.dirname(__file__), "..", ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
    )
    
    # Database configuration - REQUIRED
    # Must be set in Railway environment variables or .env file
    # Railway provides this automatically as DATABASE_URL in the PostgreSQL service
    database_url: str
    deepgram_api_key: str
    gemini_api_key: str
    
    # Authentication is Supabase-only. Supabase Auth is the single source of
    # truth; the backend verifies Supabase access tokens and bridges them to the
    # integer users.id used across the schema. Supabase config below is required.

    # Redis configuration for Celery - supports full URL or individual host/port
    redis_url: str = ""  # Full Redis URL (overrides host/port if provided)
    redis_host: str = "localhost"
    redis_port: int = 6379
    
    # API configuration
    max_upload_size_mb: int = 50  # Maximum file upload size in MB
    request_timeout_seconds: int = 60
    
    # Audio storage configuration
    audio_storage_dir: str = "/data/linkd/users"  # Base directory for user audio files
    
    # CORS configuration. Stored as a raw string (comma-separated, the documented
    # env format, or a JSON list) and exposed parsed via `cors_origins_list`.
    # Kept as `str` because pydantic-settings JSON-decodes list-typed env vars at
    # the source level and would crash on a plain comma-separated value.
    cors_origins: str = "http://localhost:3000,http://localhost:8080"

    @property
    def cors_origins_list(self) -> list[str]:
        s = (self.cors_origins or "").strip()
        if not s:
            return []
        if s.startswith("["):
            import json
            try:
                return json.loads(s)
            except Exception:
                pass
        return [o.strip() for o in s.split(",") if o.strip()]
    
    # Rate limiting
    rate_limit_enabled: bool = True
    rate_limit_requests_per_minute: int = 60
    
    # S3 Configuration
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""
    aws_s3_bucket: str = ""
    aws_region: str = "us-east-1"
    
    # Environment
    environment: str = "development"  # "development", "staging", "production"

    # Supabase Configuration - REQUIRED for storage and database
    supabase_url: str = ""  # e.g., https://project.supabase.co
    supabase_anon_key: str = ""  # Public anon key for client-side auth
    supabase_service_role_key: str = ""  # Server-side service role key (optional)

    # Search API (Phase 4)
    serper_api_key: str = ""  # Serper.dev API key for web search

    # Encryption (Phase 4)
    fernet_encryption_key: str = ""  # Optional data encryption key

    # Observability (optional). When set, errors are reported to Sentry.
    sentry_dsn: str = ""

    # Demo account (development convenience). MUST be overridden in production.
    demo_email: str = "demo@linkd.app"
    demo_password: str = ""  # empty => demo login disabled unless set

    @model_validator(mode='after')
    def _validate_production_secrets(self):
        """Fail closed in non-development environments.

        Auth is Supabase-only, so production must have Supabase configured.
        Runs after all fields are populated so it can see `environment`.
        """
        if self.environment != 'development':
            missing = [
                name
                for name, value in (
                    ('SUPABASE_URL', self.supabase_url),
                    ('SUPABASE_ANON_KEY', self.supabase_anon_key),
                )
                if not value
            ]
            if missing:
                raise ValueError(
                    f"{', '.join(missing)} must be set in non-development "
                    f"environments (auth is Supabase-only)"
                )
        return self


settings = Settings()  # loads from .env by default

