"""Publishing an employer opportunity into the existing campus feed.

Lives in the shared kernel because two different features need it and a feature may never import
another feature's `service.py` (CLAUDE.md):

* `app/features/employers/service.py` — auto-publishes on submit (the normal path).
* `app/features/admin/employers.py` — the manual approve path, kept for anything left pending.

Policy note: an organisation is vetted once, at approval. Re-reviewing every post it makes added
admin latency without adding much protection, so posts now go live immediately and moderation is
reactive — admins can archive any published post via the existing campus-post controls. See
`publish_submission` for how attribution survives that change.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub import publishing
from app.features.campus_hub.schema import CampusPostCreate
from app.models import CampusPost, EmployerOpportunitySubmission, User
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG


async def publish_submission(
    db: AsyncSession, *, submission: EmployerOpportunitySubmission, actor: User
) -> CampusPost:
    """Create + publish the campus post for `submission`, returning it.

    Idempotent against partial failure: `create_post`/`publish_post` each commit on their own, so
    if this died between them a retry must not publish a second, duplicate post.
    `published_post_id` is the guard — it is recorded the moment the draft exists, *before* the
    publish step, so a retry finds and reuses that draft instead of creating another.

    `actor` only supplies `CampusPost.author_id` (a non-null FK) and the audit actor. It is never
    shown to students — the student-facing schemas expose `source='employer'`, which drives the
    "Employer Partner" badge. True authorship stays on the submission itself via
    `submitted_by_id`, which is unaffected by whichever `User` row owns the post record.
    """
    if submission.published_post_id is not None:
        post = await db.get(CampusPost, submission.published_post_id)
    else:
        payload = CampusPostCreate(
            kind='opportunity',
            title=submission.title,
            body=submission.description,
            category=submission.category,
            external_url=submission.external_url,
        )
        post = await publishing.create_post(db, actor=actor, payload=payload)
        post.source = 'employer'
        post.eligible_program_slug = PRESIDENTIAL_SCHOLARS_SLUG
        submission.published_post_id = post.id
        await db.commit()
        await db.refresh(post)

    if post.status != 'published':
        post = await publishing.publish_post(db, actor=actor, post_id=post.id)
    return post
