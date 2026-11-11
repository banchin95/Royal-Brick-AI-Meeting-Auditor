import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_brick_meeting_auditor/main.dart';

void main() {
  testWidgets(
    'Стартовый экран пустой: без демо, учебных данных и лишних переключателей',
    (tester) async {
      await tester.pumpWidget(const RoyalBrickApp());
      expect(find.text('Загрузить аудио'), findsOneWidget);
      expect(find.text('У меня есть текст'), findsOneWidget);
      expect(find.text('Демо'), findsNothing);
      expect(find.textContaining('учебн'), findsNothing);
      expect(find.text('Разделить по участникам'), findsNothing);
      expect(find.byKey(const ValueKey('transcript')), findsNothing);
      expect(find.text('Отчёт по встрече'), findsNothing);
      await tester.tap(find.text('У меня есть текст'));
      await tester.pumpAndSettle();
      final text = find.byKey(const ValueKey('transcript'));
      expect(tester.widget<TextField>(text).controller!.text, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('analyze-meeting')))
            .onPressed,
        isNull,
      );
      await tester.enterText(text, 'Мой разговор для дальнейшей проверки.');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('new-meeting')));
      await tester.tap(find.byKey(const ValueKey('new-meeting')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transcript')), findsNothing);
      expect(find.text('Добавьте разговор'), findsOneWidget);
    },
  );

  testWidgets(
    'Вставка текста и дополнительные условия доступны на узком экране',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RoyalBrickApp());
      await tester.ensureVisible(find.text('У меня есть текст'));
      await tester.tap(find.text('У меня есть текст'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transcript')),
        'Разговор для проверки размера интерфейса.',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Дополнительно'));
      await tester.tap(find.text('Дополнительно'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('analysis-context')), findsOneWidget);
      expect(find.text('Записана только часть встречи'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
