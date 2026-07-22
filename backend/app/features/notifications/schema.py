from typing import Literal

from pydantic import BaseModel, Field


class DeviceRegister(BaseModel):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal['ios', 'android', 'web']
