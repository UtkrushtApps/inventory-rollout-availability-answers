import logging
import time
from uuid import uuid4

from fastapi import FastAPI, Request

from app.lifecycle import lifespan
from app.routers import health, inventory

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

app = FastAPI(
    title="CartForge Inventory API",
    version="1.0.0",
    lifespan=lifespan,
)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("x-request-id") or str(uuid4())
    started = time.perf_counter()
    response = await call_next(request)
    response.headers["x-request-id"] = request_id
    response.headers["x-response-time-ms"] = str(
        round((time.perf_counter() - started) * 1000, 2)
    )
    return response


app.include_router(health.router)
app.include_router(inventory.router, prefix="/api/v1")
