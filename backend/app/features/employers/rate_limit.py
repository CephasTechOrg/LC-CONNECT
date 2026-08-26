"""Employer-scoped rate limiting — mirrors `UserRateLimit` (`app/shared/rate_limit.py`), but keyed
on `EmployerAccount.id` instead of `User.id` since employers aren't `User` rows. Reuses the same
generic `RateLimiter` bucket; only the FastAPI dependency wiring differs.
"""

from __future__ import annotations

from fastapi import Depends, HTTPException, status

from app.config import settings
from app.features.employers.auth import EmployerAuthContext, require_approved_employer
from app.shared.rate_limit import RateLimiter

_DAY = 86400


class EmployerRateLimit:
    def __init__(self, limit: int, per_seconds: float, message: str) -> None:
        self._message = message
        self._limiter = RateLimiter(limit, per_seconds, name='employer_opportunity_submit')

    async def __call__(
        self, ctx: EmployerAuthContext = Depends(require_approved_employer)
    ) -> EmployerAuthContext:
        if not await self._limiter.aallow(ctx.account.id):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=self._message)
        return ctx


opportunity_submit_limit = EmployerRateLimit(
    settings.rate_limit_employer_opportunity_submissions_per_day, _DAY,
    "You've submitted too many opportunities today — try again tomorrow.",
)
