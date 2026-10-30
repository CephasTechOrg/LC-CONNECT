from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.shared.message_limits import MAX_BODY_CHARS
from app.shared.schemas import ProfilePublic


# There is deliberately no timestamp here, and the reason is not an omission worth "fixing"
# later: a group's read state is a per-member *boundary*
# (`ConversationMember.last_read_message_id`), not a per-message record, so the moment this
# particular message was passed is not stored anywhere. Reporting the boundary's own timestamp as
# a read time for an older message would be a guess presented as a fact. `Message.read_at` cannot
# help — it is a single column, which is exactly why the boundary exists.
#
# It also deliberately does **not** embed `ProfilePublic`. That object carries bio, interests,
# languages, looking-for and a staff contact email — none of which a "read by" row renders, and
# loading it costs four extra `selectinload` queries *per reader*. A 30-member group would have
# meant kilobytes of unrelated personal data over the wire to draw a name and an avatar. Two
# fields is both the smaller payload and the smaller disclosure.
#
# The docstring below is the public OpenAPI description, so it stays about the contract.
class ReactionSummary(BaseModel):
    """One emoji's tally on a message, from the viewer's point of view.

    Aggregated server-side rather than sent as individual rows: a popular message would otherwise
    ship one row per reactor to render a chip that says "12". `reacted_by_me` comes from the same
    grouped query, so the client never needs a second request to know whether to fill the chip.
    """

    emoji: str
    count: int
    reacted_by_me: bool


class ReactionState(BaseModel):
    """A message's reactions after a change, from the caller's point of view.

    Returned by the reaction endpoints so the client reconciles its optimistic chip strip with
    the server's answer in the same round trip, instead of waiting for (or missing) a frame.
    """

    message_id: UUID
    reactions: list[ReactionSummary]


class MessageReactor(BaseModel):
    """Someone who reacted to a message, and with what — a row in the "Reacted by" sheet.

    Name and avatar only, for the same reason as [MessageReadBy]: the sheet draws a name, an
    avatar and an emoji, and a full public profile per reactor would be kilobytes of unrelated
    personal data. Includes the caller, so the sheet can show "You" and offer removal.
    """

    user_id: UUID
    display_name: str | None = None
    avatar_url: str | None = None
    emoji: str
    reacted_at: datetime


class ReplyPreview(BaseModel):
    """The message a reply quotes, as the quote block shows it.

    A snippet rather than the whole body: a quote is one or two lines, and a long message would
    otherwise ride along in full on every reply to it. `deleted` lets the quote say so instead of
    showing a stale excerpt; `edited` marks that the excerpt is the message's current text.
    """

    id: UUID
    sender_id: UUID
    sender_name: str | None = None
    body_snippet: str
    deleted: bool = False
    edited: bool = False


class MessageReadBy(BaseModel):
    """A member who has read a given message."""

    user_id: UUID
    display_name: str | None = None
    avatar_url: str | None = None


def _not_blank(value: str) -> str:
    """Length limits apply to the raw text, so a body of spaces passed `min_length=1` and was
    stored as an empty message. The WebSocket path already refused it."""
    if not value.strip():
        raise ValueError('Message cannot be empty')
    return value


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=MAX_BODY_CHARS)

    _body_not_blank = field_validator('body')(_not_blank)
    # Optional idempotency key; a retry with the same value returns the original message.
    client_message_id: UUID | None = None
    # The message this one replies to; must be in the same conversation and not deleted.
    reply_to_id: UUID | None = None


class MessageEditRequest(BaseModel):
    """The new body. Same bounds as sending — an edit cannot smuggle in a longer message."""

    body: str = Field(min_length=1, max_length=MAX_BODY_CHARS)

    _body_not_blank = field_validator('body')(_not_blank)


class LinkPreviewRequest(BaseModel):
    """A URL (or a snippet containing one) to unfurl for the chat composer / bubble card."""

    url: str = Field(min_length=8, max_length=2000)


class MessageLinkPreviewRead(BaseModel):
    """Open Graph / meta preview for a chat URL. Soft-fails: `status='failed'` still carries
    the domain so the client can render a hostname card rather than nothing."""

    url: str
    domain: str | None = None
    site_name: str | None = None
    title: str | None = None
    description: str | None = None
    image_url: str | None = None
    fetched_at: datetime | None = None
    status: str  # ok | failed


class StaffThreadCreate(BaseModel):
    """Start (or resolve) a staff↔anyone conversation — no connection required."""

    target_user_id: UUID


class MessageRead(BaseModel):
    id: UUID
    # match_id is null for group messages (a group has no match); conversation_id is the
    # universal container. Clients address a thread by match_id (DM) or conversation_id (group).
    match_id: UUID | None = None
    conversation_id: UUID | None = None
    sender_id: UUID
    client_message_id: UUID | None = None
    body: str  # empty when deleted — the original is never sent to clients
    created_at: datetime
    read_at: datetime | None
    # Whether every other member has acknowledged receipt — the sender's second tick.
    #
    # A boolean rather than a timestamp on purpose: delivery is recorded as a per-member
    # *boundary*, which does not store when it passed any particular older message. A
    # `delivered_at` would therefore be a fabricated time for every message but the newest.
    # `read_at` can be a timestamp because `messages.read_at` is a real per-row column.
    delivered: bool = False
    deleted: bool = False
    # When the sender last edited it, or null. Drives the small "edited" label; the authority on
    # *what* changed is `message_edits`, which clients never see.
    edited_at: datetime | None = None
    # Empty for the overwhelming majority of messages, which is why it is a list on the message
    # rather than a separate endpoint: one grouped query per page costs one round trip, and a
    # message with no reactions costs nothing to report.
    reactions: list[ReactionSummary] = []
    # The message this one replies to, as its quote shows it; null when it is not a reply (or
    # what it quoted has since been purged).
    reply_to: ReplyPreview | None = None


class ThreadReactionPreview(BaseModel):
    """The newest reaction worth showing on a thread's inbox row.

    In a DM that is any reaction; in a group, one to the viewer's own message or by the viewer —
    otherwise a busy group's reactions to everyone else's messages would take over the row.
    Surfaced so "Ama reacted 👍 to “see you at 5”" is visible without opening the chat. Additive:
    it never affects thread ordering or the unread count.
    """

    emoji: str
    actor_id: UUID
    actor_name: str | None = None
    message_id: UUID
    reacted_at: datetime
    # Whose message was reacted to, so the client can say "your message" or quote it.
    message_sender_id: UUID | None = None
    message_snippet: str = ''


class GroupThreadInfo(BaseModel):
    id: UUID
    name: str
    avatar_url: str | None


class MessageThreadRead(BaseModel):
    # `conversation_id` is the universal addressing id (what the client opens/subscribes to).
    # `match_id` is kept for DM back-compat (null for groups and staff_dm). Clients branch on
    # `kind`.
    conversation_id: UUID
    kind: str  # 'dm' | 'group' | 'staff_dm'
    match_id: UUID | None = None
    partner: ProfilePublic | None = None  # dm / staff_dm only
    # Staff identity context for the partner, when they hold a verified campus position —
    # lets a student see *who* is messaging them (e.g. "Officer Jane Doe · Campus Security").
    partner_position_title: str | None = None
    partner_department: str | None = None
    group: GroupThreadInfo | None = None  # group only
    latest_message: MessageRead | None
    # The most recent reaction someone else left on one of my messages here, if any. Additive —
    # see [ThreadReactionPreview]; it does not move the row or change the unread count.
    latest_reaction: ThreadReactionPreview | None = None
    # Whether the viewer muted this conversation (no message or reaction pushes).
    muted: bool = False
    # The viewer's own arrangement: pinned to the top, or archived out of the main list.
    pinned_at: datetime | None = None
    archived: bool = False
    # DM partner online right now, when the viewer may see it (see `shared/presence.py`).
    partner_online: bool = False


class ThreadMuteRequest(BaseModel):
    muted: bool


class ThreadStateRequest(BaseModel):
    """Pin or archive a chat for yourself. Omitted fields are left as they are."""

    pinned: bool | None = None
    archived: bool | None = None


class ThreadStateRead(BaseModel):
    pinned_at: datetime | None
    archived: bool


class MessageSearchHit(BaseModel):
    """One message matching a search, with enough of its chat to show and open it."""

    message_id: UUID
    # The addressing id the app opens the chat by (match id for a DM, conversation id otherwise).
    thread_id: UUID
    kind: str  # 'dm' | 'staff_dm' | 'group'
    title: str  # the partner's or the group's name
    avatar_url: str | None = None
    group_id: UUID | None = None
    sender_id: UUID
    snippet: str
    created_at: datetime


class PresenceRead(BaseModel):
    """A DM partner's online state, as the viewer is allowed to see it.

    `visible` is false when either side has hidden their status — reciprocal, as in WhatsApp —
    and then `online` is false and `last_seen_at` null, so a hidden status reveals nothing.
    """

    user_id: UUID
    visible: bool
    online: bool = False
    last_seen_at: datetime | None = None


class UnreadSummary(BaseModel):
    """Total unread + per-conversation counts (conversations with 0 unread are omitted)."""

    total: int
    per_conversation: dict[UUID, int]


class RecipientSearchResult(BaseModel):
    """A lightweight, message-composer-facing user match (not the full profile)."""

    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    role: str
    position_title: str | None = None
    department: str | None = None


class MessagingCapabilities(BaseModel):
    can_message_anyone: bool
    staff_messaging_enabled: bool
