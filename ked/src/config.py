import os
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, field_validator


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
    
    # CORS configuration - Production-ready
    # Can be set via CORS_ORIGINS environment variable (comma-separated list)
    cors_origins: list = []  # Will be populated by validator or environment
    
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

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, v):
        """Parse CORS origins from environment or provide sensible defaults.
        
        Can be:
        - Comma-separated string: "https://example.com,https://app.example.com"
        - List: ["https://example.com", "https://app.example.com"]
        - Empty/None: Uses defaults based on environment
        """
        if isinstance(v, str):
            # Parse comma-separated string
            if not v or v.lower() == "none":
                return []
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        
        if isinstance(v, list):
            return v
        
        return []

    def get_cors_origins(self) -> list:
        """Get CORS origins with sensible defaults based on environment.
        
        Returns:
            List of allowed CORS origins
        """
        if self.cors_origins:
            # Explicitly configured origins
            return self.cors_origins
        
        # Default origins based on environment
        if self.environment == "production":
            # Production: allow frontend domain only
            # Must be configured via environment variable
            return []
        elif self.environment == "staging":
            # Staging: allow staging domain + localhost
            return ["https://staging.example.com", "http://localhost:3000", "http://localhost:8080"]
        else:
            # Development: allow localhost
            return ["http://localhost:3000", "http://localhost:8080", "http://127.0.0.1:3000"]

settings = Settings()  # loads from .env by default
