"""Campus announcement images — cap, ownership, cover on list/detail, storage cleanup."""

from __future__ import annotations

import io
from uuid import UUID

import pytest
from fastapi import HTTPException
from PIL import Image

from app.features.admin.campus_posts import create_post, delete_post, publish_post
from app.features.campus_hub import images as post_images
from app.features.campus_hub.posts import get_post, list_posts
from app.features.campus_hub.schema import CampusPostCreate
from app.models import CampusPostImage


def _jpeg(size=(40, 30)) -> bytes:
    img = Image.new('RGB', size, 'navy')
    buf = io.BytesIO()
    img.save(buf, 'JPEG')
    return buf.getvalue()


def _stub_storage(monkeypatch):
    deleted: list[str] = []

    def upload(post_id: UUID, image_id: UUID, content_type: str, data: bytes) -> tuple[str, str]:
        path = f'campus-posts/{post_id}/{image_id}.jpg'
        return path, f'https://cdn.example/{image_id}.jpg?v=1'

    monkeypatch.setattr(post_images.storage_service, 'upload_campus_post_image', upload)
    monkeypatch.setattr(
        post_images.storage_service,
        'delete_campus_post_image',
        lambda path: deleted.append(path),
    )
    return deleted


async def _admin(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    await db.commit()
    return admin


async def test_fifth_image_is_rejected(db, factory, monkeypatch):
    _stub_storage(monkeypatch)
    admin = await _admin(db, factory)
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Flyer', body='See photos.'),
    )
    jpeg = _jpeg()
    for _ in range(4):
        post = await post_images.add_image(db, actor=admin, post_id=post.id, data=jpeg, as_staff=False)
    assert len(post.images) == 4
    with pytest.raises(HTTPException) as exc:
        await post_images.add_image(db, actor=admin, post_id=post.id, data=jpeg, as_staff=False)
    assert exc.value.status_code == 400
    assert '4' in exc.value.detail


async def test_non_author_cannot_attach_image(db, factory, monkeypatch):
    _stub_storage(monkeypatch)
    owner = await factory.user(display_name='Owner')
    owner.role = 'admin'
    other = await factory.user(display_name='Other')
    other.role = 'staff'
    await db.commit()
    post = await create_post(
        db, actor=owner, payload=CampusPostCreate(kind='announcement', title='Mine', body='Body'),
    )
    with pytest.raises(HTTPException) as exc:
        await post_images.add_image(db, actor=other, post_id=post.id, data=_jpeg(), as_staff=True)
    assert exc.value.status_code == 403


async def test_list_and_detail_include_cover(db, factory, monkeypatch):
    _stub_storage(monkeypatch)
    admin = await _admin(db, factory)
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Covered', body='Body'),
    )
    post = await post_images.add_image(db, actor=admin, post_id=post.id, data=_jpeg(), as_staff=False)
    post = await post_images.add_image(db, actor=admin, post_id=post.id, data=_jpeg(), as_staff=False)
    published = await publish_post(db, actor=admin, post_id=post.id)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    rows = await list_posts(db, user=student, kind='announcement')
    match = next(row for row in rows if row['id'] == published.id)
    assert len(match['images']) == 2
    assert match['images'][0]['sort_order'] == 0
    assert match['images'][0]['url'].startswith('https://cdn.example/')

    detail = await get_post(db, user=student, post_id=published.id)
    assert [img['sort_order'] for img in detail['images']] == [0, 1]


async def test_delete_image_removes_storage_object(db, factory, monkeypatch):
    deleted = _stub_storage(monkeypatch)
    admin = await _admin(db, factory)
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Temp', body='Body'),
    )
    post = await post_images.add_image(db, actor=admin, post_id=post.id, data=_jpeg(), as_staff=False)
    image_id = post.images[0].id
    object_path = post.images[0].object_path
    post = await post_images.delete_image(
        db, actor=admin, post_id=post.id, image_id=image_id, as_staff=False
    )
    assert post.images == []
    assert object_path in deleted
    remaining = (await db.get(CampusPostImage, image_id))
    assert remaining is None


async def test_hard_delete_cleans_storage(db, factory, monkeypatch):
    deleted = _stub_storage(monkeypatch)
    admin = await _admin(db, factory)
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Gone', body='Body'),
    )
    post = await post_images.add_image(db, actor=admin, post_id=post.id, data=_jpeg(), as_staff=False)
    path = post.images[0].object_path
    await delete_post(db, actor=admin, post_id=post.id)
    assert path in deleted
