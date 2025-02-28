from typing import List, Optional
from pydantic_settings import BaseSettings
from pydantic import AnyHttpUrl

class Settings(BaseSettings):
    # Server settings
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    ENVIRONMENT: str = "production"

    # Database settings
    DATABASE_URL: str = "sqlite:///./photoshare.db"

    # Security settings
    SECRET_KEY: str = "your-super-secret-key-change-this-in-production"

    # CORS settings
    ALLOWED_ORIGINS: str = "*"

    # AWS settings
    AWS_ACCESS_KEY_ID: str
    AWS_SECRET_ACCESS_KEY: str
    AWS_DEFAULT_REGION: str = "ap-south-1"  # Default to Mumbai region if not specified

    # Frontend URL settings
    FRONTEND_URL: str = "https://main.d1q28qol42ug2a.amplifyapp.com"  # Default to production URL
    BACKEND_URL: Optional[str] = None  # Will be set based on request

    class Config:
        env_file = ".env"
        case_sensitive = True

    @property
    def cors_origins(self) -> List[str]:
        if self.ENVIRONMENT == "development" or self.ALLOWED_ORIGINS == "*":
            return ["*"]
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

    @property
    def api_url(self) -> str:
        if self.BACKEND_URL:
            return f"{self.BACKEND_URL}/api/v1"
        return "/api/v1"  # Relative URL if BACKEND_URL is not set

settings = Settings()