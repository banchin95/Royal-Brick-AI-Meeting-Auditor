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
  await tester.pumpWidget(
    MaterialApp(home: AuditPage(api: api, autoPrepareAudio: false)),
  );
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
    'После аудио метки автоматически собираются в предложение, без повторного распознавания',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      final api = AuditApi(
        client: MockClient((request) {
          requests.add(request);
          return pending.future;
        }),
      );
      await tester.pumpWidget(MaterialApp(home: AuditPage(api: api)));
      final panel = tester.widget<AudioPanel>(find.byType(AudioPanel));
      final source = List.generate(
        14,
        (i) =>
            '[${i.toString().padLeft(2, '0')}:01] Участник ${i + 1}: '
            '${i.isEven ? 'Мне нужны панели.' : 'Уточним ваш объект.'}',
      ).join('\n\n');
      final grouped = source.replaceAllMapped(
        RegExp(r'Участник (\d+):'),
        (m) => 'Участник ${int.parse(m[1]!).isOdd ? 1 : 2}:',
      );
      panel.onBusy(true);
      panel.onResult(
        TranscriptionResult(
          text: source,
          speakers: List.generate(14, (i) => i + 1),
          duration: 850,
          notice: 'Метки разных частей.',
          hasSpeakers: true,
        ),
      );
      await tester.pump();
      expect(requests, isEmpty); // Wait until the audio job releases the UI.
      tester.widget<AudioPanel>(find.byType(AudioPanel)).onBusy(false);
      await tester.pump();
      await tester.pump();
      expect(requests.length, 1);
      expect(requests.single.url.path, '/api/prepare-transcript');
      expect(jsonDecode(requests.single.body)['reconcile_speakers'], isTrue);
      expect(find.byKey(const ValueKey('source-speakers-14')), findsNothing);
      expect(
        find.byKey(const ValueKey('role-13-unknown')),
        findsNothing,
      ); // Collapsed, not a wall of controls.
      final proposal = preparationFixture();
      proposal['transcript'] = grouped;
      proposal['source_speaker_count'] = 14;
      final people = proposal['participants'] as List;
      people[0]['source_speakers'] = [1, 3, 5, 7, 9, 11, 13];
      people[1]['source_speakers'] = [2, 4, 6, 8, 10, 12, 14];
      pending.complete(
        http.Response(
          jsonEncode(proposal),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(textInEditor(tester), source);
      await tester.ensureVisible(find.text('Почему такие роли?'));
      await tester.tap(find.text('Почему такие роли?'));
      await tester.pumpAndSettle();
      expect(
        find.text('Исходных меток: 14 → ИИ предлагает участников: 2'),
        findsOneWidget,
      );
      final apply = find.byKey(const ValueKey('apply-role-preparation'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), grouped);
      expect(find.byKey(const ValueKey('role-1-client')), findsOneWidget);
      expect(find.byKey(const ValueKey('role-2-manager')), findsOneWidget);
      expect(requests.length, 1); // No automatic scoring or new audio request.
      final undo = find.byKey(const ValueKey('undo-role-preparation'));
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), source);
      expect(requests.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
      final analyze = find.byKey(const ValueKey('analyze-meeting'));
      expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
      final button = find.byKey(const ValueKey('prepare-roles'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Определяем участников…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transcript')))
            .readOnly,
        isTrue,
      );
      expect(requests.single.url.path, '/api/prepare-transcript');
      expect(requests.single.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(requests.single.body), {
        'transcript': unlabelledText,
        'reconcile_speakers': true,
      });
      pending.complete(
        http.Response(
          jsonEncode(preparationFixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(textInEditor(tester), unlabelledText);
      expect(
        find.byKey(const ValueKey('suggested-role-1-client')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('suggested-role-2-manager')),
        findsOneWidget,
      );
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
            .widget<FilledButton>(find.byKey(const ValueKey('analyze-meeting')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Роль можно исправить в предложении до подтверждения участников',
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
      final request = find.byKey(const ValueKey('prepare-roles'));
      await tester.ensureVisible(request);
      await tester.tap(request);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('suggested-role-2-unknown'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Менеджер').last);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), unlabelledText);
      final apply = find.byKey(const ValueKey('apply-role-preparation'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(textInEditor(tester), preparedText);
      expect(find.byKey(const ValueKey('role-2-manager')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('analyze-meeting')))
            .onPressed,
        isNotNull,
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
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
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
