from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.openapi.docs import (
    get_swagger_ui_html,
    get_swagger_ui_oauth2_redirect_html,
)
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.api.v1.router import api_router
from app.core.exceptions import (
    business_rule_exception_handler,
    integrity_error_handler,
    validation_error_handler,
    BusinessRuleException
)

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=None,   # ✅ desativa docs padrão
    redoc_url=None,  # opcional
)

# Register exception handlers
app.add_exception_handler(BusinessRuleException, business_rule_exception_handler)
app.add_exception_handler(IntegrityError, integrity_error_handler)
app.add_exception_handler(RequestValidationError, validation_error_handler)

# Configure CORS
if settings.BACKEND_CORS_ORIGINS:
    origins = [str(origin).rstrip('/') for origin in settings.BACKEND_CORS_ORIGINS]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Requested-With"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

# Router
app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health")
def health_check():
    return {"status": "ok", "environment": "lambda"}

# ✅ Docs customizado: monta openapi_url com root_path (/prod)
@app.get("/docs", include_in_schema=False)
async def custom_docs(request: Request):
    root = request.scope.get("root_path") or getattr(app, "root_path", "") or ""
    openapi_url = f"{root}{settings.API_V1_STR}/openapi.json"
    oauth2_redirect_url = f"{root}/docs/oauth2-redirect"

    return get_swagger_ui_html(
        openapi_url=openapi_url,
        title=f"{app.title} - Swagger UI",
        oauth2_redirect_url=oauth2_redirect_url,
    )

@app.get("/docs/oauth2-redirect", include_in_schema=False)
async def swagger_redirect():
    return get_swagger_ui_oauth2_redirect_html()
