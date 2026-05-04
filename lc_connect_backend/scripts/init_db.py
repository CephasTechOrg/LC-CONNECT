import asyncio

from app.database import Base, engine, AsyncSessionLocal
from app import models  # noqa: F401 - imports models so metadata is registered
from app.seed import seed_lookup_data


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSessionLocal() as db:
        await seed_lookup_data(db)

    print('Database tables created and lookup data seeded.')


if __name__ == '__main__':
    asyncio.run(main())
