from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, File, Form, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import Settings
from .schemas import AnalyzeRequest
from .service import AnalysisError, AuditService
from .audio import TranscriptionService
from .preparation import PrepareRequest
import shutil


def create_app(settings: Settings | None = None, service=None, transcription_service=None) -> FastAPI:
    settings = settings or Settings.load()

    @asynccontextmanager
    async def lifespan(application):
        application.state.audit_service = service or AuditService(settings)
        application.state.transcription_service = transcription_service or TranscriptionService(settings)
        yield
        if transcription_service is None:
            await application.state.transcription_service.close()
        if service is None:
            await application.state.audit_service.close()

    application = FastAPI(title="Royal Brick Meeting Auditor", version="0.5.1", lifespan=lifespan)
    application.add_middleware(CORSMiddleware, allow_origins=list(settings.origins),
                               allow_methods=["GET", "POST", "DELETE"], allow_headers=["Content-Type"])

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
                "model": settings.model, "version": "0.5.1",
                "audio_tools_ready": bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))}

    @application.post("/api/transcriptions", status_code=202)
    async def transcribe(request: Request, file: UploadFile = File(...), diarize: bool = Form(False)):
        try:
            result = await request.app.state.transcription_service.submit(file, diarize)
            return JSONResponse(result, status_code=202, headers={"Cache-Control": "no-store"})
        finally:
            await file.close()

    @application.get("/api/transcriptions/{job_id}")
    async def transcription_status(job_id: str, request: Request):
        return JSONResponse(request.app.state.transcription_service.get(job_id), headers={"Cache-Control": "no-store"})

    @application.delete("/api/transcriptions/{job_id}")
    async def cancel_transcription(job_id: str, request: Request):
        return JSONResponse(await request.app.state.transcription_service.cancel(job_id), headers={"Cache-Control": "no-store"})

    @application.post("/api/analyze")
    async def analyze(body: AnalyzeRequest, request: Request):
        response = JSONResponse(await request.app.state.audit_service.analyze(body))
        response.headers["Cache-Control"] = "no-store"
        return response

    @application.post("/api/prepare-transcript")
    async def prepare_transcript(body: PrepareRequest, request: Request):
        response = JSONResponse(await request.app.state.audit_service.prepare_transcript(body))
        response.headers["Cache-Control"] = "no-store"
        return response

    return application


app = create_app()
