import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:royal_brick_meeting_auditor/domain/audio.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';
import 'package:royal_brick_meeting_auditor/ui/audio_panel.dart';
import 'package:royal_brick_meeting_auditor/ui/audit_page.dart';
import 'support/preparation_fixture.dart';

Future<void> loadPlainText(
  WidgetTester tester,
  AuditApi api, {
  bool narrow = false,
}) async {
  tester.view.physicalSize = narrow
      ? const Size(390, 900)
      : const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: AuditPage(api: api)));
  tester
      .widget<AudioPanel>(find.byType(AudioPanel))
      .onResult(
        const TranscriptionResult(
          text: unlabelledText,
          speakers: [],
          duration: 20,
          notice: 'Без меток говорящих.',
          hasSpeakers: false,
        ),
      );
  await tester.pumpAndSettle();
}

String textInEditor(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('transcript')))
    .controller!
    .text;

void main() {
  testWidgets(
    'Предположение не меняет текст до применения; отмена возвращает исходник',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final api = AuditApi(
        client: MockClient((request) {
          requests.add(request);
          return pending.future;
        }),
      );
      await loadPlainText(tester, api);
      final analyze = find.byKey(const ValueKey('show-demo-report'));
      expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
      final button = find.byKey(const ValueKey('prepare-roles'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Определяю участников…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transcript')))
            .readOnly,
        isTrue,
      );
      expect(requests.single.url.path, '/api/prepare-transcript');
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(requests.single.body), {'transcript': unlabelledText});
      pending.complete(
        http.Response(
          jsonEncode(preparationFixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(textInEditor(tester), unlabelledText);
      expect(find.text('Участник 1 — Клиент'), findsOneWidget);
      expect(find.text('Участник 2 — Менеджер'), findsOneWidget);
      expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
      final apply = find.byKey(const ValueKey('apply-role-preparation'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), preparedText);
      expect(find.byKey(const ValueKey('role-1-client')), findsOneWidget);
      expect(find.byKey(const ValueKey('role-2-manager')), findsOneWidget);
      expect(tester.widget<FilledButton>(analyze).onPressed, isNotNull);
      expect(requests.length, 1); // Preparing/applying never starts an audit.
      final undo = find.byKey(const ValueKey('undo-role-preparation'));
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), unlabelledText);
      expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Неуверенные роли блокируют оценку; разметка помещается на телефоне',
    (tester) async {
      final api = AuditApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(preparationFixture(unknownManager: true)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await loadPlainText(tester, api, narrow: true);
      final button = find.byKey(const ValueKey('prepare-roles'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final apply = find.byKey(const ValueKey('apply-role-preparation'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('role-2-unknown')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('show-demo-report')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ошибка определения ролей сохраняет исходник и позволяет повторить запрос',
    (tester) async {
      final api = AuditApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'invalid_preparation_response',
                'message': 'Разметка не прошла проверку.',
              },
            }),
            502,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await loadPlainText(tester, api);
      final button = find.byKey(const ValueKey('prepare-roles'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), unlabelledText);
      expect(find.text('Разметка не прошла проверку.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('apply-role-preparation')),
        findsNothing,
      );
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    },
  );

  testWidgets('Правка исходника убирает устаревшее предположение', (
    tester,
  ) async {
    final api = AuditApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(preparationFixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await loadPlainText(tester, api);
    final button = find.byKey(const ValueKey('prepare-roles'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('transcript'));
    await tester.ensureVisible(editor);
    await tester.enterText(editor, '$unlabelledText Новая реплика.');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('apply-role-preparation')), findsNothing);
    expect(textInEditor(tester), endsWith('Новая реплика.'));
  });
}
