import re

from .schemas import (
    AssessmentStatus as Status, GeneratedAudit, PRICE_MAXIMA,
    STAGE_MAXIMA, SequenceStatus, Turn,
)


class InvalidAudit(ValueError):
    """The generated answer failed business or evidence validation."""


def _ordered(items, attribute: str, count: int):
    if {getattr(item, attribute) for item in items} != set(range(1, count + 1)):
        raise InvalidAudit("Missing or duplicate report item")
    return sorted(items, key=lambda item: getattr(item, attribute))


def _valid_points(status, points, maximum):
    if status == Status.SCORED:
        if points is None or not 0 <= points <= maximum:
            raise InvalidAudit("Invalid score")
    elif points is not None:
        raise InvalidAudit("Unassessed items must not have a score")


def price_score(rules):
    rules = _ordered(rules, "rule", 8)
    for rule, maximum in zip(rules, PRICE_MAXIMA):
        _valid_points(rule.status, rule.points, maximum)
    # An unknown required subcriterion is not silently treated as a missed action.
    if any(rule.status == Status.NO_DATA for rule in rules):
        return Status.NO_DATA, None
    available = sum(maximum for rule, maximum in zip(rules, PRICE_MAXIMA)
                    if rule.status == Status.SCORED)
    if not available:
        return Status.NOT_APPLICABLE, None
    return Status.SCORED, sum(rule.points or 0 for rule in rules) / available * 10


def _check_label(rules, indexes):
    applicable = [rules[i] for i in indexes if rules[i].status != Status.NOT_APPLICABLE]
    if not applicable:
        return "not_applicable"
    if any(rule.status == Status.NO_DATA for rule in applicable):
        return "no_data"
    if any(rule.points < PRICE_MAXIMA[rule.rule - 1] for rule in applicable):
        return "not_done"
    return "done"


def build_report(audit: GeneratedAudit, turns: list[Turn], model: str, is_partial: bool = False):
    stages = _ordered(audit.stages, "stage", 9)
    sections = _ordered(audit.sections, "section", 13)
    rules = _ordered(audit.price_rules, "rule", 8)
    computed_status, computed_points = price_score(rules)
    stages[5] = stages[5].model_copy(update={"status": computed_status, "points": computed_points})
    if is_partial:
        stages = [stage.model_copy(update={
            "status": Status.NO_DATA, "points": None,
            "comment": "Неполная запись: объективная неприменимость этого этапа не подтверждена репликой. Нет данных для оценки."
        }) if stage.status == Status.NOT_APPLICABLE and not stage.evidence else stage
            for stage in stages]

    def normalize(text):
        return re.sub(r"\s+", " ", text).strip()

    def evidence(ref):
        if ref.utterance_id >= len(turns):
            raise InvalidAudit("Unknown evidence reference")
        turn = turns[ref.utterance_id]
        if normalize(ref.quote) not in normalize(turn.text):
            raise InvalidAudit("Quote not present in the referenced utterance")
        return {"at": turn.timestamp, "speaker": turn.speaker, "text": ref.quote}

    earned = available = 0.0
    for index, stage in enumerate(stages):
        _valid_points(stage.status, stage.points, STAGE_MAXIMA[index])
        if stage.status == Status.SCORED:
            if not stage.evidence:
                raise InvalidAudit("A scored stage requires transcript evidence")
            earned += stage.points
            available += STAGE_MAXIMA[index]
        for ref in stage.evidence:
            evidence(ref)

    if len(sections[11].body) > 1000 or len(sections[9].body) > 600:
        raise InvalidAudit("CRM summary or client message is too long")

    sequence = audit.price_sequence
    if rules[7].status == Status.NO_DATA:
        sequence = SequenceStatus.NO_DATA
    elif rules[7].status == Status.SCORED:
        if (rules[7].points == 1) != (sequence == SequenceStatus.FOLLOWED):
            raise InvalidAudit("Sequence conclusion contradicts its score")

    return {
        "source": "openai",
        "model": model,
        "score": {"earned": earned, "available": available,
                  "normalized": earned / available * 100 if available else None,
                  "coverage": available},
        "stages": [{"status": stage.status.value, "points": stage.points,
                    "comment": stage.comment} for stage in stages],
        "price": {
            "checks": [_check_label(rules, indexes) for indexes in
                       [(0,), (1,), (2, 3), (4, 5), (6,)]],
            "sequence": sequence.value,
            "comment": audit.price_comment,
        },
        "sections": [{"body": section.body,
                      "evidence": [evidence(ref) for ref in section.evidence]}
                     for section in sections],
    }
