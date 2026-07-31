"""Admin program-membership verify/revoke workflow — Blueprint Bond Phase 1 foundation."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.features.admin import programs as programs_admin
from app.features.programs.service import list_active_memberships
from app.models import AdminAuditLog, Program, ProgramMembership


async def _program(db, *, slug: str = 'presidential_scholars', name: str = 'Presidential Scholars') -> Program:
    program = Program(slug=slug, name=name)
    db.add(program)
    await db.commit()
    await db.refresh(program)
    return program


async def test_verify_membership_creates_active_and_writes_audit(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)

    membership, user, profile = await programs_admin.verify_membership(
        db, actor=admin, program=program, email=student.email
    )
    assert membership.status == 'active'
    assert membership.verified_by_id == admin.id
    assert membership.verified_at is not None
    assert user.id == student.id
    assert profile.user_id == student.id

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'program_membership.verify',
                AdminAuditLog.target_id == membership.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_verify_membership_duplicate_active_is_409(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)

    await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)

    with pytest.raises(HTTPException) as exc:
        await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)
    assert exc.value.status_code == 409


async def test_verify_membership_reactivates_after_revoke(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)

    first, _, _ = await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)
    await programs_admin.revoke_membership(db, actor=admin, program=program, user_id=student.id, reason=None)

    reactivated, _, _ = await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)
    assert reactivated.id == first.id  # same row, not a duplicate
    assert reactivated.status == 'active'
    assert reactivated.revoked_at is None


async def test_verify_membership_rejects_non_student(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    staff = await factory.user(display_name='Staff Member')
    staff.role = 'staff'
    await db.commit()
    program = await _program(db)

    with pytest.raises(HTTPException) as exc:
        await programs_admin.verify_membership(db, actor=admin, program=program, email=staff.email)
    assert exc.value.status_code == 422


async def test_verify_membership_unknown_email_404(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    program = await _program(db)

    with pytest.raises(HTTPException) as exc:
        await programs_admin.verify_membership(db, actor=admin, program=program, email='nobody@livingstone.edu')
    assert exc.value.status_code == 404


async def test_revoke_membership_sets_revoked_and_writes_audit(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)
    await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)

    revoked = await programs_admin.revoke_membership(
        db, actor=admin, program=program, user_id=student.id, reason='Left the program'
    )
    assert revoked.status == 'revoked'
    assert revoked.revoked_at is not None

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'program_membership.revoke',
                AdminAuditLog.target_id == revoked.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_revoke_membership_not_found_404(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)

    with pytest.raises(HTTPException) as exc:
        await programs_admin.revoke_membership(db, actor=admin, program=program, user_id=student.id, reason=None)
    assert exc.value.status_code == 404


async def test_revoke_already_revoked_membership_is_409(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    program = await _program(db)
    await programs_admin.verify_membership(db, actor=admin, program=program, email=student.email)
    await programs_admin.revoke_membership(db, actor=admin, program=program, user_id=student.id, reason=None)

    with pytest.raises(HTTPException) as exc:
        await programs_admin.revoke_membership(db, actor=admin, program=program, user_id=student.id, reason=None)
    assert exc.value.status_code == 409


async def test_list_memberships_filters_by_status(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    active_student = await factory.user(display_name='Active Scholar')
    revoked_student = await factory.user(display_name='Former Scholar')
    program = await _program(db)

    await programs_admin.verify_membership(db, actor=admin, program=program, email=active_student.email)
    await programs_admin.verify_membership(db, actor=admin, program=program, email=revoked_student.email)
    await programs_admin.revoke_membership(db, actor=admin, program=program, user_id=revoked_student.id, reason=None)

    active_rows = await programs_admin.list_memberships(db, program_id=program.id, status_filter='active')
    assert [user.id for _, user, _ in active_rows] == [active_student.id]

    revoked_rows = await programs_admin.list_memberships(db, program_id=program.id, status_filter='revoked')
    assert [user.id for _, user, _ in revoked_rows] == [revoked_student.id]


async def test_student_sees_only_active_memberships(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Scholar')
    other_program = await _program(db, slug='other_program', name='Other Program')
    scholars_program = await _program(db)

    await programs_admin.verify_membership(db, actor=admin, program=scholars_program, email=student.email)
    await programs_admin.verify_membership(db, actor=admin, program=other_program, email=student.email)
    await programs_admin.revoke_membership(
        db, actor=admin, program=other_program, user_id=student.id, reason=None
    )

    rows = await list_active_memberships(db, student.id)
    assert [program.slug for _, program in rows] == ['presidential_scholars']


async def test_membership_unique_per_user_and_program_at_db_level(db, factory):
    """The unique constraint is what makes `verify_membership`'s reuse-the-row logic safe —
    a raw duplicate insert must fail loudly, not silently create a second active row."""
    student = await factory.user(display_name='Scholar')
    program = await _program(db)

    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    with pytest.raises(IntegrityError):
        await db.commit()
