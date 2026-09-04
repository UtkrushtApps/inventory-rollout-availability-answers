import asyncio
from datetime import UTC, datetime

from app.models import StockResponse


class InventoryService:
    def __init__(self, warehouse: str, response_delay: float) -> None:
        self._warehouse = warehouse
        self._response_delay = response_delay

    async def lookup(self, sku: str) -> StockResponse:
        await asyncio.sleep(self._response_delay)
        normalized_sku = sku.upper()
        checksum = sum(ord(character) for character in normalized_sku)
        quantity = 5 + checksum % 91
        return StockResponse(
            sku=normalized_sku,
            available=quantity > 0,
            quantity=quantity,
            warehouse=self._warehouse,
            checked_at=datetime.now(UTC),
        )
