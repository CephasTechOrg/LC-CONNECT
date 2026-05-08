from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    app_name: str = Field(default='LC Connect API', alias='APP_NAME')
    environment: str = Field(default='development', alias='ENVIRONMENT')
    api_v1_prefix: str = Field(default='/api/v1', alias='API_V1_PREFIX')
    database_url: str = Field(alias='DATABASE_URL')

    jwt_secret_key: str = Field(alias='JWT_SECRET_KEY')
    jwt_algorithm: str = Field(default='HS256', alias='JWT_ALGORITHM')
    access_token_expire_minutes: int = Field(default=60 * 24 * 7, alias='ACCESS_TOKEN_EXPIRE_MINUTES')

    cors_origins: str = Field(default='', alias='CORS_ORIGINS')

    supabase_url: str | None = Field(default=None, alias='SUPABASE_URL')
    supabase_service_role_key: str | None = Field(default=None, alias='SUPABASE_SERVICE_ROLE_KEY')
    supabase_profile_bucket: str = Field(default='profile-images', alias='SUPABASE_PROFILE_BUCKET')
    max_profile_image_mb: int = Field(default=5, alias='MAX_PROFILE_IMAGE_MB')

    # Email provider: auto | resend | smtp | console
    email_provider: str = Field(default='auto', alias='EMAIL_PROVIDER')

    # Resend (primary)
    resend_api_key: str | None = Field(default=None, alias='RESEND_API_KEY')
    resend_from_email: str = Field(default='LC Connect <noreply@lcconnect.app>', alias='RESEND_FROM_EMAIL')
    resend_reply_to: str | None = Field(default=None, alias='RESEND_REPLY_TO')

    # SMTP (fallback)
    smtp_host: str = Field(default='smtp.gmail.com', alias='SMTP_HOST')
    smtp_port: int = Field(default=587, alias='SMTP_PORT')
    smtp_username: str | None = Field(default=None, alias='SMTP_USERNAME')
    smtp_password: str | None = Field(default=None, alias='SMTP_PASSWORD')
    smtp_from: str = Field(default='LC Connect <noreply@lcconnect.app>', alias='SMTP_FROM')
    smtp_tls: bool = Field(default=True, alias='SMTP_TLS')

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(',') if item.strip()]

    @property
    def is_development(self) -> bool:
        return self.environment.lower() in {'dev', 'development', 'local'}


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings = get_settings()
