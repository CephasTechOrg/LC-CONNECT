"""FCM push sender — guarded so the backend runs fine with no Firebase config.

Covers messages, campus posts, and a deliberately small set of in-app notifications
(connections + group invites/requests + program membership verification — see
`notify_in_app_event`). Everything else stays live-only (WebSocket + badge), to avoid pushing for
every low-value event.

Privacy: the notification shows the sender's/actor's name only; the data payload carries just
ids, never message bodies or notification content — the client fetches details on open (rec #2).
Invalid tokens FCM reports are pruned (rec #5); outcomes are logged (rec #6).
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


def _notification_copy(notif_type: str, actor_name: str | None, group_name: str | None) -> tuple[str, str]:
    """Title/body per notification type. Title is who did it (falls back to 'Someone'); body
    is a short, non-sensitive description — never anything the actor wrote."""
    who = actor_name or 'Someone'
    if notif_type == 'connection_request':
        return who, 'Wants to connect with you'
    if notif_type == 'connection_accepted':
        return who, 'Accepted your connection request'
    if notif_type == 'group_invite':
        return who, f'Invited you to {group_name}' if group_name else 'Invited you to a group'
    if notif_type == 'group_join_request':
        return who, f'Wants to join {group_name}' if group_name else 'Wants to join your group'
    if notif_type == 'group_request_approved':
        return group_name or 'Group request', 'Your request to join was approved'
    if notif_type == 'program_membership_verified':
        return 'LC Connect', "You've been verified for a new program — check your profile"
    return who, 'You have a new notification'


class PushSender:
    def __init__(self) -> None:
        self._ready = False
        self._app = None
        self._init()

    def _init(self) -> None:
        if not settings.firebase_credentials_json:
            logger.info('Push disabled: FIREBASE_CREDENTIALS_JSON not set')
            return
        try:
            import firebase_admin
            from firebase_admin import credentials

            cred = credentials.Certificate(json.loads(settings.firebase_credentials_json))
            # A named (non-default) app: every messaging call MUST pass app=self._app,
            # else firebase-admin looks for the default app and raises "does not exist".
            self._app = firebase_admin.initialize_app(cred, name='lc-connect-push')
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

    async def notify_in_app_event(
        self,
        db: AsyncSession,
        *,
        recipient_id: UUID,
        notif_type: str,
        actor_name: str | None,
        group_name: str | None,
    ) -> None:
        """Push for the small set of in-app notifications worth interrupting someone for —
        a connection request/acceptance or a group invite/join-request/approval. Everything
        else (role changes, removals, etc.) stays live-only; the badge still catches it up
        on next open. Title is the actor's name (never the notification body's raw content)."""
        if not self._ready:
            return
        tokens = await tokens_for_user(db, recipient_id)
        if not tokens:
            return
        title, body = _notification_copy(notif_type, actor_name, group_name)
        try:
            invalid = await asyncio.to_thread(self._send_notification, tokens, notif_type, title, body)
        except Exception as exc:  # noqa: BLE001 - a push failure must never surface to the actor
            logger.warning('Notification push failed for user %s (type=%s): %s', recipient_id, notif_type, exc)
            return
        if invalid:
            await prune_tokens(db, invalid)

    def _send_notification(self, tokens: list[str], notif_type: str, title: str, body: str) -> list[str]:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={'type': 'notification', 'notif_type': notif_type},
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))),
        )
        response = messaging.send_each_for_multicast(message, app=self._app)
        invalid = [
            token
            for token, result in zip(tokens, response.responses, strict=False)
            if not result.success and isinstance(result.exception, messaging.UnregisteredError)
        ]
        logger.info(
            'Notification push (%s): sent=%d failed=%d pruned=%d',
            notif_type, response.success_count, response.failure_count, len(invalid),
        )
        return invalid

    async def notify_campus_post(
        self,
        db: AsyncSession,
        *,
        tokens: list[str],
        title: str,
        post_id: UUID,
        priority: str,
    ) -> None:
        if not self._ready or not tokens:
            return
        body = 'Important campus update' if priority == 'important' else 'Urgent campus alert'
        try:
            invalid = await asyncio.to_thread(self._send_campus_post, tokens, title, body, post_id, priority)
        except Exception as exc:  # noqa: BLE001
            logger.warning('Campus post push failed for %s: %s', post_id, exc)
            return
        if invalid:
            await prune_tokens(db, invalid)

    def _send_campus_post(
        self,
        tokens: list[str],
        title: str,
        body: str,
        post_id: UUID,
        priority: str,
    ) -> list[str]:
        from firebase_admin import messaging

        invalid: list[str] = []
        for start in range(0, len(tokens), 500):
            chunk = tokens[start : start + 500]
            message = messaging.MulticastMessage(
                tokens=chunk,
                notification=messaging.Notification(title=title, body=body),
                data={'type': 'campus_post', 'post_id': str(post_id), 'priority': priority},
                apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))),
            )
            response = messaging.send_each_for_multicast(message, app=self._app)
            invalid.extend(
                token
                for token, result in zip(chunk, response.responses, strict=False)
                if not result.success and isinstance(result.exception, messaging.UnregisteredError)
            )
        logger.info('Campus post push: tokens=%d pruned=%d', len(tokens), len(invalid))
        return invalid

    def _send(self, tokens: list[str], sender_name: str, conversation_id: UUID, sender_id: UUID) -> list[str]:
        from firebase_admin import messaging

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=sender_name, body='Sent you a message'),
            data={'type': 'message', 'conversation_id': str(conversation_id), 'sender_id': str(sender_id)},
            apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(sound='default'))),
        )
        response = messaging.send_each_for_multicast(message, app=self._app)
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
