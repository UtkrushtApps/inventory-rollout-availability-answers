from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse

from app.lifecycle import RuntimeState
from app.models import HealthResponse

router = APIRouter(tags=["platform"])


@router.get("/live", response_model=HealthResponse)
async def liveness(request: Request) -> HealthResponse:
    runtime: RuntimeState = request.app.state.runtime
    return HealthResponse(
        status="alive",
        service=runtime.settings.service_name,
    )


@router.get(
    "/ready",
    response_model=HealthResponse,
    responses={503: {"model": HealthResponse}},
)
async def readiness(request: Request) -> HealthResponse | JSONResponse:
    runtime: RuntimeState = request.app.state.runtime

    # Readiness must represent application-level serviceability, not merely a
    # running HTTP process. This keeps warming or draining pods out of the
    # Service's ready EndpointSlice backends.
    if runtime.ready:
        return HealthResponse(
            status="ready",
            service=runtime.settings.service_name,
        )

    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content={
            "status": "not-ready",
            "service": runtime.settings.service_name,
        },
    )
