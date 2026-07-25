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
    # Legacy custom-password auth (/auth/login, /register, /reset). OFF by default: the app signs in
    # via Supabase Auth, so these unauthenticated password endpoints are a rollback-only surface.
    # Set AUTH_LEGACY_ENABLED=true ONLY to temporarily re-open them during an emergency rollback.
    auth_legacy_enabled: bool = Field(default=False, alias='AUTH_LEGACY_ENABLED')

    cors_origins: str = Field(default='', alias='CORS_ORIGINS')

    supabase_url: str | None = Field(default=None, alias='SUPABASE_URL')
    supabase_service_role_key: str | None = Field(default=None, alias='SUPABASE_SERVICE_ROLE_KEY')
    # Required for local/HS256 Supabase projects; JWKS covers asymmetric production keys.
    supabase_jwt_secret: str | None = Field(default=None, alias='SUPABASE_JWT_SECRET')
    supabase_jwt_audience: str = Field(default='authenticated', alias='SUPABASE_JWT_AUDIENCE')
    supabase_profile_bucket: str = Field(default='profile-images', alias='SUPABASE_PROFILE_BUCKET')
    max_profile_image_mb: int = Field(default=5, alias='MAX_PROFILE_IMAGE_MB')
    # Hard cap on any request body, enforced at the edge (before buffering) via Content-Length —
    # stops oversized uploads from being received at all. Never below the image cap + headroom.
    max_request_body_mb: int = Field(default=12, alias='MAX_REQUEST_BODY_MB')
    # Global hard cap on group members — no group may exceed this regardless of its own
    # `max_members`. Bounds per-message fan-out cost and abuse.
    group_max_members: int = Field(default=500, alias='GROUP_MAX_MEMBERS')

    # Per-user, per-day abuse limits on authenticated actions (login limits live in Supabase).
    # Tune via env without a code change.
    rate_limit_connection_requests_per_day: int = Field(default=50, alias='RATE_LIMIT_CONNECTION_REQUESTS_PER_DAY')
    rate_limit_group_creates_per_day: int = Field(default=5, alias='RATE_LIMIT_GROUP_CREATES_PER_DAY')
    rate_limit_avatar_uploads_per_day: int = Field(default=10, alias='RATE_LIMIT_AVATAR_UPLOADS_PER_DAY')
    rate_limit_reports_per_day: int = Field(default=20, alias='RATE_LIMIT_REPORTS_PER_DAY')
    rate_limit_group_invites_per_day: int = Field(default=200, alias='RATE_LIMIT_GROUP_INVITES_PER_DAY')

    allowed_email_domains: str = Field(
        default='students.livingstone.edu,livingstone.edu',
        alias='ALLOWED_EMAIL_DOMAINS',
    )

    # WebSocket real-time gateway (Phase 2). redis_url is the seam for multi-instance
    # fan-out later; unused while the gateway runs single-instance (in-memory).
    redis_url: str | None = Field(default=None, alias='REDIS_URL')
    ws_heartbeat_seconds: int = Field(default=25, alias='WS_HEARTBEAT_SECONDS')
    ws_auth_timeout_seconds: int = Field(default=10, alias='WS_AUTH_TIMEOUT_SECONDS')
    ws_idle_timeout_seconds: int = Field(default=90, alias='WS_IDLE_TIMEOUT_SECONDS')
    ws_max_sockets_per_user: int = Field(default=5, alias='WS_MAX_SOCKETS_PER_USER')
    ws_max_frame_bytes: int = Field(default=8192, alias='WS_MAX_FRAME_BYTES')
    ws_send_rate_per_10s: int = Field(default=20, alias='WS_SEND_RATE_PER_10S')
    ws_typing_rate_per_10s: int = Field(default=10, alias='WS_TYPING_RATE_PER_10S')
    ws_subscribe_rate_per_10s: int = Field(default=15, alias='WS_SUBSCRIBE_RATE_PER_10S')
    ws_max_malformed_frames: int = Field(default=10, alias='WS_MAX_MALFORMED_FRAMES')
    ws_outbox_max_size: int = Field(default=256, alias='WS_OUTBOX_MAX_SIZE')

    # Push notifications (FCM). SECRET — set via env/secret, never commit. Absent → push disabled.
    firebase_credentials_json: str | None = Field(default=None, alias='FIREBASE_CREDENTIALS_JSON')
    # Grace before an offline push: absorb Wi-Fi↔cellular handoffs / rapid reconnects.
    push_reconnect_grace_seconds: float = Field(default=3.0, alias='PUSH_RECONNECT_GRACE_SECONDS')

    @property
    def push_enabled(self) -> bool:
        return bool(self.firebase_credentials_json)

    @property
    def environment_slug(self) -> str:
        """Short env token for Redis channel prefixes (lcconnect:<slug>:...)."""
        value = self.environment.lower()
        if value in {'dev', 'development', 'local'}:
            return 'dev'
        if value in {'stage', 'staging'}:
            return 'staging'
        if value in {'prod', 'production'}:
            return 'prod'
        return value

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

    @property
    def allowed_email_domain_set(self) -> set[str]:
        return {item.strip().lower() for item in self.allowed_email_domains.split(',') if item.strip()}

    @property
    def supabase_jwks_url(self) -> str | None:
        if not self.supabase_url:
            return None
        return f'{self.supabase_url.rstrip("/")}/auth/v1/.well-known/jwks.json'


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings = get_settings()
