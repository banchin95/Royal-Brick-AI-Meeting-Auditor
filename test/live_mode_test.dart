import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';
import 'package:royal_brick_meeting_auditor/ui/audit_page.dart';
import 'package:royal_brick_meeting_auditor/ui/audio_panel.dart';
import 'package:royal_brick_meeting_auditor/domain/audio.dart';

import 'support/api_fixture.dart';

void main() {
  testWidgets('ИИ-режим показывает ожидание и ответ backend без демоподмены', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<http.Response>();
    final api = AuditApi(client: MockClient((request) => pending.future));
    await tester.pumpWidget(
      MaterialApp(home: AuditPage(api: api, autoPrepareAudio: false)),
    );
    tester
        .widget<AudioPanel>(find.byType(AudioPanel))
        .onResult(
          const TranscriptionResult(
            text:
                'Участник 1: Здравствуйте! Чем могу помочь?\nУчастник 2: Нужна облицовка.',
            speakers: [1, 2],
            duration: 10,
            notice: 'Проверьте текст.',
            hasSpeakers: true,
          ),
        );
    await tester.pumpAndSettle();
    for (final entry in {1: 'Менеджер', 2: 'Клиент'}.entries) {
      final field = find.byKey(ValueKey('role-${entry.key}-unknown'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.value).last);
      await tester.pumpAndSettle();
    }
    final button = find.byKey(const ValueKey('analyze-meeting'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Создаём отчёт…'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    pending.complete(
      http.Response(
        jsonEncode(apiFixture()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('50 / 100'), findsOneWidget);
    expect(find.text('66 / 100'), findsNothing);
    expect(
      find.text('13 разделов с оценкой, выводами и следующим шагом.'),
      findsOneWidget,
    );

    final text = find.byKey(const ValueKey('transcript'));
    await tester.ensureVisible(text);
    await tester.enterText(
      text,
      'Участник 1: Здравствуйте!\nУчастник 2: Нужна облицовка.',
    );
    await tester.pumpAndSettle();
    expect(find.text('50 / 100'), findsNothing);
  });
}
