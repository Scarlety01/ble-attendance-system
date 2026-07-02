from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "BLE Attendance API"
    environment: str = "development"
    secret_key: str = ""
    algorithm: str = "HS256"
    cors_origins: str = (
        "http://localhost:3000,"
        "http://localhost:5173,"
        "http://127.0.0.1:3000,"
        "http://192.168.10.15:3000,"
        "http://192.168.10.15:5173"
    )

    database_url: str = "postgresql://postgres:1234@db:5432/attendance"
    redis_url: str = "redis://redis:6379/0"
    auto_create_tables: bool = False

    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 7

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @field_validator("secret_key")
    @classmethod
    def validate_secret_key(cls, value: str):
        if value and value not in {
            "change-this-secret",
            "change-this-secret-in-production",
            "replace-with-strong-secret-key",
        }:
            return value

        raise ValueError("SECRET_KEY must be set to a strong non-default value")

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
