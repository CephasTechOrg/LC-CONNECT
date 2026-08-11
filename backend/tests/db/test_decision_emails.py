"""Decision-outcome emails — every admin decision must reach the person it affects.

Each of these paths used to end at the audit log: the person waiting on the decision was told
nothing, anywhere. These lock in that an email is attempted, addressed correctly, and carries
the reviewer's note.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from sqlalchemy import select

from app.features.admin import admins as admins_service
from app.features.admin import campus_positions as positions_admin
from app.features.admin import employers as employers_admin
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import upsert_primary_position
from app.models import AdminMembership, EmployerAccount, EmployerOrganization, Profile


@pytest.fixture
def sent(monkeypatch):
    """Capture every decision email instead of sending it."""
    calls: list[tuple[str, str, dict]] = []

    def _capture(name):
        def _fn(to_email, **kwargs):
            calls.append((name, to_email, kwargs))

        return _fn

    for module in (admins_service, positions_admin, employers_admin):
        for attr in ('send_admin_access_granted_email', 'send_position_decision_email',
                     'send_employer_rejected_email'):
            if hasattr(module, attr):
                monkeypatch.setattr(module, attr, _capture(attr))
    return calls


async def _super_admin(db, factory):
    admin = await factory.user(display_name='Super Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role='super_admin'))
    await db.commit()
    return admin


# ── gap 1: promoting an EXISTING account sends no Supabase invite ───────────────────


async def test_promoting_existing_account_emails_them(db, factory, sent, monkeypatch):
    """The common case: someone who already uses LC Connect is made an admin. No invite email is
    generated (they already have an identity), so this is the only thing that tells them."""
    monkeypatch.setattr(admins_service, 'invite_auth_user', lambda email, **kw: str(uuid4()))
    actor = await _super_admin(db, factory)
    target = await factory.user(display_name='Existing Staff')
    target.auth_user_id = uuid4()  # already has a Supabase identity
    await db.commit()

    await admins_service.invite_admin(db, actor=actor, email=target.email, role='content_admin')

    assert [(n, e) for n, e, _ in sent] == [('send_admin_access_granted_email', target.email)]


async def test_brand_new_invitee_is_not_double_emailed(db, factory, sent, monkeypatch):
    """A genuinely new invitee already gets the branded Supabase invite — sending the
    access-granted notice too would be a duplicate."""
    monkeypatch.setattr(admins_service, 'invite_auth_user', lambda email, **kw: str(uuid4()))
    actor = await _super_admin(db, factory)

    await admins_service.invite_admin(
        db, actor=actor, email='brand.new@livingstone.edu', role='auditor'
    )

    assert sent == []


# ── gap 2: campus position review was entirely silent ───────────────────────────────


async def _pending_position(db, factory):
    staff = await factory.user(display_name='Staff')
    staff.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == staff.id))).scalar_one()
    position = await upsert_primary_position(
        db, staff, profile,
        CampusPositionCreate(
            category='advising', official_title='Advisor',
            department='Student Success', contact_email=staff.email,
        ),
    )
    return staff, position


async def test_position_approval_emails_the_owner(db, factory, sent):
    actor = await _super_admin(db, factory)
    staff, position = await _pending_position(db, factory)

    await positions_admin.approve_position(db, actor=actor, position_id=position.id)

    assert len(sent) == 1
    name, to_email, kwargs = sent[0]
    assert (name, to_email, kwargs['outcome']) == ('send_position_decision_email', staff.email, 'approved')


async def test_position_rejection_carries_the_review_note(db, factory, sent):
    """The note is the whole point of a rejection — it was written and never delivered."""
    actor = await _super_admin(db, factory)
    staff, position = await _pending_position(db, factory)

    await positions_admin.reject_position(
        db, actor=actor, position_id=position.id, review_note='Title does not match HR records'
    )

    name, to_email, kwargs = sent[0]
    assert name == 'send_position_decision_email'
    assert to_email == staff.email
    assert kwargs['outcome'] == 'rejected'
    assert kwargs['review_note'] == 'Title does not match HR records'


async def test_position_revocation_emails_the_owner(db, factory, sent):
    actor = await _super_admin(db, factory)
    staff, position = await _pending_position(db, factory)
    await positions_admin.approve_position(db, actor=actor, position_id=position.id)
    sent.clear()

    await positions_admin.revoke_position(
        db, actor=actor, position_id=position.id, review_note='No longer employed'
    )

    name, to_email, kwargs = sent[0]
    assert (name, to_email, kwargs['outcome']) == ('send_position_decision_email', staff.email, 'revoked')


# ── gap 3: employer rejection was silent ────────────────────────────────────────────


async def test_employer_rejection_emails_the_contact(db, factory, sent):
    actor = await _super_admin(db, factory)
    org = EmployerOrganization(name='Acme Corp', status='pending')
    db.add(org)
    await db.flush()
    db.add(EmployerAccount(organization_id=org.id, email='hr@acme.com', display_name='HR'))
    await db.commit()

    await employers_admin.reject_organization(
        db, actor=actor, org_id=org.id, reason='Could not verify the organization'
    )

    name, to_email, kwargs = sent[0]
    assert name == 'send_employer_rejected_email'
    assert to_email == 'hr@acme.com'
    assert kwargs['review_note'] == 'Could not verify the organization'
