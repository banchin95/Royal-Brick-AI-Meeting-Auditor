import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:royal_brick_meeting_auditor/services/audit_api.dart';
import 'package:royal_brick_meeting_auditor/ui/audit_page.dart';

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
    await tester.pumpWidget(MaterialApp(home: AuditPage(api: api)));
    await tester.tap(find.text('ИИ-анализ'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('show-demo-report'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Анализирую…'), findsOneWidget);
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
    expect(find.textContaining('ИИ-анализ · 13 разделов'), findsOneWidget);

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
