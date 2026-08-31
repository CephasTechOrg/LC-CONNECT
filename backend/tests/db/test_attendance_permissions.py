"""Honors attendance permission helpers — Phase 1."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.features.attendance.permissions import (
    ensure_honors_attendance_enabled,
    is_honors_student,
)
from app.features.attendance.service import get_honors_program_id
from app.models import AdminMembership, Program, ProgramMembership


async def _honors_program(db) -> Program:
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.commit()
    await db.refresh(program)
    return program


async def test_is_honors_student_true_when_active_membership(db, factory):
    student = await factory.user(display_name='Scholar')
    program = await _honors_program(db)
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    assert await is_honors_student(db, student.id) is True


async def test_is_honors_student_false_without_membership(db, factory):
    student = await factory.user(display_name='Plain Student')
    await _honors_program(db)

    assert await is_honors_student(db, student.id) is False


async def test_is_honors_student_false_when_revoked(db, factory):
    student = await factory.user(display_name='Revoked Scholar')
    program = await _honors_program(db)
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='revoked'))
    await db.commit()

    assert await is_honors_student(db, student.id) is False


async def test_get_honors_program_id_resolves_seeded_slug(db):
    program = await _honors_program(db)
    assert await get_honors_program_id(db) == program.id


def test_ensure_honors_attendance_enabled_raises_when_flag_off(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, 'honors_attendance_enabled', False)
    with pytest.raises(HTTPException) as exc:
        ensure_honors_attendance_enabled()
    assert exc.value.status_code == 404


def test_ensure_honors_attendance_enabled_passes_when_flag_on(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, 'honors_attendance_enabled', True)
    ensure_honors_attendance_enabled()


async def test_honors_admin_membership_exists_for_instructor_gate(db, factory):
    """Document the instructor gate: honors_admin scope on AdminMembership (not a new table)."""
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    db.add(AdminMembership(user_id=admin.id, role='honors_admin'))
    await db.commit()

    row = (
        await db.execute(
            AdminMembership.__table__.select().where(
                AdminMembership.user_id == admin.id, AdminMembership.role == 'honors_admin'
            )
        )
    ).first()
    assert row is not None
