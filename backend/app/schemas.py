from enum import StrEnum
import re

from pydantic import BaseModel, ConfigDict, Field, model_validator


STAGE_MAXIMA = (8, 20, 5, 15, 10, 10, 15, 10, 7)
PRICE_MAXIMA = (1, 1, 2, 2, 1, 1, 1, 1)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Participant(StrictModel):
    speaker: int = Field(ge=1, le=2)
    role: str = Field(pattern="^(manager|client)$")


class Turn(StrictModel):
    id: int
    speaker: int
    timestamp: str | None
    text: str


TURN_LABEL = re.compile(
    r"(?:\[(\d{1,2}:\d{2}(?::\d{2})?)\][ \t]*)?"
    r"Участник[ \t]+(\d+)[ \t]*:[ \t]*",
    re.IGNORECASE,
)


def parse_transcript(text: str) -> list[Turn]:
    matches = list(TURN_LABEL.finditer(text))
    if not matches or text[:matches[0].start()].strip():
        raise ValueError("Подпишите реплики: «Участник 1: ...» и «Участник 2: ...».")
    turns = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.end():end].strip()
        speaker = int(match[2])
        if speaker not in (1, 2) or not body:
            raise ValueError("Поддерживаются непустые реплики участников 1 и 2.")
        turns.append(Turn(id=index, speaker=speaker, timestamp=match[1], text=body))
    if {turn.speaker for turn in turns} != {1, 2}:
        raise ValueError("Нужны реплики обоих участников; их роли должны быть установлены.")
    return turns


class AnalyzeRequest(StrictModel):
    transcript: str = Field(min_length=30, max_length=60_000)
    participants: list[Participant] = Field(min_length=2, max_length=2)
    context: str = Field(default="", max_length=16_000)
    is_partial: bool = False

    @model_validator(mode="after")
    def validate_input(self):
        if {p.speaker for p in self.participants} != {1, 2}:
            raise ValueError("Укажите разных участников 1 и 2.")
        if {p.role for p in self.participants} != {"manager", "client"}:
            raise ValueError("Назначьте одного менеджера и одного клиента.")
        parse_transcript(self.transcript)
        return self


class AssessmentStatus(StrEnum):
    SCORED = "scored"
    NOT_APPLICABLE = "not_applicable"
    NO_DATA = "no_data"


class EvidenceRef(StrictModel):
    utterance_id: int = Field(ge=0)
    quote: str = Field(min_length=1, max_length=2000)


class StageAssessment(StrictModel):
    stage: int = Field(ge=1, le=9)
    status: AssessmentStatus
    points: float | None
    comment: str = Field(min_length=1, max_length=1600)
    evidence: list[EvidenceRef] = Field(max_length=5)


class PriceRule(StrictModel):
    rule: int = Field(ge=1, le=8)
    status: AssessmentStatus
    points: float | None


class ReportSection(StrictModel):
    section: int = Field(ge=1, le=13)
    body: str = Field(min_length=1, max_length=5000)
    evidence: list[EvidenceRef] = Field(max_length=5)


class SequenceStatus(StrEnum):
    FOLLOWED = "соблюдена"
    PARTLY = "частично соблюдена"
    VIOLATED = "нарушена"
    NO_DATA = "недостаточно данных"


class GeneratedAudit(StrictModel):
    """Only model judgements; totals and citation metadata are built by the server."""

    stages: list[StageAssessment] = Field(min_length=9, max_length=9)
    price_rules: list[PriceRule] = Field(min_length=8, max_length=8)
    price_sequence: SequenceStatus
    price_comment: str = Field(min_length=1, max_length=1800)
    sections: list[ReportSection] = Field(min_length=13, max_length=13)
