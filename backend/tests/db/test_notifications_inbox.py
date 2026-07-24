"""In-app notification inbox — create, list (with group + actor resolution), unread count, and
mark-all-read (the badge that ticks down when the user opens the screen)."""

from __future__ import annotations

from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.notifications import service as notifications


async def _group(db, owner, name='CS Club'):
    group = await group_service.create_group(db, owner, GroupCreate(name=name, category='club', join_policy='approval'))
    await db.commit()
    return group


async def test_create_list_and_resolve_group_and_actor(db, factory):
    me = await factory.user(display_name='Me')
    actor = await factory.user(display_name='Alex')
    group = await _group(db, actor, name='Chess Club')

    await notifications.create_notification(
        db, user_id=me.id, type='group_invite', group_id=group.id, actor_id=actor.id
    )
    await db.commit()

    items = await notifications.list_notifications(db, me.id)
    assert len(items) == 1
    n = items[0]
    assert n.type == 'group_invite'
    assert n.read is False
    assert n.group is not None and n.group.name == 'Chess Club'
    assert n.actor is not None and n.actor.display_name == 'Alex'


async def test_unread_count_and_mark_all_read(db, factory):
    me = await factory.user()
    actor = await factory.user(display_name='Admin')
    group = await _group(db, actor)

    for kind in ('group_request_approved', 'group_made_admin'):
        await notifications.create_notification(db, user_id=me.id, type=kind, group_id=group.id, actor_id=actor.id)
    await db.commit()

    assert await notifications.unread_count(db, me.id) == 2

    await notifications.mark_all_read(db, me.id)
    assert await notifications.unread_count(db, me.id) == 0
    # The rows remain (history), just marked read.
    items = await notifications.list_notifications(db, me.id)
    assert len(items) == 2 and all(n.read for n in items)


async def test_notifications_are_scoped_to_their_recipient(db, factory):
    me = await factory.user()
    other = await factory.user()
    actor = await factory.user()
    group = await _group(db, actor)

    await notifications.create_notification(db, user_id=me.id, type='group_invite', group_id=group.id, actor_id=actor.id)
    await db.commit()

    assert await notifications.unread_count(db, me.id) == 1
    assert await notifications.unread_count(db, other.id) == 0  # never leaks to another user
    assert await notifications.list_notifications(db, other.id) == []


async def test_admin_ids_lists_admins_and_owner(db, factory):
    owner = await factory.user()
    member = await factory.user()
    group = await _group(db, owner)
    # Add a plain member; they should NOT be an admin recipient.
    await group_service.join_group(db, group, member)
    await db.commit()
    # Owner is auto-admin-tier; approve the member and promote to admin.
    await group_service.approve_request(db, group, member.id)
    owner_member = await group_service.membership(db, group.conversation_id, owner.id)
    await group_service.change_role(db, group, owner_member, member.id, 'admin')
    await db.commit()

    ids = set(await group_service.admin_ids(db, group.conversation_id))
    assert ids == {owner.id, member.id}
