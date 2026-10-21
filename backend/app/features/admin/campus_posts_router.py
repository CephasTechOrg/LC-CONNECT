"""Admin campus-post endpoints (`/admin/campus-posts/...`).

Split out of `admin/router.py` so that file stays under the 600-line hard cap once image
upload handlers land. Mounted back onto the same `/admin` prefix; the API surface for the
existing CRUD routes is unchanged.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, File, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import campus_posts as posts_admin
from app.features.admin.schema import CampusPostAdminRead
from app.features.campus_hub import images as post_images
from app.features.campus_hub import publishing
from app.features.campus_hub.schema import CampusPostCreate, CampusPostImageReorder, CampusPostUpdate
from app.models import User
from app.shared.rate_limit import campus_post_image_upload_limit

router = APIRouter()


@router.get('/campus-posts', response_model=list[CampusPostAdminRead])
async def list_campus_posts(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[CampusPostAdminRead]:
    posts = await posts_admin.list_posts(db)
    return [posts_admin.to_admin_read(post) for post in posts]


@router.post('/campus-posts', response_model=CampusPostAdminRead, status_code=201)
async def create_campus_post(
    payload: CampusPostCreate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.create_post(db, actor=actor, payload=payload)
    return posts_admin.to_admin_read(post)


@router.patch('/campus-posts/{post_id}', response_model=CampusPostAdminRead)
async def update_campus_post(
    post_id: UUID,
    payload: CampusPostUpdate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.update_post(db, actor=actor, post_id=post_id, payload=payload)
    return posts_admin.to_admin_read(post)


@router.post('/campus-posts/{post_id}/publish', response_model=CampusPostAdminRead)
async def publish_campus_post(
    post_id: UUID,
    background_tasks: BackgroundTasks,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.publish_post(db, actor=actor, post_id=post_id)
    # Only fan out push for posts that are live now — scheduled posts wait for a future job.
    if publishing.should_push_on_publish(post):
        background_tasks.add_task(publishing.push_published_post, post.id)
    return posts_admin.to_admin_read(post)


@router.post('/campus-posts/{post_id}/archive', response_model=CampusPostAdminRead)
async def archive_campus_post(
    post_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.archive_post(db, actor=actor, post_id=post_id)
    return posts_admin.to_admin_read(post)


@router.delete('/campus-posts/{post_id}')
async def delete_campus_post(
    post_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    await posts_admin.delete_post(db, actor=actor, post_id=post_id)
    return {'status': 'deleted', 'post_id': str(post_id)}


@router.post('/campus-posts/{post_id}/images', response_model=CampusPostAdminRead, status_code=201)
async def upload_campus_post_image(
    post_id: UUID,
    file: UploadFile = File(...),
    actor: User = Depends(campus_post_image_upload_limit),
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    data = await post_images.read_upload(file)
    post = await post_images.add_image(db, actor=actor, post_id=post_id, data=data, as_staff=False)
    return posts_admin.to_admin_read(post)


@router.patch('/campus-posts/{post_id}/images/reorder', response_model=CampusPostAdminRead)
async def reorder_campus_post_images(
    post_id: UUID,
    payload: CampusPostImageReorder,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await post_images.reorder_images(
        db, actor=actor, post_id=post_id, image_ids=payload.image_ids, as_staff=False
    )
    return posts_admin.to_admin_read(post)


@router.delete('/campus-posts/{post_id}/images/{image_id}', response_model=CampusPostAdminRead)
async def delete_campus_post_image(
    post_id: UUID,
    image_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await post_images.delete_image(
        db, actor=actor, post_id=post_id, image_id=image_id, as_staff=False
    )
    return posts_admin.to_admin_read(post)
