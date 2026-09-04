from fastapi import APIRouter, Path, Request, status
from fastapi.responses import JSONResponse

from app.lifecycle import RuntimeState
from app.models import ErrorResponse, StockResponse

router = APIRouter(tags=["inventory"])


@router.get(
    "/stock/{sku}",
    response_model=StockResponse,
    responses={503: {"model": ErrorResponse}},
)
async def get_stock(
    request: Request,
    sku: str = Path(min_length=2, max_length=64, pattern=r"^[A-Za-z0-9_-]+$"),
) -> StockResponse | JSONResponse:
    runtime: RuntimeState = request.app.state.runtime
    if not runtime.ready:
        # Keep the runtime 503 body consistent with the documented
        # ErrorResponse rather than wrapping it in FastAPI's `detail` field.
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "code": "inventory_unavailable",
                "message": "Inventory data is not serviceable",
            },
        )

    return await runtime.service.lookup(sku)
