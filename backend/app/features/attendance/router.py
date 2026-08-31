"""Honors attendance HTTP routes — Phase 2 adds session/check-in endpoints."""

from fastapi import APIRouter

from app.features.attendance.permissions import honors_attendance_enabled
from app.features.attendance.schema import HonorsAttendanceFeatureStatus

router = APIRouter(prefix='/attendance', tags=['attendance'])


@router.get('/honors/status', response_model=HonorsAttendanceFeatureStatus)
async def honors_attendance_status() -> HonorsAttendanceFeatureStatus:
    """Public feature-flag probe (no auth) — lets clients hide UI before Phase 2 APIs land."""
    return HonorsAttendanceFeatureStatus(enabled=honors_attendance_enabled())
