"""FastAPI app entrypoint. Per docs/api-contract.md §1, §3.1."""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.config import settings

log = logging.getLogger("syncra")
logging.basicConfig(level=logging.INFO)


def create_app() -> FastAPI:
    app = FastAPI(
        title="Syncra API",
        version=settings.version,
        docs_url="/docs",
        openapi_url=f"{settings.api_prefix}/openapi.json",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get(f"{settings.api_prefix}/health", tags=["health"])
    async def health() -> dict:
        return {"status": "ok", "version": settings.version}

    from app.auth import router as auth_router
    from app.applications.router import router as applications_router
    from app.jobs.router import router as jobs_router
    from app.agent.router import router as agent_router

    app.include_router(auth_router, prefix=settings.api_prefix)
    app.include_router(applications_router, prefix=settings.api_prefix)
    app.include_router(jobs_router, prefix=settings.api_prefix)
    app.include_router(agent_router, prefix=settings.api_prefix)

    # Mounted as A ships their router:
    # from app.resumes.router import router as resumes_router      # Person A
    # app.include_router(resumes_router, prefix=settings.api_prefix)

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail
        if isinstance(detail, dict) and "type" in detail:
            body = {"error": detail}
        else:
            body = {
                "error": {
                    "type": _type_for_status(exc.status_code),
                    "message": str(detail),
                    "status_code": exc.status_code,
                }
            }
        return JSONResponse(status_code=exc.status_code, content=jsonable_encoder(body))

    @app.exception_handler(RequestValidationError)
    async def validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": {
                    "type": "validation",
                    "message": "Request validation failed.",
                    "status_code": 422,
                    "errors": jsonable_encoder(exc.errors()),
                }
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_handler(_: Request, exc: Exception) -> JSONResponse:
        log.exception("unhandled error: %s", exc)
        return JSONResponse(
            status_code=500,
            content={
                "error": {"type": "server", "message": "Internal server error.", "status_code": 500}
            },
        )

    return app


def _type_for_status(code: int) -> str:
    if code == 401:
        return "auth"
    if code == 403:
        return "auth"
    if code == 404:
        return "not_found"
    if code == 422:
        return "validation"
    if code == 429:
        return "rate_limited"
    if 400 <= code < 500:
        return "validation"
    return "server"


app = create_app()
