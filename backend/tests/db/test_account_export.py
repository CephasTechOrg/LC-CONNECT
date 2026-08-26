"""Account data export — privacy right of access."""

from __future__ import annotations

import json

from sqlalchemy import select

from app.features.account.export import build_account_export
from app.models import AdminAuditLog, Profile


async def test_export_includes_account_profile_and_message(db, factory):
    user = await factory.user(display_name='Exporter')
    other = await factory.user(display_name='Peer')
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.bio = 'Hello campus'
    match = await factory.match(user, other)
    await factory.message(match, user, 'My private note')
    await db.commit()

    payload = await build_account_export(db, user)

    assert payload['schema_version'] == 1
    assert payload['account']['email'] == user.email
    assert payload['profile']['display_name'] == 'Exporter'
    assert payload['profile']['bio'] == 'Hello campus'
    assert any(m['body'] == 'My private note' for m in payload['messages_sent'])
    assert 'password_hash' not in payload['account']
    assert all('token' not in d for d in payload['device_tokens'])

    audit = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'account.export',
                AdminAuditLog.target_id == user.id,
            )
        )
    ).scalar_one()
    after = json.loads(audit.after_data or '{}')
    assert after['schema_version'] == 1
