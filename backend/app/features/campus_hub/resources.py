"""Public campus resources — active evergreen information."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CampusResource


def _resource_row(resource: CampusResource) -> dict:
    return {
        'id': resource.id,
        'category': resource.category,
        'title': resource.title,
        'description': resource.description,
        'location': resource.location,
        'hours': resource.hours,
        'contact_email': resource.contact_email,
        'phone': resource.phone,
        'external_url': resource.external_url,
        'sort_order': resource.sort_order,
    }


async def list_resources(
    db: AsyncSession,
    *,
    category: str | None = None,
    limit: int = 100,
) -> list[dict]:
    stmt = select(CampusResource).where(CampusResource.is_active.is_(True))
    if category:
        stmt = stmt.where(CampusResource.category == category.strip().lower())
    stmt = stmt.order_by(CampusResource.sort_order.asc(), CampusResource.title.asc()).limit(limit)
    resources = (await db.execute(stmt)).scalars().all()
    return [_resource_row(resource) for resource in resources]


async def get_resource(db: AsyncSession, resource_id: UUID) -> dict:
    resource = await db.get(CampusResource, resource_id)
    if resource is None or not resource.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus resource not found')
    return _resource_row(resource)
