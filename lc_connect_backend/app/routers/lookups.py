from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Interest, Language, LookingForOption

router = APIRouter(prefix='/lookups', tags=['lookups'])


@router.get('')
async def get_lookups(db: AsyncSession = Depends(get_db)) -> dict[str, list[dict]]:
    interests = (await db.execute(select(Interest).order_by(Interest.name))).scalars().all()
    languages = (await db.execute(select(Language).order_by(Language.name))).scalars().all()
    looking_for = (await db.execute(select(LookingForOption).order_by(LookingForOption.id))).scalars().all()
    return {
        'interests': [{'id': item.id, 'name': item.name, 'category': item.category} for item in interests],
        'languages': [{'id': item.id, 'name': item.name} for item in languages],
        'looking_for': [{'id': item.id, 'code': item.code, 'name': item.name} for item in looking_for],
    }
