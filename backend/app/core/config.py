from typing import List
from pydantic_settings import BaseSettings
from pydantic import AnyHttpUrl

class Settings(BaseSettings):
    # Server settings
    HOST: str
    PORT: int
    ENVIRONMENT: str

    # Database settings
    DATABASE_URL: str

    # Security settings
    SECRET_KEY: str

    # CORS settings
    ALLOWED_ORIGINS: str

    # AWS settings
    AWS_ACCESS_KEY_ID: str
    AWS_SECRET_ACCESS_KEY: str
    AWS_DEFAULT_REGION: str = "ap-south-1"  # Default to Mumbai region if not specified

    class Config:
        env_file = ".env"
        case_sensitive = True

    @property
    def cors_origins(self) -> List[str]:
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

settings = Settings()