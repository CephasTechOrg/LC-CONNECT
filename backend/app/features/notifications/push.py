"""FCM push sender — guarded so the backend runs fine with no Firebase config.

Privacy: the notification shows the sender's name only; the data payload carries just
ids (`conversation_id`, `sender_id`), never the message body — the client fetches the
message on open (rec #2). Invalid tokens FCM reports are pruned (rec #5); outcomes are
logged (rec #6).
"""

from __future__ import annotations

import asyncio
import json
import logging
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.notifications.service import prune_tokens, tokens_for_user

logger = logging.getLogger('lc_connect.push')


class PushSender:
    def __init__(self) -> None:
        self._ready = False
        self._init()

    def _init(self) -> None:
        if not settings.firebase_credentials_json:
            logger.info('Push disabled: FIREBASE_CREDENTIALS_JSON not set')
            return
        try:
            import firebase_admin
            from firebase_admin import credentials

            cred = credentials.Certificate(json.loads(settings.firebase_credentials_json))
            firebase_admin.initialize_app(cred, name='lc-connect-push')
            self._ready = True
            logger.info('Push enabled (FCM)')
        except Exception as exc:  # noqa: BLE001 - never let push break startup
            logger.warning('Push disabled: firebase init failed: %s', exc)

    @property
    def enabled(self) -> bool:
        return self._ready

    async def notify_new_message(
        self,
        db: AsyncSession,
        *,
        recipient_id: UUID,
        sender_name: str,
        conversation_id: UUID,
        sender_id: UUID,
    ) -> None:
        if not self._ready:
            return
        tokens = await tokens_for_user(db, recipient_id)
        if not tokens:
            return
        try:
            invalid = await asyncio.to_thread(self._send, tokens, sender_name, conversation_id, sender_id)
        except Exception as exc:  # noqa: BLE001 - a push failure must never surface to the sender
            logger.warning('Push send failed for user %s: %s', recipient_id, exc)
            return
        if invalid:
            await prune_tokens(db, invalid)

    def _send(self, tokens: list[str], sender_name: str, conversation_id: UUID, sender_id: UUID) -> list[str]:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=sender_name, body='Sent you a message'),
            data={'type': 'message', 'conversation_id': str(conversation_id), 'sender_id': str(sender_id)},
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))),
        )
        response = messaging.send_each_for_multicast(message)
        invalid = [
            token
            for token, result in zip(tokens, response.responses, strict=False)
            if not result.success and isinstance(result.exception, messaging.UnregisteredError)
        ]
        logger.info(
            'Push: sent=%d failed=%d pruned=%d', response.success_count, response.failure_count, len(invalid)
        )
        return invalid


push_sender = PushSender()
