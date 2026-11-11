import asyncio
import json
import re
from types import SimpleNamespace
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient
import pytest

from backend.app.config import Settings
from backend.app.main import create_app
from backend.app.preparation import (
    GeneratedPreparation, InvalidPreparation, PrepareRequest, build_preparation, preparation_source,
)
from backend.app.schemas import TURN_LABEL
from backend.app.service import AuditService, AnalysisError


RAW = 'Мне нужны панели для дома.\n\nКакая площадь? Примерно 40 квадратных метров. '
PLAN = {
    "runs": [
        {"first_unit": 0, "last_unit": 0, "speaker": 1},
        {"first_unit": 1, "last_unit": 1, "speaker": 2},
        {"first_unit": 2, "last_unit": 2, "speaker": 1},
    ],
    "participants": [
        {"speaker": 1, "role": "client", "confidence": "high", "reason": "Описывает свой объект.", "evidence_unit": 0},
        {"speaker": 2, "role": "manager", "confidence": "medium", "reason": "Выясняет объём работ.", "evidence_unit": 1},
    ],
}


def test_inferred_runs_keep_all_original_words_and_order():
    source = preparation_source(RAW)
    assert ''.join(unit['text'] for unit in source.units) == RAW
    result = build_preparation(GeneratedPreparation.model_validate(PLAN), source, "test-model")
    text = TURN_LABEL.sub('', result['transcript'])
    assert re.sub(r'\s+', ' ', text).strip() == re.sub(r'\s+', ' ', RAW).strip()
    assert result['participants'][0]['role'] == 'client'  # Participant 1 need not be the manager.
    assert result['participants'][0]['evidence'] == 'Мне нужны панели для дома.'
    assert result['inferred_turns'] is True and '[00:' not in result['transcript']


def test_labelled_source_is_unchanged_and_low_confidence_is_unknown():
    text = '[00:04] Участник 1: Мне нужны панели.\n\n[00:08] Участник 2: Какой у вас объект?'
    plan = {**PLAN, 'runs': PLAN['runs'][:2], 'participants': [
        PLAN['participants'][0], {**PLAN['participants'][1], 'confidence': 'low'}]}
    result = build_preparation(GeneratedPreparation.model_validate(plan), preparation_source(text), 'test')
    assert result['transcript'] == text and result['inferred_turns'] is False
    assert result['participants'][1]['role'] == 'unknown'


@pytest.mark.parametrize('runs', [
    [{"first_unit": 1, "last_unit": 2, "speaker": 1}],
    [{"first_unit": 0, "last_unit": 0, "speaker": 1}],
    [{"first_unit": 0, "last_unit": 4, "speaker": 1}],
    [{"first_unit": 0, "last_unit": 1, "speaker": 1}, {"first_unit": 1, "last_unit": 2, "speaker": 2}],
])
def test_missing_repeated_reordered_or_nonexistent_units_are_rejected(runs):
    with pytest.raises(InvalidPreparation):
        build_preparation(GeneratedPreparation.model_validate({**PLAN, 'runs': runs}), preparation_source(RAW), 'test')


def test_existing_speaker_identity_and_evidence_ownership_cannot_change():
    labelled = 'Участник 2: Мне нужны панели. Участник 1: Какой у вас объект?'
    with pytest.raises(InvalidPreparation):
        build_preparation(GeneratedPreparation.model_validate({**PLAN, 'runs': PLAN['runs'][:2]}),
                          preparation_source(labelled), 'test')
    changed = {**PLAN, 'participants': [{**PLAN['participants'][0], 'evidence_unit': 1}, PLAN['participants'][1]]}
    with pytest.raises(InvalidPreparation):
        build_preparation(GeneratedPreparation.model_validate(changed), preparation_source(RAW), 'test')


def test_ambiguous_monologue_does_not_invent_a_second_speaker():
    plan = {"runs": [{"first_unit": 0, "last_unit": 2, "speaker": 1}], "participants": [
        {"speaker": 1, "role": "unknown", "confidence": "low", "reason": "Недостаточно данных.", "evidence_unit": 0}]}
    result = build_preparation(GeneratedPreparation.model_validate(plan), preparation_source(RAW), 'test')
    assert len(result['participants']) == 1 and result['participants'][0]['role'] == 'unknown'


def test_preparation_uses_structured_output_and_separates_input_from_instructions():
    async def run():
        service = AuditService(Settings(api_key='test-only-placeholder'))
        service.client.responses.parse = AsyncMock(return_value=SimpleNamespace(
            status='completed', output_parsed=GeneratedPreparation.model_validate(PLAN)))
        try:
            result = await service.prepare_transcript(PrepareRequest(transcript=RAW))
            options = service.client.responses.parse.call_args.kwargs
            assert options['store'] is False and options['text_format'] is GeneratedPreparation
            assert RAW not in options['instructions']
            assert json.loads(options['input'][0]['content'])['source_has_speakers'] is False
            assert result['source'] == 'ai' and not service._gate.locked()
        finally:
            await service.close()
    asyncio.run(run())


def test_unsafe_model_preparation_is_sanitized_and_gate_is_released():
    async def run():
        service = AuditService(Settings(api_key='test-only-placeholder'))
        invalid = {**PLAN, 'runs': PLAN['runs'][:1]}
        service.client.responses.parse = AsyncMock(return_value=SimpleNamespace(
            status='completed', output_parsed=GeneratedPreparation.model_validate(invalid)))
        try:
            with pytest.raises(AnalysisError) as error:
                await service.prepare_transcript(PrepareRequest(transcript=RAW))
            assert error.value.code == 'invalid_preparation_response'
            assert RAW not in error.value.message and not service._gate.locked()
        finally:
            await service.close()
    asyncio.run(run())


def test_prepare_api_contract_and_private_validation():
    class FakeService:
        async def prepare_transcript(self, request):
            return build_preparation(GeneratedPreparation.model_validate(PLAN), preparation_source(request.transcript), 'test')
    with TestClient(create_app(Settings(), service=FakeService())) as client:
        response = client.post('/api/prepare-transcript', json={'transcript': RAW})
        assert response.status_code == 200 and response.headers['Cache-Control'] == 'no-store'
        assert response.json()['participants'][1]['role'] == 'manager'
        invalid = client.post('/api/prepare-transcript', json={'transcript': 'PRIVATE_SENTINEL'})
        assert invalid.status_code == 422 and 'PRIVATE_SENTINEL' not in invalid.text


def test_unpunctuated_text_does_not_trigger_a_paid_request():
    async def run():
        service = AuditService(Settings(api_key='test-only-placeholder'))
        service.client.responses.parse = AsyncMock()
        try:
            with pytest.raises(AnalysisError) as error:
                await service.prepare_transcript(PrepareRequest(transcript='одно длинное предложение без пунктуации и без границ реплик'))
            assert error.value.status == 422
            service.client.responses.parse.assert_not_called()
        finally:
            await service.close()
    asyncio.run(run())
