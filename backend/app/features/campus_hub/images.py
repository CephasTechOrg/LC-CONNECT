"""Campus post image attach/remove/reorder — staff authors and admins share this service."""

from __future__ import annotations

from uuid import UUID, uuid4

from fastapi import HTTPException, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.campus_hub import publishing
from app.models import CampusPost, CampusPostImage, User
from app.shared.blocking import run_image, run_sync
from app.shared.image_processing import sanitize_announcement_image
from app.shared.storage import storage_service

MAX_IMAGES = 4


def serialized_images(post: CampusPost) -> list[dict]:
    if 'images' in sa_inspect(post).unloaded:
        return []
    images = sorted(post.images or [], key=lambda img: img.sort_order)
    return [{'id': img.id, 'url': img.public_url, 'sort_order': img.sort_order} for img in images]


async def read_upload(file: UploadFile) -> bytes:
    data = await file.read()
    cap = settings.max_profile_image_mb * 1024 * 1024
    if not data:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Image is required')
    if len(data) > cap:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail='Image is too large',
        )
    return data


async def _load_for_author(
    db: AsyncSession, *, actor: User, post_id: UUID, as_staff: bool
) -> CampusPost:
    post = await publishing.get_post_or_404(db, post_id)
    if as_staff:
        await publishing.require_staff_publisher(db, actor)
        publishing.require_post_owner_or_admin(actor=actor, post=post)
    return post


async def add_image(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    data: bytes,
    as_staff: bool,
) -> CampusPost:
    post = await _load_for_author(db, actor=actor, post_id=post_id, as_staff=as_staff)
    current_count = await _image_count(db, post.id)
    if current_count >= MAX_IMAGES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Announcements can have at most 4 images',
        )
    clean, content_type = await run_image(sanitize_announcement_image, data)
    image_id = uuid4()
    object_path, public_url = await run_sync(
        storage_service.upload_campus_post_image, post.id, image_id, content_type, clean
    )
    db.add(
        CampusPostImage(
            id=image_id,
            post_id=post.id,
            sort_order=current_count,
            object_path=object_path,
            public_url=public_url,
        )
    )
    await db.commit()
    return await _reload(db, post)


async def delete_image(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    image_id: UUID,
    as_staff: bool,
) -> CampusPost:
    post = await _load_for_author(db, actor=actor, post_id=post_id, as_staff=as_staff)
    image = next((img for img in post.images if img.id == image_id), None)
    if image is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Image not found')
    await run_sync(storage_service.delete_campus_post_image, image.object_path)
    remaining = [img for img in post.images if img.id != image_id]
    await db.delete(image)
    await db.flush()
    await _assign_sort_order(db, remaining)
    await db.commit()
    return await _reload(db, post)


async def reorder_images(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    image_ids: list[UUID],
    as_staff: bool,
) -> CampusPost:
    post = await _load_for_author(db, actor=actor, post_id=post_id, as_staff=as_staff)
    current_ids = {img.id for img in post.images}
    if len(image_ids) != len(set(image_ids)) or set(image_ids) != current_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='image_ids must list every image on this post exactly once',
        )
    by_id = {img.id: img for img in post.images}
    ordered = [by_id[image_id] for image_id in image_ids]
    await _assign_sort_order(db, ordered)
    await db.commit()
    return await _reload(db, post)


async def delete_all_for_post(post: CampusPost) -> None:
    """Best-effort storage cleanup before a hard delete (rows cascade with the post)."""
    for img in list(post.images):
        await run_sync(storage_service.delete_campus_post_image, img.object_path)


async def _image_count(db: AsyncSession, post_id: UUID) -> int:
    return int(
        (
            await db.execute(
                select(func.count()).select_from(CampusPostImage).where(CampusPostImage.post_id == post_id)
            )
        ).scalar_one()
    )


async def _reload(db: AsyncSession, post: CampusPost) -> CampusPost:
    post_id = post.id
    db.expire(post)
    return await publishing.get_post_or_404(db, post_id)


async def _assign_sort_order(db: AsyncSession, images: list[CampusPostImage]) -> None:
    """Offset then assign so UniqueConstraint(post_id, sort_order) is never violated mid-update."""
    for img in images:
        img.sort_order = img.sort_order + 10
    await db.flush()
    for order, img in enumerate(images):
        img.sort_order = order
