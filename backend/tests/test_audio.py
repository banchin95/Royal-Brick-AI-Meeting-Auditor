import asyncio
import io
from pathlib import Path
import shutil
from types import SimpleNamespace
from unittest.mock import AsyncMock
import wave

from fastapi import UploadFile
from fastapi.testclient import TestClient
import pytest

from backend.app import audio
from backend.app.audio import TranscriptionService, prepare_audio, transcription_result, combine_transcriptions
from backend.app.config import Settings
from backend.app.main import create_app
from backend.app.service import AnalysisError


RECOGNIZED = {"segments": [
    {"speaker": "B", "start": 0, "end": 1, "text": "Добрый день!"},
    {"speaker": "A", "start": 1.1, "end": 2, "text": "Нужна облицовка."},
    {"speaker": "B", "start": 2.1, "end": 3, "text": "Какой объект?"},
]}


def test_voice_ids_do_not_guess_manager_and_timestamps_survive():
    result = transcription_result(RECOGNIZED, 3, True, "test-model")
    assert [s["speaker"] for s in result["segments"]] == [1, 2, 1]
    assert result["speaker_count"] == 2 and result["has_speakers"]
    assert result["text"].startswith("[00:00] Участник 1: Добрый день!")
    assert "manager" not in str(result) and "client" not in str(result)


def test_plain_transcript_has_no_invented_speakers():
    result = transcription_result({"text": "Только распознанная речь"}, 10, False, "test")
    assert result["text"] == "Только распознанная речь"
    assert result["segments"] == [] and result["speaker_count"] == 0
    assert result["has_speakers"] is False


def test_chunk_results_keep_absolute_times_and_separate_voice_ids():
    first = transcription_result(RECOGNIZED, 1200, True, "test")
    second = transcription_result(RECOGNIZED, 369, True, "test")
    result = combine_transcriptions([(0, first), (1200, second)], 1569, True, "test")
    assert result["speaker_count"] == 4
    assert [segment["speaker"] for segment in result["segments"]] == [1, 2, 1, 3, 4, 3]
    assert result["segments"][3]["start"] == 1200
    assert "[20:00] Участник 3:" in result["text"]
    assert "один человек может получить несколько номеров" in result["notice"]
    assert "Проверьте конец части 1" in result["notice"]


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="FFmpeg is required")
def test_audio_chunks_cover_entire_recording_without_gaps(tmp_path, monkeypatch):
    monkeypatch.setattr(audio, "MAX_CHUNK_SECONDS", 1)
    async def run():
        source = tmp_path / "meeting.mp3"
        await audio.run_media("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=16000:cl=mono", "-t", "2.5",
            "-codec:a", "libmp3lame", str(source), timeout=10)
        chunks = await audio.audio_chunks(source, 2.5)
        assert [(offset, length) for _, offset, length in chunks] == [(0, 1), (1, 1), (2, .5)]
        assert all(path.stat().st_size > 0 for path, _, _ in chunks)
        assert source.exists()
    asyncio.run(run())


@pytest.mark.parametrize("start,end", [(-1, 2), (2, 1), (float("nan"), 2), (0, 100)])
def test_bad_recognition_timestamps_are_rejected(start, end):
    with pytest.raises(AnalysisError):
        transcription_result({"segments": [{"speaker": "A", "start": start, "end": end, "text": "Речь"}]}, 3, True, "test")


def test_empty_recognition_and_uncovered_tail_are_explicit():
    with pytest.raises(AnalysisError):
        transcription_result({"segments": []}, 3, True, "test")
    result = transcription_result(RECOGNIZED, 100, True, "test")
    assert "оставшийся участок" in result["notice"]


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="FFmpeg is required")
def test_real_ffmpeg_preparation_uses_small_synthetic_audio(tmp_path):
    source, target = tmp_path / "sample.wav", tmp_path / "meeting.mp3"
    with wave.open(str(source), "wb") as stream:
        stream.setnchannels(1); stream.setsampwidth(2); stream.setframerate(16000)
        stream.writeframes(b"\x00\x00" * 16000)
    duration = asyncio.run(prepare_audio(source, target, Settings()))
    assert duration == pytest.approx(1)
    assert 0 < target.stat().st_size < 24000
    assert source.exists()


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="FFmpeg is required")
def test_streaming_webm_without_duration_header_is_supported(tmp_path):
    async def run():
        source, target = tmp_path / "browser.webm", tmp_path / "meeting.mp3"
        data = await audio.run_media("ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "1", "-c:a", "libopus",
            "-f", "webm", "pipe:1", timeout=10)
        source.write_bytes(data)
        duration = await prepare_audio(source, target, Settings())
        assert 0.9 < duration < 1.3 and target.stat().st_size > 0
    asyncio.run(run())


async def fake_prepare(source, destination, settings):
    assert source.name.startswith("input")
    destination.write_bytes(b"synthetic-mp3-for-mocked-provider")
    return 3


def test_jobs_clean_up_files_and_use_auto_chunking(monkeypatch):
    monkeypatch.setattr(audio, "prepare_audio", fake_prepare)
    async def run():
        service = TranscriptionService(Settings(api_key="test-only-placeholder"))
        service.client.audio.transcriptions.create = AsyncMock(return_value=RECOGNIZED)
        upload = UploadFile(filename="private-original.m4a", file=io.BytesIO(b"test audio"))
        try:
            job = await service.submit(upload, True)
            directory = service.jobs[job["id"]].directory.name
            await service.jobs[job["id"]].task
            result = service.get(job["id"])
            assert result["status"] == "completed" and result["result"]["speaker_count"] == 2
            options = service.client.audio.transcriptions.create.call_args.kwargs
            assert options["chunking_strategy"] == "auto"
            assert options["response_format"] == "diarized_json"
            assert options["file"][0] == "meeting.mp3"
            assert not Path(directory).exists() and service._active is None
        finally:
            await upload.close(); await service.close()
    asyncio.run(run())


def test_long_job_sends_parts_and_cleans_every_file(monkeypatch):
    async def prepare(source, destination, settings):
        destination.write_bytes(b"synthetic")
        return 1569
    async def chunks(source, duration):
        paths = [source.with_name(f"part-{i}.mp3") for i in (1, 2)]
        for path in paths:
            path.write_bytes(b"synthetic")
        return [(paths[0], 0, 1200), (paths[1], 1200, 369)]
    monkeypatch.setattr(audio, "prepare_audio", prepare)
    monkeypatch.setattr(audio, "audio_chunks", chunks)
    async def run():
        service = TranscriptionService(Settings(api_key="test-only-placeholder"))
        service.client.audio.transcriptions.create = AsyncMock(side_effect=[RECOGNIZED, RECOGNIZED])
        upload = UploadFile(filename="sample.m4a", file=io.BytesIO(b"synthetic"))
        try:
            job = await service.submit(upload, True)
            directory = service.jobs[job["id"]].directory.name
            await service.jobs[job["id"]].task
            result = service.get(job["id"])
            assert result["status"] == "completed" and result["total_parts"] == result["completed_parts"] == 2
            assert result["result"]["duration_seconds"] == 1569
            assert result["result"]["speaker_count"] == 4
            assert service.client.audio.transcriptions.create.await_count == 2
            assert not Path(directory).exists()
        finally:
            await upload.close(); await service.close()
    asyncio.run(run())


def test_parallel_parts_are_bounded_and_keep_chronological_output(monkeypatch):
    async def prepare(source, destination, settings):
        destination.write_bytes(b"synthetic")
        return 601
    async def chunks(source, duration):
        parts = []
        for index in range(3):
            path = source.with_name(f"part-{index}.mp3")
            path.write_bytes(b"synthetic")
            parts.append((path, index * 300, 300 if index < 2 else 1))
        return parts
    monkeypatch.setattr(audio, "prepare_audio", prepare)
    monkeypatch.setattr(audio, "audio_chunks", chunks)
    async def run():
        active, peak = 0, 0
        async def recognize(**options):
            nonlocal active, peak
            index = int(Path(options["file"][1].name).stem.split("-")[-1])
            active += 1; peak = max(peak, active)
            try:
                await asyncio.sleep(.02 if index == 0 else .001)
                return {"segments": [{"speaker": "A", "start": 0, "end": 1, "text": f"Часть {index}"}]}
            finally:
                active -= 1
        service = TranscriptionService(Settings(api_key="test-only-placeholder"))
        service.client.audio.transcriptions.create = AsyncMock(side_effect=recognize)
        upload = UploadFile(filename="sample.m4a", file=io.BytesIO(b"synthetic"))
        try:
            job = await service.submit(upload, True)
            await service.jobs[job["id"]].task
            result = service.get(job["id"])
            assert result["status"] == "completed" and result["completed_parts"] == 3
            assert peak == 2 and active == 0
            segments = result["result"]["segments"]
            assert [s["start"] for s in segments] == [0, 300, 600]
            assert [s["text"] for s in segments] == ["Часть 0", "Часть 1", "Часть 2"]
        finally:
            await upload.close(); await service.close()
    asyncio.run(run())


def test_cancelling_active_requests_waits_for_cleanup(monkeypatch):
    monkeypatch.setattr(audio, "prepare_audio", fake_prepare)
    async def run():
        started, cancelled = asyncio.Event(), asyncio.Event()
        async def recognize(**options):
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()
        service = TranscriptionService(Settings(api_key="test-only-placeholder"))
        service.client.audio.transcriptions.create = AsyncMock(side_effect=recognize)
        upload = UploadFile(filename="sample.wav", file=io.BytesIO(b"synthetic"))
        try:
            job = await service.submit(upload, True)
            directory = service.jobs[job["id"]].directory.name
            await asyncio.wait_for(started.wait(), 1)
            result = await service.cancel(job["id"])
            assert result["status"] == "cancelled" and cancelled.is_set()
            assert not Path(directory).exists() and service._active is None
        finally:
            await upload.close(); await service.close()
    asyncio.run(run())


def test_cancelling_job_before_it_starts_removes_private_file():
    async def run():
        service = TranscriptionService(Settings(api_key="test-only-placeholder"))
        upload = UploadFile(filename="sample.wav", file=io.BytesIO(b"test"))
        try:
            job = await service.submit(upload, True)
            directory = service.jobs[job["id"]].directory.name
            result = await service.cancel(job["id"])
            assert result["status"] == "cancelled"
            assert not Path(directory).exists() and service._active is None
        finally:
            await upload.close(); await service.close()
    asyncio.run(run())


def test_upload_limits_and_single_active_job(monkeypatch):
    async def run():
        service = TranscriptionService(Settings(api_key="test-only-placeholder", max_audio_bytes=2))
        try:
            with pytest.raises(AnalysisError) as error:
                await service.submit(UploadFile(filename="sample.wav", file=io.BytesIO(b"large")), True)
            assert error.value.code == "audio_too_large" and service._active is None
            with pytest.raises(AnalysisError):
                await service.submit(UploadFile(filename="sample.txt", file=io.BytesIO(b"a")), True)
            service._active = "existing-job"
            with pytest.raises(AnalysisError) as busy:
                await service.submit(UploadFile(filename="sample.wav", file=io.BytesIO(b"a")), True)
            assert busy.value.code == "transcription_busy"
        finally:
            await service.close()
    asyncio.run(run())


def test_upload_job_api_contract_without_external_requests():
    class FakeAudio:
        async def submit(self, upload, diarize):
            assert upload.filename == "sample.wav" and diarize is True
            assert await upload.read() == b"test"
            return {"id": "job", "status": "preparing"}
        def get(self, job_id): return {"id": job_id, "status": "completed", "result": {"text": "Учебный текст"}}
        async def cancel(self, job_id): return {"id": job_id, "status": "cancelled"}
    with TestClient(create_app(Settings(), transcription_service=FakeAudio())) as client:
        response = client.post("/api/transcriptions", files={"file": ("sample.wav", b"test", "audio/wav")}, data={"diarize": "true"})
        assert response.status_code == 202 and response.json()["id"] == "job"
        assert response.headers["Cache-Control"] == "no-store"
        assert client.get("/api/transcriptions/job").json()["status"] == "completed"
        assert client.delete("/api/transcriptions/job").json()["status"] == "cancelled"
