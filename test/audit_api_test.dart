import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:royal_brick_meeting_auditor/domain/audit.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';

import 'support/api_fixture.dart';

void main() {
  test(
    'HTTP-запрос передаёт текст, роли и контекст, ответ сохраняет тип ИИ',
    () async {
      final api = AuditApi(
        client: MockClient((request) async {
          expect(request.url.path, '/api/analyze');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['participants'][0]['role'], 'client');
          expect(body['participants'][1]['role'], 'manager');
          expect(body['is_partial'], isTrue);
          expect(body['context'], 'Подтверждённых условий нет');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode(apiFixture()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      final report = await api.analyze(
        transcript: 'Учебный текст',
        roles: {1: ParticipantRole.client, 2: ParticipantRole.manager},
        context: 'Подтверждённых условий нет',
        partial: true,
      );
      expect(report.isAi, isTrue);
      expect(report.score.normalized, 50);
      expect(report.score.coverage, 8);
      expect(report.sections.first.evidence.first.at, 'Без метки');
      expect(report.toPlainText(), contains('ROYAL BRICK · ИИ-АНАЛИЗ'));
      expect(report.toPlainText(), isNot(contains('Подготовленный пример')));
    },
  );

  test(
    'Сообщение о недоступной квоте видно пользователю без демоподмены',
    () async {
      final api = AuditApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'quota_exceeded',
                'message': 'Проверьте баланс API',
              },
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);
      expect(
        () => api.analyze(
          transcript: 'Текст',
          roles: {1: ParticipantRole.manager, 2: ParticipantRole.client},
          context: '',
          partial: false,
        ),
        throwsA(
          isA<AuditApiException>().having(
            (e) => e.message,
            'message',
            'Проверьте баланс API',
          ),
        ),
      );
    },
  );

  test('Неверная структура или баллы API отклоняются', () {
    final payload = apiFixture();
    (payload['score'] as Map)['earned'] = 99;
    expect(() => AuditReport.fromJson(payload), throwsFormatException);
    (payload['sections'] as List).removeLast();
    expect(() => AuditReport.fromJson(payload), throwsFormatException);
  });
}
