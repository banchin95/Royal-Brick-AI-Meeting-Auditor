import asyncio

import pytest

from backend.app import config
from backend.app.compat import timeout
from backend.app.config import Settings


def test_timeweb_never_reuses_openai_credentials(monkeypatch):
    monkeypatch.setattr(config, "load_dotenv", lambda *args, **kwargs: None)
    monkeypatch.setenv("AI_PROVIDER", "timeweb")
    monkeypatch.setenv("OPENAI_API_KEY", "test-openai-placeholder")
    monkeypatch.delenv("TIMEWEB_AI_TOKEN", raising=False)
    assert Settings.load().api_key == ""
    monkeypatch.setenv("TIMEWEB_AI_TOKEN", "test-timeweb-placeholder")
    settings = Settings.load()
    assert settings.api_key == "test-timeweb-placeholder"
    assert settings.base_url == "https://api.timeweb.ai/v1"
    assert settings.model == "openai/gpt-5.4-mini"
    assert settings.plain_transcription_model == "openai/gpt-4o-transcribe"
    assert "test-timeweb-placeholder" not in repr(settings)


def test_openai_ignores_timeweb_credentials(monkeypatch):
    monkeypatch.setattr(config, "load_dotenv", lambda *args, **kwargs: None)
    monkeypatch.setenv("AI_PROVIDER", "openai")
    monkeypatch.setenv("TIMEWEB_AI_TOKEN", "test-timeweb-placeholder")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    assert Settings.load().api_key == ""
    assert Settings.load().base_url == "https://api.openai.com/v1"


def test_unknown_provider_fails_closed():
    with pytest.raises(ValueError, match="AI_PROVIDER"):
        Settings(provider="unknown")


def test_compatible_timeout_cancels_and_runs_cleanup():
    cleaned = []
    async def run():
        with pytest.raises((TimeoutError, asyncio.TimeoutError)):
            async with timeout(0.01):
                try:
                    await asyncio.sleep(10)
                finally:
                    cleaned.append(True)
    asyncio.run(run())
    assert cleaned == [True]
