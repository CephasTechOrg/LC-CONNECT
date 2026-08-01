"""One-time Super Admin bootstrap (Blueprint Bond Phase 3).

Run this exactly once, by the platform builder, against whichever Supabase project the backend
is actually configured against (the same real database used everywhere — there is no separate
"script" database). It creates the very first admin through **Supabase Auth** (a real invite
email, so the builder sets their own password and enrolls in MFA like every other admin — never
a script-set password) and seeds them with the `super_admin` scope.

Every admin after this one is created through the in-app invite flow
(`POST /admin/admins/invite`), never by running this script again. Refuses to run if a
`super_admin` already exists, to guard against exactly that mistake.
"""

import asyncio

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models import AdminMembership, Profile, User
from app.shared.supabase_admin import invite_auth_user


async def main() -> None:
    async with AsyncSessionLocal() as db:
        existing_super_admin = (
            await db.execute(select(AdminMembership.id).where(AdminMembership.role == 'super_admin'))
        ).scalar_one_or_none()
        if existing_super_admin is not None:
            print(
                'A Super Admin already exists. This script only ever bootstraps the first one — '
                'invite any further admin through the admin portal instead.'
            )
            return

        email = input('Super Admin email: ').strip().lower()
        display_name = input('Display name: ').strip() or 'Admin'

        user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()

        # An existing account (e.g. already-signed-in staff/student) already has a real Supabase
        # identity — inviting it again would fail (Supabase rejects invites for an email that's
        # already registered). Only invite when there's genuinely no auth identity yet.
        sent_invite = False
        if user is not None and user.auth_user_id is not None:
            auth_user_id = user.auth_user_id
        else:
            auth_user_id = invite_auth_user(email)
            if auth_user_id is None:
                print(
                    'Could not send the Supabase invite (is SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY '
                    'configured?). Nothing was created — fix the config and try again.'
                )
                return
            sent_invite = True

        if user is None:
            user = User(email=email, role='admin', auth_user_id=auth_user_id, is_verified=True)
            db.add(user)
            await db.flush()
            db.add(Profile(user_id=user.id, display_name=display_name))
        else:
            user.role = 'admin'
            user.is_verified = True
            if user.auth_user_id is None:
                user.auth_user_id = auth_user_id
        await db.flush()

        db.add(AdminMembership(user_id=user.id, role='super_admin', invited_by_id=user.id))
        await db.commit()

        if sent_invite:
            print(f'Invited {email} as Super Admin — check that inbox to set a password and enroll in MFA.')
        else:
            print(
                f'{email} already had a Supabase identity — granted Super Admin directly, no new '
                'invite email sent. Sign in with your existing password; MFA enrollment happens on '
                'your next admin login if you haven\'t set it up yet.'
            )


if __name__ == '__main__':
    asyncio.run(main())
