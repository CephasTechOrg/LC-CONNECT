import asyncio

from sqlalchemy import text

from app.database import AsyncSessionLocal, Base, engine
from app import models  # noqa: F401 — registers all models with metadata
from app.seed import seed_lookup_data


async def _migrate(conn) -> None:
    """Add columns that may not exist on already-created tables."""
    await conn.execute(text("""
        ALTER TABLE users
            ADD COLUMN IF NOT EXISTS verify_otp_hash VARCHAR(64),
            ADD COLUMN IF NOT EXISTS verify_otp_expires_at TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS reset_otp_hash VARCHAR(64),
            ADD COLUMN IF NOT EXISTS reset_otp_expires_at TIMESTAMPTZ
    """))


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _migrate(conn)

    async with AsyncSessionLocal() as db:
        await seed_lookup_data(db)

    print('Database tables created/updated and lookup data seeded.')


if __name__ == '__main__':
    asyncio.run(main())
