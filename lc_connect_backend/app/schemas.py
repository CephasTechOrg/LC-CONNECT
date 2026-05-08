from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

_LIVINGSTONE_DOMAINS = {'students.livingstone.edu', 'livingstone.edu'}
_ALLOWED_TEST_EMAILS = {
    'cephas.bonsuosei@gmail.com',
    'asiedudev.hub@gmail.com',
    'asieduminta27@gmail.com',
    'auralenx.team@gmail.com',
    'bdoreen889@gmail.com',
}


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)

    @field_validator('email')
    @classmethod
    def must_be_livingstone_email(cls, v: str) -> str:
        if v.lower() in _ALLOWED_TEST_EMAILS:
            return v.lower()
            
        domain = v.lower().split('@')[-1]
        if domain not in _LIVINGSTONE_DOMAINS:
            raise ValueError(
                'Only Livingstone College email addresses are allowed '
                '(@students.livingstone.edu or @livingstone.edu)'
            )
        return v.lower()


class VerifyEmailRequest(BaseModel):
    otp: str = Field(min_length=6, max_length=6)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str = Field(min_length=6, max_length=6)
    new_password: str = Field(min_length=8, max_length=128)


class MessageResponse(BaseModel):
    message: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'


class CurrentUserResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    pronouns: str | None = Field(default=None, max_length=50)
    major: str | None = Field(default=None, max_length=120)
    class_year: int | None = Field(default=None, ge=1900, le=2100)
    country_state: str | None = Field(default=None, max_length=120)
    campus: str | None = Field(default=None, max_length=120)
    bio: str | None = Field(default=None, max_length=500)
    is_hidden: bool | None = None
    allow_messages_from_matches_only: bool | None = None
    show_profile_to_verified_only: bool | None = None
    interests: list[str] | None = None
    languages_spoken: list[str] | None = None
    languages_learning: list[str] | None = None
    looking_for_codes: list[str] | None = None


class ProfilePublic(BaseModel):
    id: UUID
    user_id: UUID
    display_name: str | None
    pronouns: str | None
    major: str | None
    class_year: int | None
    country_state: str | None
    campus: str | None
    bio: str | None
    avatar_url: str | None
    is_hidden: bool
    profile_completed: bool
    interests: list[str]
    languages_spoken: list[str]
    languages_learning: list[str]
    looking_for: list[str]
    looking_for_codes: list[str]


class MyProfileRead(ProfilePublic):
    allow_messages_from_matches_only: bool
    show_profile_to_verified_only: bool
    connection_count: int
    activity_count: int
    message_count: int


class DiscoveryCard(BaseModel):
    profile_id: UUID
    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    major: str | None
    class_year: int | None
    bio: str | None
    interests: list[str]
    languages_spoken: list[str]
    languages_learning: list[str]
    looking_for: list[str]
    looking_for_codes: list[str]
    match_score: int
    match_reasons: list[str]


class ConnectionRequestCreate(BaseModel):
    receiver_id: UUID
    intent: str | None = Field(default=None, max_length=50)
    note: str | None = Field(default=None, max_length=240)


class ConnectionRequestRead(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    intent: str | None
    note: str | None
    status: str
    created_at: datetime


class ConnectionRequestEnriched(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    intent: str | None
    note: str | None
    status: str
    created_at: datetime
    partner_profile: ProfilePublic | None = None


class MatchRead(BaseModel):
    id: UUID
    user_a_id: UUID
    user_b_id: UUID
    created_at: datetime
    partner: ProfilePublic | None = None


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class MessageRead(BaseModel):
    id: UUID
    match_id: UUID
    sender_id: UUID
    body: str
    created_at: datetime
    read_at: datetime | None


class MessageThreadRead(BaseModel):
    match_id: UUID
    partner: ProfilePublic | None
    latest_message: MessageRead | None


class ActivityCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    category: str = Field(max_length=40)
    location: str = Field(min_length=2, max_length=160)
    start_time: datetime
    end_time: datetime | None = None
    max_participants: int | None = Field(default=None, ge=2, le=500)

    @model_validator(mode='after')
    def validate_times(self):
        if self.end_time and self.end_time <= self.start_time:
            raise ValueError('end_time must be after start_time')
        return self


class ActivityRead(BaseModel):
    id: UUID
    creator_id: UUID
    title: str
    description: str | None
    category: str
    location: str
    start_time: datetime
    end_time: datetime | None
    max_participants: int | None
    participant_count: int
    has_joined: bool
    is_cancelled: bool
    created_at: datetime


class ReportCreate(BaseModel):
    reported_user_id: UUID | None = None
    activity_id: UUID | None = None
    reason: str = Field(min_length=3, max_length=80)
    details: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def require_target(self):
        if not self.reported_user_id and not self.activity_id:
            raise ValueError('Provide reported_user_id or activity_id')
        return self


class ReportRead(BaseModel):
    id: UUID
    reporter_id: UUID
    reported_user_id: UUID | None
    activity_id: UUID | None
    reason: str
    details: str | None
    status: str
    created_at: datetime


class AdminUserRead(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_active: bool
    is_verified: bool
    display_name: str | None = None


class SuspendUserRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=240)
