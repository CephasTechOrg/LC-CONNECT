"""Campus verification admin endpoints (`/admin/users/{id}/campus-verify`).

Split from `admin/router.py` for size — same `/admin` prefix, unchanged API surface.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import campus_verification as campus_verification_admin
from app.features.admin.schema import RevokeCampusVerificationRequest
from app.models import User

router = APIRouter()


@router.post('/users/{user_id}/campus-verify')
async def campus_verify_user(
    user_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    user = await campus_verification_admin.campus_verify_user(db, user_id, actor_id=actor.id)
    return {'status': 'campus_verified', 'user_id': str(user.id)}


@router.post('/users/{user_id}/revoke-campus-verify')
async def revoke_campus_verification(
    user_id: UUID,
    payload: RevokeCampusVerificationRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    user = await campus_verification_admin.revoke_campus_verification(
        db, user_id, actor_id=actor.id, reason=payload.reason
    )
    return {'status': 'campus_unverified', 'user_id': str(user.id)}
