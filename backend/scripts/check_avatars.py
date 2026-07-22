"""One-off: print Supabase-linked users and avatar URLs from local Postgres."""
from __future__ import annotations

import asyncio

from sqlalchemy import text

from app.database import AsyncSessionLocal


async def main() -> None:
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            text(
                """
                SELECT u.email, p.display_name, u.id::text, u.auth_user_id::text, p.avatar_url
                FROM users u
                JOIN profiles p ON p.user_id = u.id
                WHERE u.auth_user_id IS NOT NULL
                ORDER BY u.created_at DESC
                """
            )
        )
        rows = result.all()
        print(f"supabase_users={len(rows)}")
        for email, name, app_id, auth_id, avatar in rows:
            print("---")
            print(f"email={email}")
            print(f"display_name={name}")
            print(f"app_user_id={app_id}")
            print(f"auth_user_id={auth_id}")
            print(f"avatar_url={avatar}")


if __name__ == "__main__":
    asyncio.run(main())
