import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:royal_brick_meeting_auditor/domain/audio.dart';
import 'package:royal_brick_meeting_auditor/domain/audit.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';
import 'package:royal_brick_meeting_auditor/ui/audio_panel.dart';
import 'package:royal_brick_meeting_auditor/ui/audit_page.dart';

void main() {
  test(
    'Аудио загружается multipart без ключа, состояние и отмена используют ID задачи',
    () async {
      final methods = <String>[];
      final api = AuditApi(
        client: MockClient((request) async {
          methods.add(request.method);
          expect(request.headers.containsKey('authorization'), isFalse);
          if (request.method == 'POST') {
            expect(
              request.headers['content-type'],
              contains('multipart/form-data'),
            );
            expect(request.body, contains('sample.wav'));
            expect(request.body, contains('diarize'));
            return http.Response(
              jsonEncode({'id': 'job', 'status': 'preparing'}),
              202,
            );
          }
          expect(request.url.path, '/api/transcriptions/job');
          return http.Response(
            jsonEncode({
              'id': 'job',
              'status': request.method == 'DELETE'
                  ? 'cancelled'
                  : 'transcribing',
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final result = await api.startTranscription(
        AudioFileData(
          name: 'sample.wav',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/wav',
        ),
        true,
      );
      expect(result['id'], 'job');
      expect((await api.transcriptionStatus('job'))['status'], 'transcribing');
      await api.cancelTranscription('job');
      expect(methods, ['POST', 'GET', 'DELETE']);
    },
  );

  testWidgets(
    'После распознавания роли неизвестны, контекст очищен, анализ требует ручного назначения',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: AuditPage(autoPrepareAudio: false)),
      );
      tester
          .widget<AudioPanel>(find.byType(AudioPanel))
          .onResult(
            const TranscriptionResult(
              text:
                  '[00:00] Участник 1: Здравствуйте!\n\n[00:02] Участник 2: Нужны панели.\n\n[00:05] Участник 3: Хочу посмотреть фактуру.',
              speakers: [1, 2, 3],
              duration: 6,
              notice: 'Проверьте участников.',
              hasSpeakers: true,
            ),
          );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('analyze-meeting'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.byKey(const ValueKey('role-3-unknown')), findsOneWidget);
      await tester.ensureVisible(find.text('Дополнительно'));
      await tester.tap(find.text('Дополнительно'));
      await tester.pumpAndSettle();
      final context = tester.widget<TextField>(
        find.byKey(const ValueKey('analysis-context')),
      );
      expect(context.controller!.text, isEmpty);
      expect(find.textContaining('Проверьте участников.'), findsOneWidget);

      Future<void> choose(int id, ParticipantRole role) async {
        final field = find.byKey(ValueKey('role-$id-unknown'));
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(role.label).last);
        await tester.pumpAndSettle();
      }

      await choose(1, ParticipantRole.manager);
      await choose(2, ParticipantRole.client);
      await choose(3, ParticipantRole.other);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Ручное объединение голосов меняет все подписи, сохраняя текст', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: AuditPage(autoPrepareAudio: false)),
    );
    tester
        .widget<AudioPanel>(find.byType(AudioPanel))
        .onResult(
          const TranscriptionResult(
            text:
                '[00:00] Участник 1: Добрый день!\n\n[00:02] Участник 2: Нужны панели.\n\n'
                '[20:05] Участник 3: Покажу образец.\n\n[20:10] Участник 3: Вот фактура.',
            speakers: [1, 2, 3],
            duration: 1212,
            notice: 'Проверьте голоса.',
            hasSpeakers: true,
          ),
        );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Дополнительно'));
    await tester.tap(find.text('Дополнительно'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Исправить метки вручную'));
    await tester.tap(find.text('Исправить метки вручную'));
    await tester.pumpAndSettle();
    final merge = find.byKey(const ValueKey('merge-3-1-2-3'));
    await tester.ensureVisible(merge);
    await tester.tap(merge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Участник 1').last);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('transcript')),
    );
    expect(
      field.controller!.text,
      contains('[20:05] Участник 1: Покажу образец.'),
    );
    expect(
      field.controller!.text,
      contains('[20:10] Участник 1: Вот фактура.'),
    );
    expect(field.controller!.text, isNot(contains('Участник 3:')));
    expect(find.byKey(const ValueKey('role-3-unknown')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
