from typing import List
from pydantic_settings import BaseSettings
from pydantic import AnyHttpUrl

class Settings(BaseSettings):
    HOST: str
    PORT: int
    ENVIRONMENT: str
    DATABASE_URL: str
    SECRET_KEY: str
    ALLOWED_ORIGINS: str

    class Config:
        env_file = ".env"
        case_sensitive = True

    @property
    def cors_origins(self) -> List[str]:
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]

settings = Settings()