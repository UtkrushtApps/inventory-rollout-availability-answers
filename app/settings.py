from dataclasses import dataclass
import os


def _float_setting(name: str, default: float) -> float:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default

    try:
        value = float(raw_value)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number") from exc

    if value < 0:
        raise ValueError(f"{name} cannot be negative")
    return value


@dataclass(frozen=True, slots=True)
class Settings:
    service_name: str
    warehouse: str
    warmup_seconds: float
    request_seconds: float
    shutdown_delay_seconds: float

    @classmethod
    def from_environment(cls) -> "Settings":
        return cls(
            service_name=os.getenv("SERVICE_NAME", "inventory-api"),
            warehouse=os.getenv("WAREHOUSE", "north-america-primary"),
            warmup_seconds=_float_setting("WARMUP_SECONDS", 4.0),
            request_seconds=_float_setting("REQUEST_SECONDS", 0.35),
            shutdown_delay_seconds=_float_setting(
                "SHUTDOWN_DELAY_SECONDS",
                3.0,
            ),
        )
