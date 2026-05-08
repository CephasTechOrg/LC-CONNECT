import asyncio

from sqlalchemy import text

from app.database import AsyncSessionLocal, Base, engine
from app import models  # noqa: F401 — registers all models with metadata
from app.seed import seed_lookup_data


async def main() -> None:
    # Alembic handles schema migrations now.
    # Base.metadata.create_all is kept as a fallback for local testing without alembic, 
    # but in production alembic should run first.
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as db:
        await seed_lookup_data(db)

    print('Database tables created/updated and lookup data seeded.')


if __name__ == '__main__':
    asyncio.run(main())
