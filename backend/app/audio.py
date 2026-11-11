"""Bounded local audio preparation and anonymous speaker-labelled transcription."""

import asyncio
from dataclasses import dataclass, field
import json
import math
import logging
import re
from pathlib import Path
import shutil
import tempfile
import time
import uuid

from openai import AsyncOpenAI, APIError, APITimeoutError, AuthenticationError, PermissionDeniedError, RateLimitError

from .config import Settings
from .service import AnalysisError


ALLOWED_EXTENSIONS = {".m4a", ".mp3", ".mp4", ".wav", ".webm", ".ogg", ".flac", ".aac", ".mpeg", ".mpga"}
MAX_CHUNK_SECONDS = 300  # Short requests avoid the slow whole-meeting diarization path.


async def run_media(*args, timeout):
    try:
        process = await asyncio.create_subprocess_exec(*args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    except FileNotFoundError:
        raise AnalysisError(503, "audio_tools_missing", "На backend нужны FFmpeg и ffprobe для подготовки аудио.") from None
    try:
        stdout, _stderr = await asyncio.wait_for(process.communicate(), timeout)
    except (TimeoutError, asyncio.CancelledError):
        if process.returncode is None:
            process.kill()
        await process.communicate()
        raise
    if process.returncode:
        raise AnalysisError(422, "invalid_audio", "Не удалось прочитать аудио. Проверьте файл и его формат.")
    return stdout


async def prepare_audio(source: Path, destination: Path, settings: Settings):
    info = json.loads(await run_media("ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=codec_type", "-of", "json", str(source), timeout=15))
    try:
        duration = float(info["format"]["duration"])
        if not math.isfinite(duration) or duration <= 0:
            duration = None
    except (KeyError, ValueError, TypeError):
        duration = None  # MediaRecorder WebM often has no duration header.
    if not any(
        stream.get("codec_type") == "audio" for stream in info.get("streams", [])
    ):
        raise AnalysisError(422, "invalid_audio", "В файле нет корректной аудиозаписи.")
    if duration is not None and duration > settings.max_audio_seconds:
        raise AnalysisError(422, "audio_too_long", "Для MVP загрузите запись длительностью не более 60 минут.")
    await run_media("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-threads", "1", "-i", str(source), "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000",
        "-codec:a", "libmp3lame", "-b:a", "48k", "-t", str(settings.max_audio_seconds + 1),
        "-map_metadata", "-1", str(destination), timeout=120)
    prepared_info = json.loads(await run_media("ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "json", str(destination), timeout=15))
    prepared_duration = float(prepared_info["format"]["duration"])
    if not math.isfinite(prepared_duration) or prepared_duration <= 0:
        raise AnalysisError(422, "invalid_duration", "Не удалось определить длительность записи.")
    if prepared_duration > settings.max_audio_seconds + 0.5:
        raise AnalysisError(422, "audio_too_long", "Для MVP загрузите запись длительностью не более 60 минут.")
    if destination.stat().st_size > 24_000_000:
        raise AnalysisError(422, "prepared_audio_too_large", "Подготовленная запись слишком велика. Разделите её на части.")
    return duration if duration is not None and abs(duration - prepared_duration) < 1 else prepared_duration


def _value(item, key, default=None):
    return item.get(key, default) if isinstance(item, dict) else getattr(item, key, default)


def format_time(seconds):
    total = int(seconds)
    return f"{total // 3600:02d}:{total // 60 % 60:02d}:{total % 60:02d}" if total >= 3600 else f"{total // 60:02d}:{total % 60:02d}"


def segments_text(segments):
    return "\n\n".join(f'[{format_time(s["start"])}] Участник {s["speaker"]}: {s["text"]}' for s in segments)


async def audio_chunks(source, duration):
    if duration <= MAX_CHUNK_SECONDS:
        return [(source, 0, duration)]
    chunks = []
    for index in range(math.ceil(duration / MAX_CHUNK_SECONDS)):
        offset = index * MAX_CHUNK_SECONDS
        length = min(MAX_CHUNK_SECONDS, duration - offset)
        target = source.with_name(f"part-{index + 1}.mp3")
        await run_media("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", str(offset), "-i", str(source), "-t", str(length), "-vn", "-ac", "1",
            "-ar", "16000", "-codec:a", "libmp3lame", "-b:a", "48k", "-map_metadata", "-1",
            str(target), timeout=30)
        chunks.append((target, offset, length))
    return chunks


def combine_transcriptions(parts, duration, diarize, model):
    if len(parts) == 1:
        return parts[0][1]
    notice = (f"Запись обработана частями: {len(parts)}. Проверьте текст на стыках частей. ")
    if not diarize:
        return {"text": "\n\n".join(result["text"] for _, result in parts), "segments": [],
                "speaker_count": 0, "duration_seconds": duration, "has_speakers": False,
                "model": model, "notice": notice + parts[0][1]["notice"]}
    segments, boundaries, voice_count = [], [], 0
    for index, (offset, result) in enumerate(parts, 1):
        ids = sorted({segment["speaker"] for segment in result["segments"]})
        mapping = {speaker: voice_count + number for number, speaker in enumerate(ids, 1)}
        voice_count += len(ids)
        boundaries.append(f"Часть {index} с {format_time(offset)}: " + ", ".join(str(mapping[s]) for s in ids))
        for segment in result["segments"]:
            segments.append({**segment, "start": segment["start"] + offset,
                             "end": segment["end"] + offset, "speaker": mapping[segment["speaker"]]})
        if "оставшийся участок" in result["notice"]:
            notice += f"Проверьте конец части {index}: возможен нераспознанный участок. "
    notice += ("Номера голосов в каждой части отдельные; один человек может получить несколько номеров. "
               "Прослушайте запись и объедините метки одного человека перед назначением ролей. "
               + "; ".join(boundaries) + ". Можно предложить сопоставление меток и роли по тексту.")
    return {"text": segments_text(segments), "segments": segments, "speaker_count": voice_count,
            "duration_seconds": duration, "has_speakers": True, "model": model, "notice": notice}


def transcription_result(response, duration, diarize, model):
    if not diarize:
        text = _value(response, "text", "").strip()
        if not text:
            raise AnalysisError(422, "empty_transcript", "Речь не обнаружена. Проверьте запись.")
        return {"text": text, "segments": [], "speaker_count": 0, "duration_seconds": duration,
                "has_speakers": False, "model": model,
                "notice": "Текст распознан без меток говорящих. Разделите реплики и подпишите участников перед анализом."}
    voices, segments = {}, []
    for item in _value(response, "segments", []):
        text = str(_value(item, "text", "")).strip()
        if not text:
            continue
        try:
            start, end = float(_value(item, "start")), float(_value(item, "end"))
            if not all(math.isfinite(n) for n in (start, end)) or not 0 <= start <= end <= duration + 5:
                raise ValueError()
        except (TypeError, ValueError):
            raise AnalysisError(502, "invalid_transcript", "Распознавание вернуло некорректные метки времени.") from None
        label = str(_value(item, "speaker", "unknown"))
        if label not in voices:
            voices[label] = len(voices) + 1
        segments.append({"start": start, "end": end, "speaker": voices[label], "text": text})
    if not segments:
        raise AnalysisError(422, "empty_transcript", "Не удалось получить реплики с метками участников. Проверьте запись.")
    segments.sort(key=lambda segment: segment["start"])
    text = segments_text(segments)
    last = max(s["end"] for s in segments)
    notice = "Метки голосов предварительные. Проверьте текст, роли и полноту записи перед оценкой."
    if duration - last > 30:
        notice += f" Последняя распознанная реплика: {format_time(last)} из {format_time(duration)}; проверьте оставшийся участок записи."
    return {"text": text, "segments": segments, "speaker_count": len(voices),
            "duration_seconds": duration, "has_speakers": True, "model": model,
            "notice": notice}


@dataclass
class AudioJob:
    id: str
    status: str = "preparing"
    started: float = field(default_factory=time.monotonic)
    result: dict | None = None
    error: dict | None = None
    task: asyncio.Task | None = field(default=None, repr=False)
    directory: object | None = field(default=None, repr=False)
    current_part: int = 0
    total_parts: int = 0
    completed_parts: int = 0

    def public(self):
        return {"id": self.id, "status": self.status, "elapsed_seconds": int(time.monotonic() - self.started),
                "result": self.result, "error": self.error,
                "current_part": self.current_part, "total_parts": self.total_parts,
                "completed_parts": self.completed_parts}


class TranscriptionService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = AsyncOpenAI(api_key=settings.api_key, base_url="https://api.openai.com/v1",
            max_retries=0, timeout=settings.transcription_timeout - 5) if settings.api_key else None
        self.jobs: dict[str, AudioJob] = {}
        self._active = None

    def _purge(self):
        now = time.monotonic()
        for job_id, job in list(self.jobs.items()):
            if job_id != self._active and now - job.started > 1800:
                del self.jobs[job_id]

    def get(self, job_id):
        self._purge()
        if job_id not in self.jobs:
            raise AnalysisError(404, "audio_job_missing", "Результат распознавания не найден или срок его хранения истёк.")
        return self.jobs[job_id].public()

    async def submit(self, upload, diarize):
        self._purge()
        if self.client is None:
            raise AnalysisError(503, "api_not_configured", "Настройте серверный API-ключ для распознавания.")
        if self._active:
            raise AnalysisError(429, "transcription_busy", "Уже распознаётся другая запись. Дождитесь её завершения.")
        suffix = Path(upload.filename or "").suffix.lower()
        if suffix not in ALLOWED_EXTENSIONS:
            raise AnalysisError(422, "audio_format", "Поддерживаются M4A, MP3, WAV, WebM, OGG, FLAC, AAC и MP4.")
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            raise AnalysisError(503, "audio_tools_missing", "На backend нужны FFmpeg и ffprobe для подготовки аудио.")
        job = AudioJob(uuid.uuid4().hex)
        self._active = job.id
        directory = None
        try:
            directory = tempfile.TemporaryDirectory(prefix="royal-brick-audio-")
            job.directory = directory
            source = Path(directory.name) / ("input" + suffix)
            size = 0
            with source.open("wb") as stream:
                while chunk := await upload.read(1024 * 1024):
                    size += len(chunk)
                    if size > self.settings.max_audio_bytes:
                        raise AnalysisError(413, "audio_too_large", "Максимальный размер аудиофайла — 100 МБ.")
                    stream.write(chunk)
            if not size:
                raise AnalysisError(422, "empty_audio", "Выбран пустой файл.")
            self.jobs[job.id] = job
            job.task = asyncio.create_task(self._run(job, directory, source, diarize))
        except BaseException:
            if directory:
                directory.cleanup()
            self._active = None
            raise
        return job.public()

    async def _run(self, job, directory, source, diarize):
        try:
            destination = Path(directory.name) / "meeting.mp3"
            duration = await prepare_audio(source, destination, self.settings)
            async with asyncio.timeout(120):
                chunks = await audio_chunks(destination, duration)
            job.total_parts = len(chunks)
            job.status = "transcribing"
            model = self.settings.transcription_model if diarize else self.settings.plain_transcription_model
            options = {"model": model, "response_format": "diarized_json" if diarize else "json"}
            if diarize:
                options["chunking_strategy"] = "auto"
            else:
                options["languages"] = ["ru"]
            gate = asyncio.Semaphore(2)
            async def recognize_part(index, path, offset, length):
                async with gate:
                    job.current_part = index
                    with path.open("rb") as audio:
                        response = await self.client.audio.transcriptions.create(file=("meeting.mp3", audio, "audio/mpeg"), **options)
                    result = transcription_result(response, length, diarize, model)
                    job.completed_parts += 1
                    return offset, result
            tasks = []
            async with asyncio.timeout(self.settings.transcription_timeout):
                try:
                    tasks = [asyncio.create_task(recognize_part(index, *chunk))
                             for index, chunk in enumerate(chunks, 1)]
                    parts = await asyncio.gather(*tasks)  # Keeps chronological order, independent of completion order.
                except BaseException:
                    for task in tasks:
                        task.cancel()
                    await asyncio.gather(*tasks, return_exceptions=True)
                    raise
            job.result = combine_transcriptions(parts, duration, diarize, model)
            job.status = "completed"
        except asyncio.CancelledError:
            job.status = "cancelled"
        except (TimeoutError, APITimeoutError):
            job.status, job.error = "failed", {"code": "transcription_timeout", "message": "Время подготовки или распознавания истекло. Попробуйте запись короче."}
        except AnalysisError as error:
            job.status, job.error = "failed", {"code": error.code, "message": error.message}
        except (AuthenticationError, PermissionDeniedError):
            job.status, job.error = "failed", {"code": "api_access", "message": "OpenAI отклонил доступ. Проверьте серверный ключ и доступ проекта."}
        except RateLimitError as error:
            job.status, job.error = "failed", {"code": "quota_exceeded" if error.code == "insufficient_quota" else "rate_limit",
                "message": "Проверьте квоту и лимиты API OpenAI, затем повторите распознавание."}
        except APIError as error:
            diagnostic = str(getattr(error, "message", "Provider error"))
            diagnostic = diagnostic.replace(self.settings.api_key, "[REDACTED]")
            diagnostic = re.sub(r"sk-[^\s\"']+", "[REDACTED]", diagnostic)
            logging.getLogger(__name__).warning("OpenAI audio error: %s status=%s code=%s %s",
                type(error).__name__, getattr(error, "status_code", None), getattr(error, "code", None), diagnostic[:600])
            job.status, job.error = "failed", {"code": "transcription_provider", "message": "Не удалось получить ответ распознавания OpenAI. Проверьте соединение и выбранную модель."}
        except Exception:
            job.status, job.error = "failed", {"code": "audio_processing", "message": "Не удалось обработать аудиофайл. Проверьте запись и настройки backend."}
        finally:
            directory.cleanup()
            job.directory = None
            if self._active == job.id:
                self._active = None

    async def cancel(self, job_id):
        job = self.jobs.get(job_id)
        if not job:
            return self.get(job_id)
        if job.task and not job.task.done():
            job.task.cancel()
            await asyncio.gather(job.task, return_exceptions=True)
            if job.directory:
                job.directory.cleanup()
                job.directory = None
            if job.status in ("preparing", "transcribing"):
                job.status = "cancelled"
            if self._active == job_id:
                self._active = None
        return job.public()

    async def close(self):
        tasks = [job.task for job in self.jobs.values() if job.task and not job.task.done()]
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for job in self.jobs.values():
            if job.directory:
                job.directory.cleanup()
                job.directory = None
        if self.client:
            await self.client.close()
