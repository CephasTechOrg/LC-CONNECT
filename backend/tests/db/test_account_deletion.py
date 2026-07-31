"""Self-service account deletion — anonymize-in-place, preserving other people's data.

Covers the guarantees the design commits to: the user row is scrubbed and access revoked; owned
groups transfer to the next member (or are deleted only when the user was alone); the user's
messages and reports about them survive; and their social-graph rows (blocks, requests, push
tokens) are cleared.
"""

from __future__ import annotations

from sqlalchemy import func, select

from app.features.account.service import delete_account
from app.features.groups import service as gs
from app.features.groups.schema import GroupCreate
from app.models import (
    Block,
    ConnectionRequest,
    ConversationMember,
    DeviceToken,
    Group,
    Message,
    Profile,
    Program,
    ProgramMembership,
    Report,
    ScholarProfessionalProfile,
    User,
)


async def test_delete_anonymizes_user_and_profile(db, factory):
    user = await factory.user(display_name='Jordan')
    user.auth_user_id = None  # no Supabase config in tests
    await db.commit()

    await delete_account(db, user)

    refreshed = await db.get(User, user.id)
    assert refreshed.status == 'deleted'
    assert refreshed.is_active is False
    assert refreshed.is_verified is False
    assert refreshed.deleted_at is not None
    assert refreshed.email == f'deleted+{user.id}@deleted.invalid'  # real email freed
    assert refreshed.auth_user_id is None

    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    assert profile.display_name == 'Deleted user'
    assert profile.bio is None
    assert profile.avatar_url is None
    assert profile.is_hidden is True


async def test_delete_keeps_sent_messages_and_reports_about_them(db, factory):
    sender = await factory.user(display_name='Sender')
    other = await factory.user(display_name='Other')
    match = await factory.match(sender, other)
    msg = await factory.message(match, sender, 'hello there')
    # Someone reported this user — moderation history must survive the deletion.
    db.add(Report(reporter_id=other.id, reported_user_id=sender.id, reason='spam'))
    await db.commit()

    await delete_account(db, sender)

    assert await db.get(Message, msg.id) is not None  # the DM history stays for `other`
    report_count = (
        await db.execute(select(func.count()).select_from(Report).where(Report.reported_user_id == sender.id))
    ).scalar_one()
    assert report_count == 1


async def test_delete_clears_social_graph_rows(db, factory):
    user = await factory.user()
    other = await factory.user()
    await factory.block(user, other)
    db.add(ConnectionRequest(sender_id=user.id, receiver_id=other.id, status='pending'))
    db.add(DeviceToken(user_id=user.id, token='fcm-abc', platform='android'))
    await db.commit()

    await delete_account(db, user)

    assert (await db.execute(select(func.count()).select_from(Block).where(Block.blocker_id == user.id))).scalar_one() == 0
    assert (await db.execute(select(func.count()).select_from(ConnectionRequest).where(ConnectionRequest.sender_id == user.id))).scalar_one() == 0
    assert (await db.execute(select(func.count()).select_from(DeviceToken).where(DeviceToken.user_id == user.id))).scalar_one() == 0


async def test_delete_removes_scholar_professional_profile(db, factory):
    from app.features.scholars import service as scholars_service
    from app.features.scholars.schema import ScholarProfessionalProfileUpdate

    user = await factory.user(display_name='Scholar')
    program = Program(slug=scholars_service.PRESIDENTIAL_SCHOLARS_SLUG, name='Presidential Scholars')
    db.add(program)
    await db.flush()
    db.add(ProgramMembership(user_id=user.id, program_id=program.id, status='active'))
    await db.commit()
    await scholars_service.update_profile(db, user.id, ScholarProfessionalProfileUpdate(summary='Bio'))

    await delete_account(db, user)

    remaining = (
        await db.execute(
            select(func.count()).select_from(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == user.id)
        )
    ).scalar_one()
    assert remaining == 0


async def test_delete_transfers_owned_group_to_next_member(db, factory):
    owner = await factory.user(display_name='Owner')
    group = await gs.create_group(db, owner, GroupCreate(name='Chess Club', category='club', join_policy='open'))
    await db.commit()
    member = await factory.user(display_name='Member')
    await gs.join_group(db, group, member)
    await db.commit()

    await delete_account(db, owner)

    surviving = await db.get(Group, group.id)
    assert surviving is not None  # the community outlives its founder
    assert surviving.owner_id == member.id
    new_owner_m = (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == group.conversation_id,
                ConversationMember.user_id == member.id,
            )
        )
    ).scalar_one()
    assert new_owner_m.role == 'owner'
    # The departing owner is no longer a member of the group chat.
    gone = (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == group.conversation_id,
                ConversationMember.user_id == owner.id,
            )
        )
    ).scalar_one_or_none()
    assert gone is None


async def test_delete_removes_solo_owned_group(db, factory):
    owner = await factory.user(display_name='Loner')
    group = await gs.create_group(db, owner, GroupCreate(name='Just Me', category='club', join_policy='open'))
    await db.commit()

    group_id = group.id  # capture before expiring — the row is about to be cascade-deleted
    await delete_account(db, owner)

    db.expire_all()  # drop the cached Group (deleted via its conversation) so we read the DB
    remaining = (
        await db.execute(select(func.count()).select_from(Group).where(Group.id == group_id))
    ).scalar_one()
    assert remaining == 0  # sole member → group removed
