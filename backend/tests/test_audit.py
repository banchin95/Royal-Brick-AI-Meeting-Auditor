from copy import deepcopy

import pytest
from pydantic import ValidationError

from backend.app.schemas import AnalyzeRequest, GeneratedAudit, parse_transcript
from backend.app.scoring import InvalidAudit, build_report


TRANSCRIPT = "[00:00] Участник 1: Добрый день! Чем могу помочь?\n\nУчастник 2: Хочу облицевать цоколь."
INPUT = {"transcript": TRANSCRIPT, "participants": [
    {"speaker": 1, "role": "manager"}, {"speaker": 2, "role": "client"}], "is_partial": True}


@pytest.fixture
def raw_audit():
    return {
        "stages": [{"stage": i, "status": "no_data", "points": None,
                    "comment": "Нет данных", "evidence": []} for i in range(1, 10)],
        "price_rules": [{"rule": i, "status": "no_data", "points": None} for i in range(1, 9)],
        "price_sequence": "недостаточно данных", "price_comment": "В фрагменте цена не обсуждается.",
        "sections": [{"section": i, "body": "Недостаточно данных", "evidence": []} for i in range(1, 14)],
    }


def finish(raw):
    return build_report(GeneratedAudit.model_validate(raw), parse_transcript(TRANSCRIPT), "test-model")


def test_parser_derives_speakers_times_and_keeps_multiline_text():
    turns = parse_transcript(TRANSCRIPT)
    assert turns[0].speaker == 1 and turns[0].timestamp == "00:00"
    assert turns[1].speaker == 2 and turns[1].timestamp is None
    assert turns[1].text == "Хочу облицевать цоколь."
    assert len(parse_transcript(TRANSCRIPT.replace("Хочу", "Хочу\nтеперь"))) == 2


@pytest.mark.parametrize("change", [
    {"transcript": "Неподписанный текст разговора длиной больше тридцати символов"},
    {"transcript": TRANSCRIPT.replace("Участник 2", "Участник 3")},
    {"participants": [{"speaker": 1, "role": "manager"}, {"speaker": 2, "role": "manager"}]},
    {"participants": [{"speaker": 1, "role": "unknown"}, {"speaker": 2, "role": "client"}]},
    {"participants": [{"speaker": 1, "role": "manager"}, {"speaker": 1, "role": "client"}]},
])
def test_invalid_input_is_rejected(change):
    with pytest.raises(ValidationError):
        AnalyzeRequest.model_validate({**INPUT, **change})


def test_no_data_never_becomes_zero(raw_audit):
    score = finish(raw_audit)["score"]
    assert score == {"earned": 0, "available": 0, "normalized": None, "coverage": 0}


def test_zero_stays_in_denominator_and_quotes_are_bound_to_turns(raw_audit):
    raw_audit["stages"][0].update(status="scored", points=0,
        evidence=[{"utterance_id": 0, "quote": "Добрый день!"}])
    raw_audit["sections"][0]["evidence"] = [{"utterance_id": 1, "quote": "Хочу облицевать цоколь."}]
    result = finish(raw_audit)
    assert result["score"]["normalized"] == 0 and result["score"]["coverage"] == 8
    assert result["sections"][0]["evidence"][0] == {
        "at": None, "speaker": 2, "text": "Хочу облицевать цоколь."}


def test_partial_and_not_applicable_are_excluded(raw_audit):
    raw_audit["stages"][0].update(status="scored", points=4,
        evidence=[{"utterance_id": 0, "quote": "Добрый день!"}])
    raw_audit["stages"][7]["status"] = "not_applicable"
    result = finish(raw_audit)
    assert result["score"]["normalized"] == 50 and result["score"]["coverage"] == 8


def test_partial_record_does_not_prove_non_applicability(raw_audit):
    raw_audit["stages"][2]["status"] = "not_applicable"
    result = build_report(GeneratedAudit.model_validate(raw_audit),
                          parse_transcript(TRANSCRIPT), "test-model", is_partial=True)
    assert result["stages"][2]["status"] == "no_data"
    assert result["stages"][2]["points"] is None


def test_price_is_recomputed_from_applicable_rules(raw_audit):
    maxima = [1, 1, 2, 2, 1, 1, 1, 1]
    for rule, maximum in zip(raw_audit["price_rules"], maxima):
        rule.update(status="scored", points=maximum)
    # Подтверждённо недоступные рассрочка и распродажа исключаются.
    for index in (2, 3, 4, 5):
        raw_audit["price_rules"][index].update(status="not_applicable", points=None)
    raw_audit["price_sequence"] = "соблюдена"
    raw_audit["stages"][5].update(status="scored", points=1,
        evidence=[{"utterance_id": 0, "quote": "Чем могу помочь?"}])
    result = finish(raw_audit)
    assert result["stages"][5]["points"] == 10  # Оценка модели 1 не используется.
    assert result["score"]["normalized"] == 100 and result["score"]["coverage"] == 10
    assert result["price"]["checks"] == ["done", "done", "not_applicable", "not_applicable", "done"]


@pytest.mark.parametrize("kind", ["quote", "reference", "duplicate", "score", "nonfinite", "crm", "message"])
def test_invalid_generated_reports_are_not_shown(raw_audit, kind):
    raw = deepcopy(raw_audit)
    if kind == "quote":
        raw["sections"][0]["evidence"] = [{"utterance_id": 0, "quote": "Я уже оплатил заказ"}]
    elif kind == "reference":
        raw["sections"][0]["evidence"] = [{"utterance_id": 900, "quote": "Добрый день!"}]
    elif kind == "duplicate":
        raw["stages"][0]["stage"] = 2
    elif kind in ("score", "nonfinite"):
        raw["stages"][0].update(status="scored", points=9 if kind == "score" else float("nan"))
    elif kind == "crm":
        raw["sections"][11]["body"] = "А" * 1001
    else:
        raw["sections"][9]["body"] = "А" * 601
    with pytest.raises((InvalidAudit, ValidationError)):
        finish(raw)
