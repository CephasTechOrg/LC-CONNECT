"""Bootstrap role assignment — Campus Hub Phase 1."""

from __future__ import annotations

from uuid import uuid4

from app.features.auth.service import bootstrap_user
from app.models import User
from app.security import SupabaseClaims


def _claims(email: str) -> SupabaseClaims:
    return SupabaseClaims(
        sub=uuid4(),
        email=email,
        role='authenticated',
        aal='aal1',
        email_verified=True,
        raw={},
    )


async def test_bootstrap_assigns_student_role(db):
    user = await bootstrap_user(db, _claims('new.student@students.livingstone.edu'))
    assert user.role == 'student'


async def test_bootstrap_assigns_staff_role(db):
    user = await bootstrap_user(db, _claims('new.prof@livingstone.edu'))
    assert user.role == 'staff'


async def test_bootstrap_syncs_existing_staff_email_from_student_default(db, factory):
    user = await factory.user(display_name='Legacy Staff')
    user.email = 'legacy.staff@livingstone.edu'
    user.role = 'student'
    await db.commit()

    refreshed = await bootstrap_user(db, _claims('legacy.staff@livingstone.edu'))
    assert refreshed.id == user.id
    assert refreshed.role == 'staff'


async def test_bootstrap_does_not_demote_admin(db, factory):
    auth_id = uuid4()
    user = await factory.user(display_name='Admin')
    user.email = 'admin@livingstone.edu'
    user.role = 'admin'
    user.auth_user_id = auth_id
    await db.commit()

    claims = SupabaseClaims(
        sub=auth_id,
        email='admin@livingstone.edu',
        role='authenticated',
        aal='aal1',
        email_verified=True,
        raw={},
    )
    refreshed = await bootstrap_user(db, claims)
    assert refreshed.role == 'admin'


async def test_role_backfill_promotes_staff_domain_students(db, factory):
    user = await factory.user(display_name='Pre-migration')
    user.email = 'old.faculty@livingstone.edu'
    user.role = 'student'
    await db.commit()
    user_id = user.id

    from sqlalchemy import select, text

    await db.execute(
        text(
            """
            UPDATE users
            SET role = 'staff'
            WHERE role = 'student'
              AND lower(split_part(email, '@', 2)) = 'livingstone.edu'
            """
        )
    )
    await db.commit()

    role = (await db.execute(select(User.role).where(User.id == user_id))).scalar_one()
    assert role == 'staff'


async def test_role_backfill_leaves_admin_untouched(db, factory):
    user = await factory.user(display_name='Still Admin')
    user.email = 'boss@livingstone.edu'
    user.role = 'admin'
    await db.commit()
    user_id = user.id

    from sqlalchemy import select, text

    await db.execute(
        text(
            """
            UPDATE users
            SET role = 'staff'
            WHERE role = 'student'
              AND lower(split_part(email, '@', 2)) = 'livingstone.edu'
            """
        )
    )
    await db.commit()

    role = (await db.execute(select(User.role).where(User.id == user_id))).scalar_one()
    assert role == 'admin'
