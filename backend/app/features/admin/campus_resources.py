"""Admin CRUD for evergreen campus resources."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub.schema import CampusResourceCreate, CampusResourceUpdate
from app.models import CampusResource, User
from app.shared.audit import record_audit


def _resource_snapshot(resource: CampusResource) -> dict[str, str | bool | int | None]:
    return {
        'title': resource.title,
        'category': resource.category,
        'is_active': resource.is_active,
        'sort_order': resource.sort_order,
    }


async def get_resource_or_404(db: AsyncSession, resource_id: UUID) -> CampusResource:
    resource = await db.get(CampusResource, resource_id)
    if resource is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus resource not found')
    return resource


async def list_resources(db: AsyncSession, *, limit: int = 200) -> list[CampusResource]:
    return list(
        (
            await db.execute(
                select(CampusResource).order_by(CampusResource.sort_order.asc(), CampusResource.title.asc()).limit(limit)
            )
        ).scalars().all()
    )


async def create_resource(db: AsyncSession, *, actor: User, payload: CampusResourceCreate) -> CampusResource:
    data = payload.model_dump()
    if data.get('external_url') is not None:
        data['external_url'] = str(data['external_url'])
    resource = CampusResource(updated_by_id=actor.id, **data)
    db.add(resource)
    await db.flush()
    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_resource.create',
        target_type='campus_resource',
        target_id=resource.id,
        before_data=None,
        after_data=_resource_snapshot(resource),
    )
    await db.commit()
    await db.refresh(resource)
    return resource


async def update_resource(
    db: AsyncSession,
    *,
    actor: User,
    resource_id: UUID,
    payload: CampusResourceUpdate,
) -> CampusResource:
    resource = await get_resource_or_404(db, resource_id)
    before = _resource_snapshot(resource)
    updates = payload.model_dump(exclude_unset=True)
    if 'external_url' in updates and updates['external_url'] is not None:
        updates['external_url'] = str(updates['external_url'])
    for key, value in updates.items():
        setattr(resource, key, value)
    resource.updated_by_id = actor.id

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_resource.update',
        target_type='campus_resource',
        target_id=resource.id,
        before_data=before,
        after_data=_resource_snapshot(resource),
    )
    await db.commit()
    await db.refresh(resource)
    return resource
