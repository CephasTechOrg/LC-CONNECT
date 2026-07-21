import asyncio
import getpass

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models import Profile, User
from app.security import hash_password


async def main() -> None:
    email = input('Admin email: ').strip().lower()
    password = getpass.getpass('Admin password: ')
    display_name = input('Display name: ').strip() or 'Admin'

    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
        if user:
            user.role = 'admin'
            user.status = 'active'
            user.is_active = True
            user.is_verified = True
            print('Existing user promoted to admin.')
        else:
            user = User(email=email, password_hash=hash_password(password), role='admin', is_verified=True)
            db.add(user)
            await db.flush()
            db.add(Profile(user_id=user.id, display_name=display_name))
            print('New admin created.')
        await db.commit()


if __name__ == '__main__':
    asyncio.run(main())
