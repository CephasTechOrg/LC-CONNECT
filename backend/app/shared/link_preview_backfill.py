"""One-shot / batched backfill of campus post link previews."""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CampusPost
from app.shared.link_preview import sync_post_link_preview


@dataclass(frozen=True, slots=True)
class LinkPreviewBackfillReport:
    eligible: int
    processed: int
    ok: int
    failed: int
    sample_ids: list[UUID]


async def backfill_missing_link_previews(
    db: AsyncSession,
    *,
    apply: bool = False,
    limit: int = 100,
) -> LinkPreviewBackfillReport:
    """Unfurl posts that have `external_url` but no `link_preview_status` yet.

    Dry-run (`apply=False`) only counts and samples; apply commits after each post so a
    mid-run failure keeps earlier successes.
    """
    limit = max(1, min(limit, 500))
    stmt = (
        select(CampusPost)
        .where(
            CampusPost.external_url.is_not(None),
            CampusPost.external_url != '',
            CampusPost.link_preview_status.is_(None),
        )
        .order_by(CampusPost.updated_at.asc())
        .limit(limit)
    )
    posts = list((await db.execute(stmt)).scalars().all())
    sample_ids = [p.id for p in posts[:10]]

    if not apply:
        return LinkPreviewBackfillReport(
            eligible=len(posts),
            processed=0,
            ok=0,
            failed=0,
            sample_ids=sample_ids,
        )

    ok = 0
    failed = 0
    for post in posts:
        await sync_post_link_preview(post)
        if post.link_preview_status == 'ok':
            ok += 1
        else:
            failed += 1
        await db.commit()

    return LinkPreviewBackfillReport(
        eligible=len(posts),
        processed=len(posts),
        ok=ok,
        failed=failed,
        sample_ids=sample_ids,
    )
