from __future__ import annotations

from typing import Any, Dict, Optional
from mangum import Mangum
from app.main import app

_handlers: dict[str, Mangum] = {}

def _get_stage(event: Dict[str, Any]) -> Optional[str]:
    stage = (event.get("requestContext") or {}).get("stage")
    if not stage or stage == "$default":
        return None
    return stage

def lambda_handler(event: Dict[str, Any], context: Any):
    stage = _get_stage(event)
    base_path = f"/{stage}" if stage else ""

    # ✅ garante root_path mesmo se o adapter não preencher no scope
    app.root_path = base_path

    if base_path not in _handlers:
        if base_path:
            _handlers[base_path] = Mangum(
                app,
                lifespan="off",
                api_gateway_base_path=base_path,
            )
        else:
            _handlers[base_path] = Mangum(app, lifespan="off")

    return _handlers[base_path](event, context)
