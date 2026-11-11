import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient
import httpx2
from openai import RateLimitError
import pytest

from backend.app.config import Settings
from backend.app.main import create_app
from backend.app.schemas import AnalyzeRequest
from backend.app.grounding import GroundedAudit
from backend.app.service import AnalysisError, AuditService
from test_audit import INPUT, finish, raw_audit  # shared deterministic fixtures


class FakeService:
    def __init__(self, report):
        self.report = report
        self.calls = 0

    async def analyze(self, request):
        self.calls += 1
        return self.report


def test_api_contract_and_cors_without_live_requests(raw_audit):
    service = FakeService(finish(raw_audit))
    with TestClient(create_app(Settings(), service)) as client:
        health = client.get("/api/health")
        assert health.status_code == 200 and health.json()["ai_configured"] is False
        response = client.post("/api/analyze", json=INPUT,
                               headers={"Origin": "http://127.0.0.1:8080"})
        assert response.status_code == 200 and len(response.json()["sections"]) == 13
        assert response.headers["Cache-Control"] == "no-store"
        assert response.headers["access-control-allow-origin"] == "http://127.0.0.1:8080"
        assert service.calls == 1
        denied = client.options("/api/analyze", headers={
            "Origin": "https://unrelated.example", "Access-Control-Request-Method": "POST"})
        assert denied.status_code == 400


def test_validation_errors_do_not_echo_transcript(raw_audit):
    service = FakeService(finish(raw_audit))
    with TestClient(create_app(Settings(), service)) as client:
        response = client.post("/api/analyze", json={**INPUT, "transcript": "PRIVATE_SENTINEL"})
        assert response.status_code == 422
        assert "PRIVATE_SENTINEL" not in response.text
        assert service.calls == 0


def test_missing_key_is_an_explicit_error():
    with TestClient(create_app(Settings())) as client:
        response = client.post("/api/analyze", json=INPUT)
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "api_not_configured"


def test_provider_uses_structured_outputs_and_no_storage(raw_audit):
    async def run():
        service = AuditService(Settings(api_key="test-only-placeholder"))
        service.client.responses.parse = AsyncMock(return_value=SimpleNamespace(
            status="completed", output_parsed=GroundedAudit.model_validate(raw_audit)))
        try:
            response = await service.analyze(AnalyzeRequest.model_validate(INPUT))
            options = service.client.responses.parse.call_args.kwargs
            assert options["store"] is False
            assert options["text_format"] is GroundedAudit
            assert '"fragments":' in options["input"][0]["content"]
            assert '"is_partial": true' in options["input"][0]["content"]
            assert len(response["sections"]) == 13
        finally:
            await service.close()
    asyncio.run(run())


def test_quota_error_is_sanitized():
    async def run():
        service = AuditService(Settings(api_key="test-only-placeholder"))
        error = RateLimitError("PRIVATE_PROVIDER_MESSAGE", response=httpx2.Response(429,
            request=httpx2.Request("POST", "https://api.openai.com/v1/responses")),
            body={"code": "insufficient_quota"})
        service.client.responses.parse = AsyncMock(side_effect=error)
        try:
            with pytest.raises(AnalysisError) as raised:
                await service.analyze(AnalyzeRequest.model_validate(INPUT))
            assert raised.value.code == "quota_exceeded"
            assert "PRIVATE_PROVIDER_MESSAGE" not in raised.value.message
            assert not service._gate.locked()
        finally:
            await service.close()
    asyncio.run(run())


def test_backend_does_not_queue_multiple_paid_requests():
    async def run():
        service = AuditService(Settings(api_key="test-only-placeholder"))
        await service._gate.acquire()
        try:
            with pytest.raises(AnalysisError) as raised:
                await service.analyze(AnalyzeRequest.model_validate(INPUT))
            assert raised.value.code == "analysis_busy"
        finally:
            service._gate.release()
            await service.close()
    asyncio.run(run())
