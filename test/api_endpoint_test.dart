import 'package:flutter_test/flutter_test.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';
import 'package:royal_brick_meeting_auditor/domain/audit.dart';
import 'support/api_fixture.dart';

void main() {
  test('Отчёт Timeweb проходит те же проверки баллов и охвата', () {
    final data = apiFixture()..['source'] = 'timeweb';
    final report = AuditReport.fromJson(data);
    expect(report.score.normalized, 50);
    expect(report.score.coverage, 8);
    expect(report.isAi, isTrue);
  });
  test('Серверная сборка направляет все запросы на HTTPS-адрес сайта', () {
    final page = Uri.parse('https://review.example.com/?view=workspace');
    for (final path in [
      '/api/analyze',
      '/api/prepare-transcript',
      '/api/transcriptions',
      '/api/transcriptions/job',
    ]) {
      expect(
        apiEndpoint('', path, pageUri: page).toString(),
        'https://review.example.com$path',
      );
    }
  });

  test('Локальный и явно указанный backend сохраняют свой адрес', () {
    expect(
      apiEndpoint('http://127.0.0.1:8000', '/api/analyze').toString(),
      'http://127.0.0.1:8000/api/analyze',
    );
    expect(
      apiEndpoint('https://api.example.com/', '/api/analyze').toString(),
      'https://api.example.com/api/analyze',
    );
  });
}
