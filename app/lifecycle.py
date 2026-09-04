import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
import logging
from typing import AsyncIterator

from fastapi import FastAPI

from app.services.inventory import InventoryService
from app.settings import Settings

logger = logging.getLogger("inventory.lifecycle")


@dataclass(slots=True)
class RuntimeState:
    settings: Settings
    service: InventoryService
    accepting_requests: bool = False
    warmed: bool = False
    warmup_task: asyncio.Task[None] | None = field(default=None, repr=False)

    @property
    def ready(self) -> bool:
        """Return whether this process can truthfully serve inventory traffic."""
        return self.accepting_requests and self.warmed

    async def warm(self) -> None:
        logger.info("inventory warmup started")
        await asyncio.sleep(self.settings.warmup_seconds)
        self.warmed = True
        logger.info("inventory warmup completed")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = Settings.from_environment()
    state = RuntimeState(
        settings=settings,
        service=InventoryService(
            warehouse=settings.warehouse,
            response_delay=settings.request_seconds,
        ),
    )
    app.state.runtime = state

    # The process can answer platform probes immediately, but readiness remains
    # false until warmup has completed and inventory data is serviceable.
    state.accepting_requests = True
    state.warmup_task = asyncio.create_task(state.warm())
    logger.info("inventory process started")

    try:
        yield
    finally:
        # Stop advertising application readiness before shutdown cleanup.
        state.accepting_requests = False

        if state.warmup_task is not None and not state.warmup_task.done():
            state.warmup_task.cancel()
            try:
                await state.warmup_task
            except asyncio.CancelledError:
                pass

        # Kubernetes supplies enough termination grace time for this bounded
        # cleanup period after the preStop endpoint-drain delay.
        await asyncio.sleep(settings.shutdown_delay_seconds)
        logger.info("inventory process shutdown completed")
