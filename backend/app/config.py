from dataclasses import dataclass, field
import os
from pathlib import Path

from dotenv import load_dotenv


BACKEND_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    api_key: str = field(default="", repr=False)
    model: str = "gpt-5.4-mini"
    timeout: float = 120
    max_output_tokens: int = 12_000
    transcription_model: str = "gpt-4o-transcribe-diarize"
    plain_transcription_model: str = "gpt-transcribe"
    transcription_timeout: float = 600
    max_audio_bytes: int = 100 * 1024 * 1024
    max_audio_seconds: int = 3600
    origins: tuple[str, ...] = ("http://127.0.0.1:8080", "http://localhost:8080")

    @classmethod
    def load(cls):
        load_dotenv(BACKEND_ROOT / ".env.local", override=False)
        return cls(
            api_key=os.environ.get("OPENAI_API_KEY", ""),
            model=os.environ.get("OPENAI_MODEL", "gpt-5.4-mini"),
            timeout=float(os.environ.get("OPENAI_TIMEOUT_SECONDS", "120")),
            max_output_tokens=int(os.environ.get("OPENAI_MAX_OUTPUT_TOKENS", "12000")),
            transcription_model=os.environ.get("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-transcribe-diarize"),
            plain_transcription_model=os.environ.get("OPENAI_PLAIN_TRANSCRIPTION_MODEL", "gpt-transcribe"),
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
