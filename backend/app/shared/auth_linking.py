"""Link historical `users` rows to Supabase Auth identities (`auth_user_id`).

Ops use: `python scripts/link_auth_users.py` (from `backend/`, with env loaded).
See `architecture_review/AUTH_USER_LINKING_RUNBOOK.md`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


@dataclass
class LinkingReport:
    linked: list[User] = field(default_factory=list)
    already_linked: int = 0
    deleted_unlinked: int = 0
    missing_in_supabase: list[User] = field(default_factory=list)
    conflicts: list[tuple[User, str]] = field(default_factory=list)  # (user, reason)

    @property
    def active_unlinked(self) -> list[User]:
        return self.missing_in_supabase  # after a link pass, leftovers still need action

    @property
    def ok_for_credential_drop(self) -> bool:
        """True when every *live* account has auth_user_id (tombstones may stay NULL)."""
        return not self.missing_in_supabase and not self.conflicts


def is_live_account(user: User) -> bool:
    return user.deleted_at is None and user.status != 'deleted'


async def load_users(db: AsyncSession) -> list[User]:
    result = await db.execute(select(User).order_by(User.email))
    return list(result.scalars().all())


async def link_existing_auth_users(
    db: AsyncSession,
    *,
    lookup_auth_id,
    apply: bool,
) -> LinkingReport:
    """Match unlinked live users to Supabase Auth by email.

    ``lookup_auth_id(email) -> str | None`` is injected so tests can stub Supabase.
    When ``apply`` is False, no writes are committed (dry-run); callers may still
    inspect the report of what *would* link.
    """
    report = LinkingReport()
    users = await load_users(db)

    for user in users:
        if user.auth_user_id is not None:
            report.already_linked += 1
            continue
        if not is_live_account(user):
            report.deleted_unlinked += 1
            continue

        auth_id = lookup_auth_id(user.email)
        if auth_id is None:
            report.missing_in_supabase.append(user)
            continue

        try:
            uid = UUID(str(auth_id))
        except (TypeError, ValueError):
            report.conflicts.append((user, f'invalid auth id from Supabase: {auth_id!r}'))
            continue

        # Guard: another app user already owns this auth subject.
        clash = (
            await db.execute(
                select(User).where(User.auth_user_id == uid, User.id != user.id)
            )
        ).scalar_one_or_none()
        if clash is not None:
            report.conflicts.append(
                (user, f'auth_user_id {uid} already on user {clash.id} ({clash.email})')
            )
            continue

        if apply:
            user.auth_user_id = uid
        report.linked.append(user)

    if apply and report.linked:
        await db.commit()
    return report
