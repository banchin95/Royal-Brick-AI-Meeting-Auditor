import asyncio
import json

from openai import (
    APIConnectionError, APIStatusError, APITimeoutError, AsyncOpenAI,
    AuthenticationError, PermissionDeniedError, RateLimitError,
)
from pydantic import ValidationError

from .config import Settings, load_instructions, BACKEND_ROOT
from .schemas import AnalyzeRequest, parse_transcript
from .scoring import InvalidAudit, build_report
from .grounding import GroundedAudit, grounded_utterances, resolve_audit
from .preparation import (
    PrepareRequest, GeneratedPreparation, InvalidPreparation, preparation_source, build_preparation,
)


class AnalysisError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status = status
        self.code = code
        self.message = message
        super().__init__(code)  # Не сохраняем текст разговора или сообщения SDK.


class AuditService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.instructions = load_instructions()
        self.client = AsyncOpenAI(api_key=settings.api_key, base_url="https://api.openai.com/v1", timeout=settings.timeout - 5,
                                  max_retries=0) if settings.api_key else None
        self._gate = asyncio.Lock()

    async def close(self):
        if self.client:
            await self.client.close()

    async def analyze(self, request: AnalyzeRequest):
        turns = parse_transcript(request.transcript)
        utterances, catalog = grounded_utterances(turns)
        payload = {
            "participants": [p.model_dump() for p in request.participants],
            "is_partial": request.is_partial,
            "additional_context": request.context,
            "utterances": utterances,
        }
        return await self._generate(payload, self.instructions, GroundedAudit,
            lambda result: build_report(resolve_audit(result, catalog), turns, self.settings.model, request.is_partial))

    async def prepare_transcript(self, request: PrepareRequest):
        try:
            source = preparation_source(request.transcript, request.reconcile_speakers)
        except ValueError as error:
            raise AnalysisError(422, "invalid_preparation_input", str(error)) from None
        instructions = (BACKEND_ROOT / "prompts" / "prepare_transcript.txt").read_text(encoding="utf-8")
        payload = {"source_has_speakers": source.labelled,
                   "allow_speaker_reconciliation": source.reconcile, "units": source.units}
        return await self._generate(payload, instructions, GeneratedPreparation,
            lambda result: build_preparation(result, source, self.settings.model))

    async def _generate(self, payload, instructions, output_type, convert):
        if self.client is None:
            raise AnalysisError(503, "api_not_configured",
                                "API-ключ на сервере не настроен. Демо остаётся доступным.")
        try:
            await asyncio.wait_for(self._gate.acquire(), timeout=0.05)
        except TimeoutError:
            raise AnalysisError(429, "analysis_busy", "Уже выполняется анализ. Дождитесь его завершения.") from None
        try:
            async with asyncio.timeout(self.settings.timeout):
                response = await self.client.responses.parse(
                    model=self.settings.model,
                    instructions=instructions,
                    input=[{"role": "user", "content": json.dumps(payload, ensure_ascii=False)}],
                    text_format=output_type,
                    max_output_tokens=self.settings.max_output_tokens,
                    reasoning={"effort": "low"},
                    store=False,
                )
            if response.status != "completed":
                raise AnalysisError(502, "incomplete_response",
                                    "Модель не завершила отчёт. Попробуйте сократить текст и повторить анализ.")
            if response.output_parsed is None:
                raise AnalysisError(502, "model_refusal",
                                    "Модель не сформировала отчёт для этого текста. Проверьте содержание разговора.")
            return convert(response.output_parsed)
        except (APITimeoutError, TimeoutError):
            raise AnalysisError(504, "analysis_timeout", "Время анализа истекло. Попробуйте повторить запрос позже.") from None
        except AuthenticationError:
            raise AnalysisError(503, "api_credentials", "Серверный API-ключ недействителен или истёк. Нужно обновить его на backend.") from None
        except PermissionDeniedError:
            raise AnalysisError(503, "api_access", "OpenAI отклонил доступ к API. Проверьте доступ проекта и условия подключения.") from None
        except RateLimitError as error:
            quota = error.code in ("insufficient_quota", "billing_hard_limit_reached")
            raise AnalysisError(503 if quota else 429,
                                "quota_exceeded" if quota else "rate_limit",
                                "На API-счёте OpenAI нет доступной квоты. Проверьте баланс и лимиты проекта."
                                if quota else "Достигнут лимит запросов OpenAI. Попробуйте позже.") from None
        except APIConnectionError:
            raise AnalysisError(503, "api_connection", "Сервер не смог подключиться к OpenAI. Проверьте соединение и повторите позже.") from None
        except APIStatusError:
            raise AnalysisError(502, "provider_error", "Сервис ИИ вернул ошибку. Проверьте модель и настройки backend.") from None
        except InvalidPreparation:
            raise AnalysisError(502, "invalid_preparation_response",
                                "Разметка ИИ не прошла проверку полноты текста или участников. Исходный текст сохранён.") from None
        except (ValidationError, InvalidAudit):
            raise AnalysisError(502, "invalid_model_response",
                                "Ответ ИИ не прошёл проверку структуры, баллов или цитат. Недостоверный отчёт не показан.") from None
        finally:
            self._gate.release()
