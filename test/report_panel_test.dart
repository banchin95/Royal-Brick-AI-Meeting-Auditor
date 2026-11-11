import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_brick_meeting_auditor/domain/audit.dart';
import 'package:royal_brick_meeting_auditor/ui/report_panel.dart';
import 'support/api_fixture.dart';

void main() {
  testWidgets(
    'На телефоне доступны все разделы, оценки, цитаты и копирование',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = AuditReport.fromJson(apiFixture());
      final copied = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReportPanel(report: report, onCopy: copied.add),
            ),
          ),
        ),
      );
      expect(find.byType(ExpansionTile), findsNWidgets(13));
      expect(find.text('50 / 100'), findsOneWidget);
      expect(find.text('Охват оценки: 8%'), findsOneWidget);
      expect(find.text('Оценён только контакт.'), findsNothing);
      await tester.tap(find.text('Скопировать отчёт'));
      await tester.tap(find.text('Резюме для CRM'));
      expect(copied, [report.toPlainText(), report.crmText]);
      final scoreSection = find.text('2. ${sectionTitles[1]}');
      await tester.ensureVisible(scoreSection);
      await tester.tap(scoreSection);
      await tester.pumpAndSettle();
      expect(find.text('Оценён только контакт.'), findsOneWidget);
      expect(find.text('Проверка презентации цены'), findsOneWidget);
      expect(find.text('Н/П'), findsNothing);
      expect(find.text('Нет данных'), findsWidgets);
      final firstSection = find.text('1. ${sectionTitles[0]}');
      await tester.ensureVisible(firstSection);
      await tester.tap(firstSection);
      await tester.pumpAndSettle();
      expect(find.text('«Здравствуйте!»'), findsOneWidget);
      final copySection = find.text('Скопировать раздел').first;
      await tester.ensureVisible(copySection);
      await tester.tap(copySection);
      expect(copied.last, report.sectionText(0));
      expect(tester.takeException(), isNull);
    },
  );
}
