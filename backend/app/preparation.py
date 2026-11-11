"""Provisional speaker/role inference, with source text reconstructed by the server."""

from dataclasses import dataclass
from enum import StrEnum
import re

from pydantic import Field

from .schemas import StrictModel, TURN_LABEL, parse_transcript


class PrepareRequest(StrictModel):
    transcript: str = Field(min_length=30, max_length=60_000)
    reconcile_speakers: bool = False


class Confidence(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class SuggestedRole(StrEnum):
    MANAGER = "manager"
    CLIENT = "client"
    OTHER = "other"
    UNKNOWN = "unknown"


class SpeakerRun(StrictModel):
    first_unit: int = Field(ge=0)
    last_unit: int = Field(ge=0)
    speaker: int = Field(ge=1, le=240)


class SpeakerGuess(StrictModel):
    speaker: int = Field(ge=1, le=240)
    role: SuggestedRole
    confidence: Confidence
    reason: str = Field(min_length=1, max_length=600)
    evidence_unit: int = Field(ge=0)


class GeneratedPreparation(StrictModel):
    runs: list[SpeakerRun] = Field(min_length=1, max_length=1200)
    participants: list[SpeakerGuess] = Field(min_length=1, max_length=240)


class InvalidPreparation(ValueError):
    pass


@dataclass(frozen=True)
class PreparationSource:
    original: str
    units: list[dict]
    labelled: bool
    reconcile: bool = False


def preparation_source(text: str, reconcile_speakers: bool = False) -> PreparationSource:
    if not text.strip():
        raise ValueError("Добавьте текст разговора.")
    if TURN_LABEL.search(text):
        turns = parse_transcript(text, max_speaker=240 if reconcile_speakers else 12)
        units = [{"id": t.id, "text": t.text, "speaker": t.speaker, "timestamp": t.timestamp} for t in turns]
        labelled = True
    else:
        pieces, cursor = [], 0
        # Stable units: sentences/paragraphs. Decimal points are not boundaries.
        for match in re.finditer(r'[.!?…]+[»"”\)\]]*(?:[ \t]+|\r?\n+)|\r?\n+', text):
            piece = text[cursor:match.end()]
            if piece.strip():
                pieces.append(piece)
                cursor = match.end()
        tail = text[cursor:]
        if tail.strip():
            pieces.append(tail)
        elif pieces:
            pieces[-1] += tail
        if len(pieces) < 2:
            raise ValueError("Для определения реплик нужны границы предложений или переносы строк. Разделите текст вручную.")
        assert "".join(pieces) == text
        units = [{"id": i, "text": piece, "speaker": None} for i, piece in enumerate(pieces)]
        labelled = False
    if len(units) > 1200:
        raise ValueError("Слишком много фрагментов текста. Разделите разговор на части для определения ролей.")
    return PreparationSource(text, units, labelled, reconcile_speakers)


def build_preparation(generated: GeneratedPreparation, source: PreparationSource, model: str):
    if source.reconcile or not source.labelled:
        # Compact final IDs, even when the model uses sparse or large source numbers.
        generated = generated.model_copy(deep=True)
        remap = {speaker: i + 1 for i, speaker in enumerate(dict.fromkeys(run.speaker for run in generated.runs))}
        for run in generated.runs:
            run.speaker = remap[run.speaker]
        for person in generated.participants:
            if person.speaker not in remap:
                raise InvalidPreparation("Participant without assigned source units")
            person.speaker = remap[person.speaker]
    assignments, rendered, cursor, speaker_mapping = {}, [], 0, {}
    for run in generated.runs:
        if run.first_unit != cursor or not run.first_unit <= run.last_unit < len(source.units):
            raise InvalidPreparation("Runs must cover every source unit exactly once, in order")
        selected = source.units[run.first_unit:run.last_unit + 1]
        if source.labelled and not source.reconcile and any(unit["speaker"] != run.speaker for unit in selected):
            raise InvalidPreparation("Existing speaker IDs cannot change")
        for unit in selected:
            assignments[unit["id"]] = run.speaker
            if source.labelled:
                original = unit["speaker"]
                if original in speaker_mapping and speaker_mapping[original] != run.speaker:
                    raise InvalidPreparation("One source speaker cannot split into multiple people")
                speaker_mapping[original] = run.speaker
        if not source.labelled:
            body = "".join(unit["text"] for unit in selected).strip()
            rendered.append(f"Участник {run.speaker}: {body}")
        cursor = run.last_unit + 1
    if cursor != len(source.units):
        raise InvalidPreparation("Missing source units")
    ids = {p.speaker for p in generated.participants}
    if len(ids) != len(generated.participants) or ids != set(assignments.values()):
        raise InvalidPreparation("Participants must match all source assignments")
    participants = []
    for guess in generated.participants:
        if assignments.get(guess.evidence_unit) != guess.speaker:
            raise InvalidPreparation("Evidence must belong to the suggested speaker")
        participants.append({
            "speaker": guess.speaker,
            "role": "unknown" if guess.confidence == Confidence.LOW else guess.role.value,
            "confidence": guess.confidence.value,
            "reason": guess.reason,
            "evidence": source.units[guess.evidence_unit]["text"].strip()[:400],
            "source_speakers": sorted(old for old, new in speaker_mapping.items() if new == guess.speaker),
        })
    transcript = source.original if source.labelled else "\n\n".join(rendered)
    if source.labelled and source.reconcile:
        # Only replace the speaker number. Keep every timestamp, word and whitespace byte.
        transcript = TURN_LABEL.sub(lambda match: re.sub(
            r"(Участник[ \t]+)\d+", lambda label: label[1] + str(speaker_mapping[int(match[2])]),
            match[0], count=1, flags=re.IGNORECASE), source.original)
    if len(transcript) > 60_000:
        raise InvalidPreparation("Prepared transcript exceeds analysis limit")
    notice = (
        "Роли предложены по смыслу текста и могут быть ошибочными. "
        "Проверьте реплики по записи перед применением. "
        "Уверенность — оценка модели, а не подтверждённая вероятность."
    )
    if not source.labelled:
        notice += (" Номера участников и границы реплик предположительные: "
                   "по одному тексту нельзя подтвердить личности говорящих. "
                   "Исходные слова сохранены; метки времени не добавлялись.")
    elif source.reconcile:
        notice += (" Предложено сопоставление исходных меток одному человеку по смыслу текста. "
                   "Одинаковая роль сама по себе не означает одного человека. "
                   "Слова, порядок и время реплик сохранены. Проверьте объединения по записи.")
    else:
        notice += " Исходные подписи участников и метки времени сохранены."
    if any(p["role"] == "unknown" for p in participants):
        notice += " Неуверенные роли оставлены неопределёнными — назначьте их вручную."
    return {"source": "ai", "model": model, "transcript": transcript,
            "participants": sorted(participants, key=lambda p: p["speaker"]),
            "notice": notice, "inferred_turns": not source.labelled,
            "source_speaker_count": len(speaker_mapping),
            "merged_speakers": len(speaker_mapping) > len(ids)}
