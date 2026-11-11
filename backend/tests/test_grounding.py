from copy import deepcopy
import re

from pydantic import ValidationError
import pytest

from backend.app.grounding import GroundedAudit, SourceRef, grounded_utterances, resolve_audit, source_fragments
from backend.app.schemas import parse_transcript
from backend.app.scoring import InvalidAudit, build_report
from test_audit import raw_audit, TRANSCRIPT


def test_catalog_keeps_exact_source_text_and_original_speaker_time():
    turns = parse_transcript(TRANSCRIPT)
    utterances, catalog = grounded_utterances(turns)
    assert utterances[0]['speaker'] == 1 and utterances[0]['timestamp'] == '00:00'
    assert utterances[1]['fragments'] == [{'quote_id': 1, 'text': 'Хочу облицевать цоколь.'}]
    assert catalog[1].utterance_id == 1
    assert all(entry.text in turns[entry.utterance_id].text for entry in catalog)


def test_long_turn_fragments_do_not_omit_or_reorder_source_words():
    text = ('  Описание фактуры, её цвета и монтажа.\n\t«Нужен серый кирпич!»  ' * 40).strip()
    pieces = list(source_fragments(text))
    normalize = lambda value: re.sub(r'\s+', ' ', value).strip()
    assert len(pieces) > 1 and all(0 < len(piece) <= 400 and piece in text for piece in pieces)
    assert normalize(' '.join(pieces)) == normalize(text)


def test_model_cannot_return_invented_quotation_text():
    with pytest.raises(ValidationError):
        SourceRef.model_validate({'quote_id': 0, 'quote': 'Я оплатил заказ, которого в разговоре нет.'})


def test_selected_ids_resolve_to_verbatim_quotes_and_unchanged_score(raw_audit):
    turns = parse_transcript(TRANSCRIPT)
    _, catalog = grounded_utterances(turns)
    raw_audit['stages'][0].update(status='scored', points=4, evidence=[{'quote_id': 0}])
    raw_audit['sections'][0]['evidence'] = [{'quote_id': 1}]
    generated = GroundedAudit.model_validate(raw_audit)
    resolved = resolve_audit(generated, catalog)
    report = build_report(resolved, turns, 'test')
    assert report['score']['normalized'] == 50 and report['score']['coverage'] == 8
    assert report['sections'][0]['evidence'] == [{'at': None, 'speaker': 2, 'text': turns[1].text}]
    assert resolved.stages[0].evidence[0].quote == turns[0].text
    assert generated.stages[0].evidence[0].quote_id == 0  # Conversion does not mutate the response.


def test_unknown_quote_ids_still_reject_the_report(raw_audit):
    _, catalog = grounded_utterances(parse_transcript(TRANSCRIPT))
    raw_audit['sections'][0]['evidence'] = [{'quote_id': 999}]
    with pytest.raises(InvalidAudit, match='Unknown source quote ID'):
        resolve_audit(GroundedAudit.model_validate(raw_audit), catalog)


def test_repeated_quote_ids_are_displayed_once(raw_audit):
    _, catalog = grounded_utterances(parse_transcript(TRANSCRIPT))
    raw_audit['sections'][0]['evidence'] = [{'quote_id': 1}, {'quote_id': 1}]
    resolved = resolve_audit(GroundedAudit.model_validate(raw_audit), catalog)
    assert len(resolved.sections[0].evidence) == 1


def test_bad_scores_and_unsubstantiated_stages_are_still_rejected(raw_audit):
    turns = parse_transcript(TRANSCRIPT)
    _, catalog = grounded_utterances(turns)
    for points, evidence in [(9, [{'quote_id': 0}]), (4, [])]:
        raw = deepcopy(raw_audit)
        raw['stages'][0].update(status='scored', points=points, evidence=evidence)
        with pytest.raises(InvalidAudit):
            build_report(resolve_audit(GroundedAudit.model_validate(raw), catalog), turns, 'test')
