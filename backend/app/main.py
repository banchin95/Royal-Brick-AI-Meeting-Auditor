from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings
from .schemas import AnalyzeRequest
from .service import AnalysisError, AuditService


def create_app(settings: Settings | None = None, service=None) -> FastAPI:
    settings = settings or Settings.load()

    @asynccontextmanager
    async def lifespan(application):
        application.state.audit_service = service or AuditService(settings)
        yield
        if service is None:
            await application.state.audit_service.close()

    application = FastAPI(title="Royal Brick Meeting Auditor", version="0.3.0", lifespan=lifespan)
    application.add_middleware(CORSMiddleware, allow_origins=list(settings.origins),
                               allow_methods=["GET", "POST"], allow_headers=["Content-Type"])

    @application.exception_handler(AnalysisError)
    async def analysis_error(_request, error):
        return JSONResponse(status_code=error.status,
                            content={"error": {"code": error.code, "message": error.message}})

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request, error):
        first = error.errors()[0]
        message = first.get("msg", "Проверьте формат входных данных.")
        # Не возвращаем стандартное поле input с полным текстом разговора.
        return JSONResponse(status_code=422,
                            content={"error": {"code": "invalid_input", "message": message[:300]}})

    @application.get("/api/health")
    async def health():
        return {"status": "ok", "ai_configured": bool(settings.api_key),
                "model": settings.model, "version": "0.3.0"}

    @application.post("/api/analyze")
    async def analyze(body: AnalyzeRequest, request: Request):
        response = JSONResponse(await request.app.state.audit_service.analyze(body))
        response.headers["Cache-Control"] = "no-store"
        return response

    return application


app = create_app()
