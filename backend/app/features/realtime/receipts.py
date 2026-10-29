"""Receipt frames — `messages.read` and `messages.delivered`.

Split out of `gateway.py` when it crossed 400 lines. Both handlers advance one member's boundary
and tell the rest of the conversation; neither touches the send, subscribe or typing paths that
the gateway's serve loop is otherwise about.
"""

from __future__ import annotations

from app.database import AsyncSessionLocal
from app.features.realtime import protocol, service
from app.features.realtime.broadcasts import publish_notifications_read
from app.features.realtime.manager import Connection
from app.features.realtime.runtime import event_bus
from app.shared.notification_reads import mark_chat_reactions_read


async def on_delivered(conn: Connection, frame: protocol.DeliveredFrame) -> None:
    """Advance this member's delivery boundary and tell the conversation (protocol 2).

    Same authorization and same publish shape as [on_read]. It stays a separate handler rather
    than a parameterised one because the two are only *currently* alike: read has a display-only
    mirror on `messages` and drives unread counts, delivery has neither, and reactions and edits
    will add more receipt kinds that diverge further.

    Silent on every failure. A delivery acknowledgement is not a request — there is no
    `request_id` to correlate an error with, and a client that cannot record a tick has nothing
    useful to do about it.
    """
    async with AsyncSessionLocal() as db:
        try:
            await service.recheck_account(db, conn.user_id)
            conversation, _ = await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
        except service.WsForbidden:
            return
        # Groups are skipped, and this is the load-bearing line of the handler.
        #
        # A group bubble shows no delivered tick (design §2.1: that needs a rule for which
        # members count, plus every member's boundary held client-side). But every member's
        # device acknowledges every message — so one message in a 30-member group produced 29
        # acknowledgements, each costing an account recheck, an authorization, four more queries
        # and a fan-out to all 30 sockets. Roughly 170 queries and 870 socket writes to drive a
        # glyph that is never drawn, and quadratic in group size.
        #
        # Enforced here rather than trusted to the client: the client also suppresses it, but
        # only the server can bound what an old or modified client sends.
        if conversation.kind == 'group':
            return
        delivered_at = await service.mark_delivered(
            db,
            recipient_id=conn.user_id,
            match_id=frame.conversation_id,
            through_message_id=frame.through_message_id,
            # Already resolved by `authorize_conversation` above; re-resolving is a wasted
            # cross-region round trip on the hottest realtime path.
            conversation=conversation,
        )
    if delivered_at is None:
        return
    # Canonical id to route, client-facing id to address — see the note in [on_read].
    await event_bus.publish_to_conversation(
        conversation.id,
        protocol.delivery_receipt(
            conversation.match_id or conversation.id,
            conn.user_id,
            frame.through_message_id,
            delivered_at.isoformat(),
        ),
        exclude_user=conn.user_id,
    )


async def on_read(conn: Connection, frame: protocol.ReadFrame) -> None:
    async with AsyncSessionLocal() as db:
        try:
            await service.recheck_account(db, conn.user_id)
            conversation, _ = await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
        except service.WsForbidden:
            return
        read_at = await service.mark_read(
            db,
            reader_id=conn.user_id,
            match_id=frame.conversation_id,
            through_message_id=frame.through_message_id,
            conversation=conversation,  # see `on_delivered`
        )
        # Reading the chat reads its reaction notifications too.
        cleared = (
            await mark_chat_reactions_read(
                db, conn.user_id, conversation.match_id or conversation.id
            )
            if read_at is not None
            else []
        )
    if read_at is None:
        return
    await publish_notifications_read(conn.user_id, cleared)
    # Route on the canonical id (what the manager indexes), but address the frame with the
    # client-facing id (what the recipient's open chat matches on). Before subscriptions were
    # canonicalised these were the same value for a DM, which is why this read correctly by
    # accident — it must not go back to echoing the client's ref.
    await event_bus.publish_to_conversation(
        conversation.id,
        protocol.read_receipt(
            conversation.match_id or conversation.id,
            conn.user_id,
            frame.through_message_id,
            read_at.isoformat(),
        ),
        exclude_user=conn.user_id,
    )
