from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class StockResponse(BaseModel):
    model_config = ConfigDict(frozen=True)

    sku: str = Field(min_length=2, max_length=64)
    available: bool
    quantity: int = Field(ge=0)
    warehouse: str
    checked_at: datetime


class HealthResponse(BaseModel):
    model_config = ConfigDict(frozen=True)

    status: str
    service: str


class ErrorResponse(BaseModel):
    model_config = ConfigDict(frozen=True)

    code: str
    message: str
