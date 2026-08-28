from functools import lru_cache
from typing import Self

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    app_name: str = Field(default='LC Connect API', alias='APP_NAME')
    environment: str = Field(default='development', alias='ENVIRONMENT')
    api_v1_prefix: str = Field(default='/api/v1', alias='API_V1_PREFIX')
    database_url: str = Field(alias='DATABASE_URL')

    cors_origins: str = Field(default='', alias='CORS_ORIGINS')

    # Where a Supabase invite email's confirmation link sends the invitee — admin invites (Phase 3)
    # and employer-approval invites (Phase 4) share one Supabase project but land in two different
    # Next.js apps, so each needs its own explicit redirect (never the Supabase dashboard's shared
    # default Site URL, which can only point at one of the two).
    admin_portal_url: str | None = Field(default=None, alias='ADMIN_PORTAL_URL')
    employer_portal_url: str | None = Field(default=None, alias='EMPLOYER_PORTAL_URL')

    supabase_url: str | None = Field(default=None, alias='SUPABASE_URL')
    supabase_service_role_key: str | None = Field(default=None, alias='SUPABASE_SERVICE_ROLE_KEY')
    # Required for local/HS256 Supabase projects; JWKS covers asymmetric production keys.
    supabase_jwt_secret: str | None = Field(default=None, alias='SUPABASE_JWT_SECRET')
    supabase_jwt_audience: str = Field(default='authenticated', alias='SUPABASE_JWT_AUDIENCE')
    # Supabase "Send Email" Auth Hook secret (Dashboard → Authentication → Hooks → Send Email →
    # enable, then copy the generated secret here). Lets EVERY Supabase auth email — including the
    # mobile app's direct signUp/resend/resetPasswordForEmail calls, which never touch this backend
    # otherwise — route through LC Connect's own templates instead of Supabase's own mailer. Unset
    # means the hook endpoint refuses all requests (never processes an unverifiable webhook).
    supabase_send_email_hook_secret: str | None = Field(default=None, alias='SUPABASE_SEND_EMAIL_HOOK_SECRET')
    supabase_profile_bucket: str = Field(default='profile-images', alias='SUPABASE_PROFILE_BUCKET')
    max_profile_image_mb: int = Field(default=5, alias='MAX_PROFILE_IMAGE_MB')
    # Blueprint Bond: a PRIVATE bucket (never public like supabase_profile_bucket) — every read
    # goes through a short-lived signed URL, generated server-side, never a public URL.
    supabase_scholar_bucket: str = Field(default='scholar-private', alias='SUPABASE_SCHOLAR_BUCKET')
    max_resume_mb: int = Field(default=5, alias='MAX_RESUME_MB')
    scholar_signed_url_expires_seconds: int = Field(default=300, alias='SCHOLAR_SIGNED_URL_EXPIRES_SECONDS')
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
    rate_limit_staff_threads_per_day: int = Field(default=200, alias='RATE_LIMIT_STAFF_THREADS_PER_DAY')
    # Per minute, not per day: staff search interactively, but this caps directory scraping.
    rate_limit_recipient_searches_per_minute: int = Field(
        default=60, alias='RATE_LIMIT_RECIPIENT_SEARCHES_PER_MINUTE'
    )
    rate_limit_campus_post_creates_per_day: int = Field(
        default=30, alias='RATE_LIMIT_CAMPUS_POST_CREATES_PER_DAY'
    )
    rate_limit_campus_post_publishes_per_day: int = Field(
        default=20, alias='RATE_LIMIT_CAMPUS_POST_PUBLISHES_PER_DAY'
    )
    rate_limit_scholar_uploads_per_day: int = Field(default=10, alias='RATE_LIMIT_SCHOLAR_UPLOADS_PER_DAY')
    # Resending an invite re-sends a real email every time. Bulk *inviting* is legitimate
    # onboarding, but repeatedly resending to the same person has no high-volume use — so this
    # caps the one shape that is purely an email amplifier.
    rate_limit_invite_resends_per_day: int = Field(default=20, alias='RATE_LIMIT_INVITE_RESENDS_PER_DAY')
    # Anonymous endpoints — keyed on client IP (and, for resets, also on the target email) since
    # there is no signed-in user to key on. Generous enough that a real person retrying never
    # trips them; tight enough to stop inbox-bombing and junk-registration floods.
    rate_limit_employer_registrations_per_hour: int = Field(
        default=5, alias='RATE_LIMIT_EMPLOYER_REGISTRATIONS_PER_HOUR'
    )
    rate_limit_password_resets_per_hour: int = Field(default=10, alias='RATE_LIMIT_PASSWORD_RESETS_PER_HOUR')
    rate_limit_password_resets_per_email_per_hour: int = Field(
        default=5, alias='RATE_LIMIT_PASSWORD_RESETS_PER_EMAIL_PER_HOUR'
    )
    rate_limit_employer_opportunity_submissions_per_day: int = Field(
        default=10, alias='RATE_LIMIT_EMPLOYER_OPPORTUNITY_SUBMISSIONS_PER_DAY'
    )

    allowed_email_domains: str = Field(
        default='students.livingstone.edu,livingstone.edu',
        alias='ALLOWED_EMAIL_DOMAINS',
    )
    # Development/testing only — non-Livingstone emails that may sign in locally.
    # Must be empty in production (validated at startup) — so the DEFAULT must be empty too.
    # A non-empty default made production unbootable even when DEV_TEST_EMAILS was never set in
    # the environment: the validator fired on the baked-in value and the app crashed at import.
    # Opt in explicitly via .env for local work instead; never rely on a source-code default here.
    dev_test_emails: str = Field(default='', alias='DEV_TEST_EMAILS')
    dev_test_email_default_role: str = Field(default='student', alias='DEV_TEST_EMAIL_DEFAULT_ROLE')

    # WebSocket real-time gateway. When REDIS_URL is set, lifespan connects Redis for
    # Pub/Sub fan-out + distributed rate limits; unset keeps single-instance memory paths.
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

    # Soft-deleted messages are hidden from clients immediately; rows (and bodies) are
    # hard-purged after this window by `scripts/purge_soft_deleted_messages.py` (cron).
    message_soft_delete_retention_days: int = Field(
        default=90, alias='MESSAGE_SOFT_DELETE_RETENTION_DAYS'
    )

    # Push notifications (FCM). SECRET — set via env/secret, never commit. Absent → push disabled.
    firebase_credentials_json: str | None = Field(default=None, alias='FIREBASE_CREDENTIALS_JSON')
    # Grace before an offline push: absorb Wi-Fi↔cellular handoffs / rapid reconnects.
    push_reconnect_grace_seconds: float = Field(default=3.0, alias='PUSH_RECONNECT_GRACE_SECONDS')

    # Delegated campus publishing: verified staff may author posts when enabled.
    staff_publishing_enabled: bool = Field(default=True, alias='STAFF_PUBLISHING_ENABLED')

    # Staff-to-anyone messaging: verified staff may message any active user (and be messaged
    # back) without a connection, when enabled.
    staff_messaging_enabled: bool = Field(default=True, alias='STAFF_MESSAGING_ENABLED')

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
    def is_testing(self) -> bool:
        return self.environment.lower() == 'testing'

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in {'prod', 'production'}

    @property
    def dev_test_emails_permitted(self) -> bool:
        return self.is_development or self.is_testing

    @property
    def _dev_test_email_pairs(self) -> list[tuple[str, str | None]]:
        """Parse DEV_TEST_EMAILS entries, each `email` or `email:role` (role optional)."""
        pairs: list[tuple[str, str | None]] = []
        for item in self.dev_test_emails.split(','):
            item = item.strip().lower()
            if not item:
                continue
            if ':' in item:
                email, role = item.split(':', 1)
                pairs.append((email.strip(), role.strip() or None))
            else:
                pairs.append((item, None))
        return pairs

    @property
    def dev_test_email_set(self) -> frozenset[str]:
        return frozenset(email for email, _ in self._dev_test_email_pairs)

    @property
    def dev_test_email_roles(self) -> dict[str, str]:
        """Per-email role overrides (`email:role`); emails without one fall back to the default."""
        return {email: role for email, role in self._dev_test_email_pairs if role}

    @property
    def allowed_email_domain_set(self) -> set[str]:
        return {item.strip().lower() for item in self.allowed_email_domains.split(',') if item.strip()}

    @model_validator(mode='after')
    def _guard_dev_test_emails(self) -> Self:
        if self.dev_test_email_set and self.is_production:
            raise ValueError('DEV_TEST_EMAILS must be empty in production')
        role = self.dev_test_email_default_role.strip().lower()
        if role not in {'student', 'staff'}:
            raise ValueError('DEV_TEST_EMAIL_DEFAULT_ROLE must be student or staff')
        for email, per_role in self.dev_test_email_roles.items():
            if per_role not in {'student', 'staff'}:
                raise ValueError(f'DEV_TEST_EMAILS role for {email} must be student or staff, got {per_role!r}')
        return self

    @property
    def supabase_jwks_url(self) -> str | None:
        if not self.supabase_url:
            return None
        return f'{self.supabase_url.rstrip("/")}/auth/v1/.well-known/jwks.json'


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings = get_settings()
