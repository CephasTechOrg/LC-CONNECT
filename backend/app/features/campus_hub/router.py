from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_user
from app.features.campus_hub import posts as posts_service
from app.features.campus_hub import resources as resources_service
from app.features.campus_hub import service as directory_service
from app.features.campus_hub.schema import (
    CampusHubOverviewRead,
    CampusPostRead,
    CampusPostSummaryRead,
    CampusResourceRead,
    DirectoryEntryRead,
)
from app.models import User

router = APIRouter(prefix='/campus-hub', tags=['campus-hub'])


@router.get('/overview', response_model=CampusHubOverviewRead)
async def get_overview(
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> CampusHubOverviewRead:
    data = await posts_service.build_overview(db, user=current_user)
    return CampusHubOverviewRead.model_validate(data)


@router.get('/posts', response_model=list[CampusPostSummaryRead])
async def list_posts(
    kind: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    category: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> list[CampusPostSummaryRead]:
    rows = await posts_service.list_posts(
        db,
        user=current_user,
        kind=kind,
        priority=priority,
        category=category,
        limit=limit,
    )
    return [CampusPostSummaryRead.model_validate(row) for row in rows]


@router.get('/posts/{post_id}', response_model=CampusPostRead)
async def get_post(
    post_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> CampusPostRead:
    row = await posts_service.get_post(db, user=current_user, post_id=post_id)
    return CampusPostRead.model_validate(row)


@router.get('/directory', response_model=list[DirectoryEntryRead])
async def list_directory(
    category: str | None = Query(default=None),
    department: str | None = Query(default=None),
    query: str | None = Query(default=None, max_length=120),
    limit: int = Query(default=100, ge=1, le=200),
    _: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> list[DirectoryEntryRead]:
    rows = await directory_service.list_directory(
        db,
        category=category,
        department=department,
        query=query,
        limit=limit,
    )
    return [DirectoryEntryRead.model_validate(row) for row in rows]


@router.get('/directory/{position_id}', response_model=DirectoryEntryRead)
async def get_directory_entry(
    position_id: UUID,
    _: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> DirectoryEntryRead:
    row = await directory_service.get_directory_entry(db, position_id)
    return DirectoryEntryRead.model_validate(row)


@router.get('/resources', response_model=list[CampusResourceRead])
async def list_resources(
    category: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=200),
    _: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> list[CampusResourceRead]:
    rows = await resources_service.list_resources(db, category=category, limit=limit)
    return [CampusResourceRead.model_validate(row) for row in rows]


@router.get('/resources/{resource_id}', response_model=CampusResourceRead)
async def get_resource(
    resource_id: UUID,
    _: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> CampusResourceRead:
    row = await resources_service.get_resource(db, resource_id)
    return CampusResourceRead.model_validate(row)
