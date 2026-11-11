from dataclasses import dataclass, field
import os
from pathlib import Path

from dotenv import load_dotenv


BACKEND_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    api_key: str = field(default="", repr=False)
    provider: str = "openai"
    model: str = "gpt-5.4-mini"
    timeout: float = 120
    max_output_tokens: int = 12_000
    transcription_model: str = "gpt-4o-transcribe-diarize"
    plain_transcription_model: str = "gpt-transcribe"
    transcription_timeout: float = 600
    max_audio_bytes: int = 100 * 1024 * 1024
    max_audio_seconds: int = 3600
    origins: tuple[str, ...] = ("http://127.0.0.1:8080", "http://localhost:8080")

    def __post_init__(self):
        if self.provider not in ("openai", "timeweb"):
            raise ValueError("AI_PROVIDER must be openai or timeweb")

    @property
    def base_url(self):
        # Only known providers; never send a key to an arbitrary environment URL.
        return "https://api.timeweb.ai/v1" if self.provider == "timeweb" else "https://api.openai.com/v1"

    @property
    def provider_name(self):
        return "Timeweb AI Gateway" if self.provider == "timeweb" else "OpenAI"

    @classmethod
    def load(cls):
        provider = os.environ.get("AI_PROVIDER", "openai")
        load_dotenv(BACKEND_ROOT / (".env.timeweb.local" if provider == "timeweb" else ".env.local"), override=False)
        timeweb = provider == "timeweb"
        return cls(
            provider=provider,
            api_key=os.environ.get("TIMEWEB_AI_TOKEN" if timeweb else "OPENAI_API_KEY", ""),
            model=os.environ.get("TIMEWEB_MODEL" if timeweb else "OPENAI_MODEL",
                                 "openai/gpt-5.4-mini" if timeweb else "gpt-5.4-mini"),
            timeout=float(os.environ.get("OPENAI_TIMEOUT_SECONDS", "120")),
            max_output_tokens=int(os.environ.get("OPENAI_MAX_OUTPUT_TOKENS", "12000")),
            transcription_model=os.environ.get("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-transcribe-diarize"),
            plain_transcription_model=os.environ.get("TIMEWEB_TRANSCRIPTION_MODEL" if timeweb else "OPENAI_PLAIN_TRANSCRIPTION_MODEL",
                                                     "openai/gpt-4o-transcribe" if timeweb else "gpt-transcribe"),
            transcription_timeout=float(os.environ.get("TRANSCRIPTION_TIMEOUT_SECONDS", "600")),
            origins=tuple(origin.strip() for origin in os.environ.get(
                "CORS_ORIGINS", "http://127.0.0.1:8080,http://localhost:8080"
            ).split(",") if origin.strip()),
        )


def load_instructions() -> str:
    prompts = BACKEND_ROOT / "prompts"
    original = prompts / "royal_brick.local.txt"
    source = original if original.is_file() else prompts / "royal_brick.txt"
    return source.read_text(encoding="utf-8") + "\n\n" + (prompts / "response_contract.txt").read_text(encoding="utf-8")
