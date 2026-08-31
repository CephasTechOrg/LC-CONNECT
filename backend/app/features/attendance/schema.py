"""Pydantic models for Honors attendance — expanded in Phase 2."""

from __future__ import annotations

from pydantic import BaseModel


class HonorsAttendanceFeatureStatus(BaseModel):
    """Phase 1 stub — confirms feature flag wiring (routes arrive in Phase 2)."""

    enabled: bool
