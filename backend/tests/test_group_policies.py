"""Group permission matrix + moderation rules (pure, no DB)."""

from app.features.groups.policies import GroupAction, can, can_moderate


def test_members_can_only_send():
    assert can('member', GroupAction.SEND_MESSAGE)
    assert not can('member', GroupAction.INVITE)
    assert not can('member', GroupAction.APPROVE_REQUEST)
    assert not can('member', GroupAction.DELETE_GROUP)


def test_admins_manage_membership_but_not_ownership():
    assert can('admin', GroupAction.INVITE)
    assert can('admin', GroupAction.APPROVE_REQUEST)
    assert can('admin', GroupAction.REMOVE_MEMBER)
    assert can('admin', GroupAction.EDIT_GROUP)
    # Owner-only actions are NOT granted to admins.
    assert not can('admin', GroupAction.DELETE_GROUP)
    assert not can('admin', GroupAction.TRANSFER_OWNERSHIP)


def test_owner_can_do_everything():
    for action in GroupAction:
        assert can('owner', action)


def test_non_member_can_do_nothing():
    for action in GroupAction:
        assert not can(None, action)


def test_moderation_requires_strictly_outranking_the_target():
    assert can_moderate('admin', 'member')       # admin > member ✓
    assert can_moderate('owner', 'admin')        # owner > admin ✓
    assert not can_moderate('admin', 'admin')    # equal rank ✗
    assert not can_moderate('admin', 'owner')    # owner is never a target ✗
    assert not can_moderate('member', 'member')  # members can't moderate ✗
    assert not can_moderate(None, 'member')      # non-member ✗
