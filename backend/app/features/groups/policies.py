"""Group authorization — one place for every "can this member do X?" decision.

Keeping these here (rather than scattering role checks through the router) means the group
invariants are stated once and enforced consistently:

- a group always has an owner;
- owner-only actions (delete, transfer ownership, change core settings) are never granted to
  plain admins;
- admins manage membership (approve, invite, remove, ban) but cannot touch the owner;
- a banned member cannot rejoin.
"""

from __future__ import annotations

from enum import StrEnum

ROLE_RANK = {'member': 0, 'admin': 1, 'owner': 2}


class GroupAction(StrEnum):
    SEND_MESSAGE = 'send_message'
    INVITE = 'invite'
    APPROVE_REQUEST = 'approve_request'
    REMOVE_MEMBER = 'remove_member'
    BAN_MEMBER = 'ban_member'
    EDIT_GROUP = 'edit_group'
    DELETE_GROUP = 'delete_group'
    TRANSFER_OWNERSHIP = 'transfer_ownership'


# Minimum role required for each action. Owner-only actions are listed explicitly so an admin
# can never be mistaken for an owner.
_MIN_ROLE = {
    GroupAction.SEND_MESSAGE: 'member',
    GroupAction.INVITE: 'admin',
    GroupAction.APPROVE_REQUEST: 'admin',
    GroupAction.REMOVE_MEMBER: 'admin',
    GroupAction.BAN_MEMBER: 'admin',
    GroupAction.EDIT_GROUP: 'admin',
    GroupAction.DELETE_GROUP: 'owner',
    GroupAction.TRANSFER_OWNERSHIP: 'owner',
}


def can(role: str | None, action: GroupAction) -> bool:
    """True if an *active* member with `role` may perform `action`. `None` = not a member."""
    if role is None:
        return False
    return ROLE_RANK.get(role, -1) >= ROLE_RANK[_MIN_ROLE[action]]


def can_moderate(actor_role: str | None, target_role: str) -> bool:
    """Whether `actor_role` may remove/ban/demote a member with `target_role`.

    You must strictly outrank the target — so an admin can act on members but not on other
    admins or the owner, and the owner is never a valid target of moderation.
    """
    if actor_role is None or target_role == 'owner':
        return False
    return ROLE_RANK.get(actor_role, -1) > ROLE_RANK.get(target_role, 99)
