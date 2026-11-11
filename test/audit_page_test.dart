import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_brick_meeting_auditor/main.dart';

void main() {
  testWidgets('Изменение текста убирает прежний отчёт и блокирует демоанализ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RoyalBrickApp());
    final show = find.byKey(const ValueKey('show-demo-report'));
    await tester.ensureVisible(show);
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(find.text('66 / 100'), findsOneWidget);

    final text = find.byKey(const ValueKey('transcript'));
    await tester.ensureVisible(text);
    await tester.enterText(text, 'Мой изменённый разговор');
    await tester.pumpAndSettle();
    expect(find.text('66 / 100'), findsNothing);
    expect(find.text('Весь отчёт'), findsNothing);
    expect(tester.widget<FilledButton>(show).onPressed, isNull);
    expect(
      find.textContaining('Подготовленный демоотчёт больше не соответствует'),
      findsOneWidget,
    );

    final restore = find.text('Восстановить пример');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(show).onPressed, isNotNull);
    expect(
      find.text('66 / 100'),
      findsNothing,
    ); // Восстановление не создаёт отчёт само.
  });

  testWidgets('Экран и готовый отчёт помещаются на узком экране', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RoyalBrickApp());
    expect(tester.takeException(), isNull);
    final button = find.text('Показать демоанализ');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('66 / 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
