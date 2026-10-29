"""Withdraw, disconnect, reconnect, and the connection_state a profile renders its button from."""

from __future__ import annotations

from sqlalchemy import select

from app.features.connections.service import active_match, existing_match, ordered_pair
from app.models import ConnectionRequest, Match
from app.shared.policies import connection_state, users_are_connected


async def _request(db, sender, receiver):
    req = ConnectionRequest(sender_id=sender.id, receiver_id=receiver.id, status='pending')
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return req


async def _match(db, a, b):
    # Pairs are stored in sorted order (`ordered_pair`), so a match created any other way is not
    # findable by the real lookups — the invariant the production code maintains.
    left, right = ordered_pair(a.id, b.id)
    m = Match(user_a_id=left, user_b_id=right)
    db.add(m)
    await db.commit()
    await db.refresh(m)
    return m


# ── connection_state ──────────────────────────────────────────────────────────

async def test_state_is_none_for_strangers(db, factory):
    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    assert await connection_state(db, viewer_id=a.id, other_id=b.id) == 'none'


async def test_state_distinguishes_who_sent_the_request(db, factory):
    """The bug this exists for: the profile screen could not tell "I asked them" from "they
    asked me" from "nothing", so it always rendered Connect and 409'd on the second tap."""
    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    await _request(db, a, b)
    assert await connection_state(db, viewer_id=a.id, other_id=b.id) == 'outgoing_pending'
    assert await connection_state(db, viewer_id=b.id, other_id=a.id) == 'incoming_pending'


async def test_state_is_connected_once_matched(db, factory):
    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    await _match(db, a, b)
    assert await connection_state(db, viewer_id=a.id, other_id=b.id) == 'connected'


async def test_state_for_yourself(db, factory):
    a = await factory.user(display_name='A')
    assert await connection_state(db, viewer_id=a.id, other_id=a.id) == 'self'


# ── disconnect ────────────────────────────────────────────────────────────────

async def test_disconnecting_ends_the_connection_without_deleting_it(db, factory):
    """Flagged, not deleted. `messages.match_id` is ON DELETE CASCADE, so deleting would erase
    the conversation for *both* people — harsher than blocking, which only hides."""
    from datetime import UTC, datetime

    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    m = await _match(db, a, b)
    assert await users_are_connected(db, a.id, b.id) is True

    m.disconnected_at = datetime.now(UTC)
    await db.commit()

    assert await users_are_connected(db, a.id, b.id) is False
    assert await connection_state(db, viewer_id=a.id, other_id=b.id) == 'none'
    # The row — and therefore the thread and its history — survives.
    assert await existing_match(db, a.id, b.id) is not None
    assert await active_match(db, a.id, b.id) is None


async def test_disconnect_is_symmetric(db, factory):
    """Either side ending it ends it for both; there is no one-way connection."""
    from datetime import UTC, datetime

    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    m = await _match(db, a, b)
    m.disconnected_at = datetime.now(UTC)
    await db.commit()
    assert await users_are_connected(db, b.id, a.id) is False


async def test_reconnecting_clears_the_flag_and_reuses_the_row(db, factory):
    """`uq_match_pair` forbids a second row, so reconnecting must clear the flag on the old one.
    Miss this and an accepted request leaves the pair still disconnected."""
    from datetime import UTC, datetime

    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    m = await _match(db, a, b)
    original_id = m.id
    m.disconnected_at = datetime.now(UTC)
    await db.commit()

    match = await existing_match(db, a.id, b.id)
    match.disconnected_at = None
    await db.commit()

    assert await users_are_connected(db, a.id, b.id) is True
    assert (await existing_match(db, a.id, b.id)).id == original_id


# ── withdraw ──────────────────────────────────────────────────────────────────

async def test_withdrawing_frees_the_pair_to_ask_again(db, factory):
    """Deleted rather than marked withdrawn: `uq_connection_sender_receiver` is on the pair, so a
    kept row would block the sender from ever requesting again."""
    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    req = await _request(db, a, b)

    await db.delete(req)
    await db.commit()

    assert await connection_state(db, viewer_id=a.id, other_id=b.id) == 'none'
    again = ConnectionRequest(sender_id=a.id, receiver_id=b.id, status='pending')
    db.add(again)
    await db.commit()  # would raise on the unique constraint if the old row were kept
    rows = (await db.execute(select(ConnectionRequest).where(
        ConnectionRequest.sender_id == a.id, ConnectionRequest.receiver_id == b.id))).scalars().all()
    assert len(rows) == 1


async def test_after_a_disconnect_either_side_can_ask_again_and_accepting_reconnects(db, factory, monkeypatch):
    """The real flow: disconnect, ask again, accept. Asking again used to answer "already
    matched" (it counted the disconnected match) and then trip the one-request-per-pair rule."""
    import importlib

    from app.features.connections.schema import ConnectionRequestCreate

    # The package exports its APIRouter as `router`, which shadows the module of the same name.
    connections = importlib.import_module('app.features.connections.router')

    async def quiet(*_args, **_kwargs):
        return None

    monkeypatch.setattr(connections, '_notify', quiet)
    monkeypatch.setattr('app.features.realtime.runtime.revoke_pair_access', quiet)
    monkeypatch.setattr('app.features.realtime.presence.hide_between', quiet)

    a, b = await factory.user(display_name='A'), await factory.user(display_name='B')
    first = await connections.send_connection_request(
        ConnectionRequestCreate(receiver_id=b.id), current_user=a, db=db
    )
    await connections.accept_request(first.id, current_user=b, db=db)
    await connections.disconnect_from_user(b.id, current_user=a, db=db)
    assert await users_are_connected(db, a.id, b.id) is False

    again = await connections.send_connection_request(
        ConnectionRequestCreate(receiver_id=b.id), current_user=a, db=db
    )
    assert again.status == 'pending' and again.id == first.id
    await connections.accept_request(again.id, current_user=b, db=db)
    assert await users_are_connected(db, a.id, b.id) is True
