import os
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, field_validator, model_validator


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
    
    # JWT configuration - REQUIRED for production
    jwt_secret_key: str = ""  # MUST be set in production
    jwt_expiration_hours: int = 24
    
    # Redis configuration for Celery - supports full URL or individual host/port
    redis_url: str = ""  # Full Redis URL (overrides host/port if provided)
    redis_host: str = "localhost"
    redis_port: int = 6379
    
    # API configuration
    max_upload_size_mb: int = 50  # Maximum file upload size in MB
    request_timeout_seconds: int = 60
    
    # Audio storage configuration
    audio_storage_dir: str = "/data/linkd/users"  # Base directory for user audio files
    
    # CORS configuration
    cors_origins: list = ["http://localhost:3000", "http://localhost:8080"]
    
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

    # Demo account (development convenience). MUST be overridden in production.
    demo_email: str = "demo@linkd.app"
    demo_password: str = ""  # empty => demo login disabled unless set

    @model_validator(mode='after')
    def _validate_production_secrets(self):
        """Fail closed in non-development environments.

        Runs after all fields are populated (unlike the previous per-field
        validator, which could not see `environment` and so never fired).
        """
        if self.environment != 'development':
            if not self.jwt_secret_key:
                raise ValueError(
                    'JWT_SECRET_KEY must be set in non-development environments'
                )
        # Provide a clearly-marked dev fallback only in development.
        if not self.jwt_secret_key:
            self.jwt_secret_key = 'dev-secret-key-change-me'
        return self


settings = Settings()  # loads from .env by default

