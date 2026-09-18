"""Review Part 3 additional findings (checklist 2.9) — defects nobody reported.

Four of the nine were real. The other five are recorded here too, because "we checked and it is
fine" is worth as much as a fix and stops the same thing being re-investigated:

* **#2** attendance auto-close — already done in 1.3 (`app/main.py` runs a sweep).
* **#4** `ActivityUpdate` naive-vs-aware 500 — already done in 1.1 (`AwareDatetime`).
* **#5** `persist_message_idempotent`'s rollback discarding `ensure_dm_conversation` work — not a
  bug. A duplicate `client_message_id` means the original send already committed, so the
  conversation it needed already exists; the rolled-back create was a redundant one that lost a
  race. Pinned below anyway, because the reasoning is not obvious from the code.
* **#6** staff-DM pair uniqueness — a trade-off the code already documents, not an oversight.
* **#7** `unread_summary` missing group conversations — already correct. It joins on
  `ConversationMember.conversation_id`, not through `matches`, so groups count. Pinned below.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, text

from app.features.messages.service import persist_message_idempotent, unread_summary
from app.features.scholars import service as scholars_service
from app.models import Conversation, Program, ProgramMembership, ScholarProfessionalProfile


async def _honors_program(db) -> Program:
    program = (
        await db.execute(select(Program).where(Program.slug == 'presidential_scholars'))
    ).scalar_one_or_none()
    if program is None:
        program = Program(slug='presidential_scholars', name='Presidential Scholars')
        db.add(program)
        await db.commit()
    return program


async def _scholar(db, factory):
    """A verified Presidential Scholar — the only account allowed a professional profile."""
    program = await _honors_program(db)
    user = await factory.user(display_name='Scholar')
    db.add(ProgramMembership(user_id=user.id, program_id=program.id, status='active'))
    await db.commit()
    return user


# ── finding #3: the scholar profile insert race ───────────────────────────────

async def test_scholar_profile_is_created_once_under_concurrency(db, factory, sessions):
    """`GET /scholars/me` creates the row lazily, and the mobile client fires several scholar
    reads at once when the dashboard mounts — so two first-reads racing is reachable, not
    theoretical. It used to raise an unhandled IntegrityError and 500 whichever request lost.
    """
    user = await _scholar(db, factory)

    async def get_profile():
        async with sessions() as session:
            return await scholars_service._get_or_create(session, user.id)

    results = await asyncio.gather(get_profile(), get_profile(), return_exceptions=True)

    failures = [r for r in results if isinstance(r, Exception)]
    assert failures == [], f'a concurrent first-read failed: {failures}'

    rows = (await db.execute(select(ScholarProfessionalProfile))).scalars().all()
    assert len(rows) == 1, 'the unique constraint must leave exactly one row'


async def test_scholar_profile_is_reused_on_a_second_read(db, factory):
    user = await _scholar(db, factory)

    first = await scholars_service._get_or_create(db, user.id)
    second = await scholars_service._get_or_create(db, user.id)

    assert first.id == second.id


# ── finding #1: the contradictory foreign key ─────────────────────────────────

async def test_started_by_id_foreign_key_restricts(db):
    """`NOT NULL` with `ON DELETE SET NULL` is incoherent — the cascade can never execute, so a
    hard delete failed with a confusing not-null violation instead of a foreign-key error.

    Asserted against the live catalogue rather than the model, because the model and the database
    are exactly what drifted apart here.
    """
    rule = (
        await db.execute(
            text(
                """
                SELECT rc.delete_rule
                FROM information_schema.referential_constraints rc
                JOIN information_schema.table_constraints tc
                  ON tc.constraint_name = rc.constraint_name
                WHERE tc.table_name = 'attendance_sessions'
                  AND tc.constraint_name LIKE '%started_by_id%'
                """
            )
        )
    ).scalar_one_or_none()

    assert rule == 'RESTRICT', f'expected RESTRICT, found {rule}'


# ── finding #7: group conversations are counted (already correct) ─────────────

async def test_unread_summary_counts_group_conversations(db, factory):
    """The concern was that this query joined through `matches`, which would make group unread
    silently zero. It does not — it joins on `ConversationMember.conversation_id`.
    """
    owner = await factory.user(display_name='Owner')
    member = await factory.user(display_name='Member')

    from app.features.groups import service as group_service
    from app.features.groups.schema import GroupCreate

    group = await group_service.create_group(
        db, owner, GroupCreate(name='CS Club', category='club', visibility='public',
                               join_policy='open')
    )
    await group_service.join_group(db, group, member)
    await db.commit()

    await persist_message_idempotent(
        db, sender_id=owner.id, match_id=None, conversation_id=group.conversation_id,
        body='hello group', client_message_id=None,
    )

    total, per_conversation = await unread_summary(db, member.id)
    assert total == 1
    assert per_conversation[group.conversation_id] == 1


# ── finding #5: the rollback is safe (already correct) ───────────────────────

async def test_duplicate_send_keeps_the_conversation(db, factory):
    """The rollback on a duplicate `client_message_id` undoes the whole transaction, including any
    `ensure_dm_conversation` work in it. That is safe, and this is why: a duplicate means the
    original send already committed, so the conversation it needed already exists — the create
    being rolled back was a redundant one that lost a race.
    """
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    client_id = (await factory.user(display_name='ignored')).id  # any uuid
    first, created_first = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='hello', client_message_id=client_id,
    )
    second, created_second = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='hello', client_message_id=client_id,
    )

    assert created_first is True
    assert created_second is False
    assert first.id == second.id
    # The conversation survived the rollback — which is the part worth pinning.
    still_there = (
        await db.execute(select(Conversation).where(Conversation.id == conversation_id))
    ).scalar_one_or_none()
    assert still_there is not None


async def test_attendance_sweep_closes_a_lapsed_session(db, factory):
    """Finding #2 asked for a scheduler, because `maybe_auto_close_session` is read-triggered: a
    lapsed session stayed `open` and held the partial unique index, blocking the next session with
    a 409 until something happened to read it. 1.3 added the sweep; this asserts it still works.
    """
    from app.features.attendance.service import start_session, sweep_expired_sessions

    await _honors_program(db)
    instructor = await factory.user(display_name='Instructor')
    session = await start_session(db, actor_id=instructor.id, title='Honors Class')
    # Push the whole window into the past so the sweep has something to close.
    session.present_until = datetime.now(UTC) - timedelta(hours=2)
    session.late_until = datetime.now(UTC) - timedelta(hours=1)
    await db.commit()

    closed = await sweep_expired_sessions(db)

    assert session.id in closed
