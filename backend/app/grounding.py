"""Model-selected source IDs; quotation text and metadata always come from input."""

from dataclasses import dataclass
import re

from pydantic import Field

from .schemas import GeneratedAudit, ReportSection, StageAssessment, StrictModel, Turn
from .scoring import InvalidAudit


class SourceRef(StrictModel):
    quote_id: int = Field(ge=0)


class GroundedStage(StageAssessment):
    evidence: list[SourceRef] = Field(max_length=5)


class GroundedSection(ReportSection):
    evidence: list[SourceRef] = Field(max_length=5)


class GroundedAudit(GeneratedAudit):
    stages: list[GroundedStage] = Field(min_length=9, max_length=9)
    sections: list[GroundedSection] = Field(min_length=13, max_length=13)


@dataclass(frozen=True)
class SourceQuote:
    utterance_id: int
    text: str


def source_fragments(text: str, maximum: int = 400):
    """Split only at source boundaries; never paraphrase or omit words."""
    cursor = 0
    while cursor < len(text):
        end = min(cursor + maximum, len(text))
        if end < len(text):
            window = text[cursor:end]
            sentences = list(re.finditer(r'[.!?…][»"”\)\]]*\s+', window))
            if sentences and sentences[-1].end() >= maximum // 2:
                end = cursor + sentences[-1].end()
            else:
                spaces = list(re.finditer(r'\s+', window))
                if spaces:
                    end = cursor + spaces[-1].end()
        fragment = text[cursor:end].strip()
        if fragment:
            yield fragment
        cursor = end


def grounded_utterances(turns: list[Turn]):
    catalog, utterances = [], []
    for turn in turns:
        fragments = []
        for text in source_fragments(turn.text):
            quote_id = len(catalog)
            catalog.append(SourceQuote(turn.id, text))
            fragments.append({"quote_id": quote_id, "text": text})
        utterances.append({"id": turn.id, "speaker": turn.speaker,
                           "timestamp": turn.timestamp, "fragments": fragments})
    return utterances, catalog


def resolve_audit(audit: GroundedAudit, catalog: list[SourceQuote]) -> GeneratedAudit:
    payload = audit.model_dump(mode="json")
    for item in [*payload["stages"], *payload["sections"]]:
        evidence, seen = [], set()
        for ref in item["evidence"]:
            quote_id = ref["quote_id"]
            if quote_id >= len(catalog):
                raise InvalidAudit("Unknown source quote ID")
            if quote_id in seen:
                continue
            seen.add(quote_id)
            original = catalog[quote_id]
            evidence.append({"utterance_id": original.utterance_id, "quote": original.text})
        item["evidence"] = evidence
    # Retain all existing score, section, quote and sequence checks downstream.
    return GeneratedAudit.model_validate(payload)
