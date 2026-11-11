import 'package:flutter_test/flutter_test.dart';
import 'package:royal_brick_meeting_auditor/demo/demo_meetings.dart';
import 'package:royal_brick_meeting_auditor/domain/audit.dart';

void main() {
  List<StageEvaluation> missing() => List.generate(
    criteria.length,
    (_) => const StageEvaluation(status: AssessmentStatus.noData, comment: ''),
  );

  test('Веса девяти этапов соответствуют спецификации', () {
    expect(criteria.map((c) => c.maximum), [8, 20, 5, 15, 10, 10, 15, 10, 7]);
    expect(criteria.fold<double>(0, (sum, c) => sum + c.maximum), 100);
  });

  test(
    'Полная встреча: пропущенное закрытие даёт 0, итог 66 при охвате 100%',
    () {
      final report = demoMeetings[0].report;
      expect(report.stages[6].points, 0);
      expect(report.stages[6].status, AssessmentStatus.scored);
      expect(
        report.stages[5].points,
        8,
      ); // Нет закрытия (1) и полной последовательности (1).
      expect(report.score.normalized, 66);
      expect(report.score.coverage, 100);
      expect(report.score.level, 'Слабая встреча');
    },
  );

  test('Фрагмент: нормирование 8/10 и охват 10%, а не 8/100', () {
    expect(demoMeetings[1].report.score.normalized, 80);
    expect(demoMeetings[1].report.score.coverage, 10);
  });

  test('Нет возражений: Н/П исключается из знаменателя', () {
    final report = demoMeetings[2].report;
    expect(report.stages[7].status, AssessmentStatus.notApplicable);
    expect(report.score.earned, 77);
    expect(report.score.available, 90);
    expect(report.score.normalized, closeTo(85.555555, 0.00001));
    expect(report.score.label, '85,6');
  });

  test('Нулевая оценка остаётся в знаменателе; Нет данных исключается', () {
    final stages = missing();
    stages[0] = const StageEvaluation(
      status: AssessmentStatus.scored,
      points: 0,
      comment: '',
    );
    final score = ScoreSummary.calculate(stages);
    expect(score.normalized, 0);
    expect(score.coverage, 8);
  });

  test('Без оцениваемых этапов нет ни нуля, ни деления на ноль', () {
    final score = ScoreSummary.calculate(missing());
    expect(score.normalized, isNull);
    expect(score.label, 'Нет данных');
    expect(score.coverage, 0);
  });

  test('Неверное количество этапов и недопустимые баллы отклоняются', () {
    expect(() => ScoreSummary.calculate([]), throwsArgumentError);
    for (final points in [-1.0, 9.0, double.nan, double.infinity]) {
      final stages = missing();
      stages[0] = StageEvaluation(
        status: AssessmentStatus.scored,
        points: points,
        comment: '',
      );
      expect(() => ScoreSummary.calculate(stages), throwsArgumentError);
    }
    final stages = missing();
    stages[0] = const StageEvaluation(
      status: AssessmentStatus.noData,
      points: 0,
      comment: '',
    );
    expect(() => ScoreSummary.calculate(stages), throwsArgumentError);
  });

  test(
    'Каждый пример содержит 13 разделов, 5 проверок цены и подлинные цитаты',
    () {
      for (final meeting in demoMeetings) {
        final report = meeting.report;
        expect(report.sections, hasLength(13));
        expect(report.price.checks, hasLength(5));
        expect(report.crmText.length, lessThanOrEqualTo(1000));
        expect(report.sections[9].body.length, inInclusiveRange(300, 600));
        for (final section in report.sections) {
          expect(section.body.trim(), isNotEmpty);
          for (final quote in section.evidence) {
            expect(meeting.utterances, contains(quote));
            expect(meeting.transcript, contains(quote.transcriptLine));
          }
        }
        final exported = report.toPlainText();
        for (var i = 0; i < sectionTitles.length; i++) {
          expect(exported, contains('${i + 1}. ${sectionTitles[i]}'));
        }
        expect(exported, contains('УЧЕБНЫЙ ДЕМОАНАЛИЗ'));
        expect(exported, contains('Охват оценки:'));
        expect(exported, contains('Последовательность презентации цены:'));
      }
    },
  );

  test('Отчёт доступен только для своего текста и установленных ролей', () {
    for (final m in demoMeetings) {
      expect(
        m.matches(
          m.transcript,
          ParticipantRole.manager,
          ParticipantRole.client,
        ),
        isTrue,
      );
      expect(
        m.matches(
          m.transcript.replaceAll('\n', ' '),
          ParticipantRole.manager,
          ParticipantRole.client,
        ),
        isTrue,
      );
      expect(
        m.matches(
          '${m.transcript} Новая реплика',
          ParticipantRole.manager,
          ParticipantRole.client,
        ),
        isFalse,
      );
      expect(
        m.matches(
          m.transcript,
          ParticipantRole.client,
          ParticipantRole.manager,
        ),
        isFalse,
      );
      expect(
        m.matches(
          m.transcript,
          ParticipantRole.unknown,
          ParticipantRole.client,
        ),
        isFalse,
      );
    }
  });
}
