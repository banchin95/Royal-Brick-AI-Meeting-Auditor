enum AssessmentStatus { scored, notApplicable, noData }

enum ParticipantRole {
  manager('Менеджер'),
  client('Клиент'),
  other('Другой участник'),
  unknown('Не определена');

  const ParticipantRole(this.label);
  final String label;
}

class Criterion {
  const Criterion(this.title, this.maximum);
  final String title;
  final double maximum;
}

const criteria = [
  Criterion('Приветствие и установление контакта', 8),
  Criterion('Выявление потребностей', 20),
  Criterion('Сравнение облицовочных материалов', 5),
  Criterion('Презентация продукции Royal Brick', 15),
  Criterion('Эмоциональная презентация', 10),
  Criterion('Расчёт и презентация стоимости', 10),
  Criterion('Закрытие на предоплату', 15),
  Criterion('Работа с возражениями', 10),
  Criterion('Завершение встречи и следующий шаг', 7),
];

class StageEvaluation {
  const StageEvaluation({
    required this.status,
    required this.comment,
    this.points,
  });

  final AssessmentStatus status;
  final double? points;
  final String comment;

  String get label => switch (status) {
    AssessmentStatus.scored => number(points!),
    AssessmentStatus.notApplicable => 'Н/П',
    AssessmentStatus.noData => 'Нет данных',
  };
}

class ScoreSummary {
  const ScoreSummary._(this.earned, this.available);

  factory ScoreSummary.calculate(List<StageEvaluation> stages) {
    if (stages.length != criteria.length) {
      throw ArgumentError('Ожидаются все девять этапов оценки.');
    }
    double earned = 0;
    double available = 0;
    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];
      if (stage.status == AssessmentStatus.scored) {
        final points = stage.points;
        if (points == null ||
            !points.isFinite ||
            points < 0 ||
            points > criteria[i].maximum) {
          throw ArgumentError('Недопустимый балл этапа ${i + 1}.');
        }
        earned += points;
        available += criteria[i].maximum;
      } else if (stage.points != null) {
        throw ArgumentError('Н/П и Нет данных не должны содержать баллы.');
      }
    }
    return ScoreSummary._(earned, available);
  }

  final double earned;
  final double available;
  double? get normalized => available == 0 ? null : earned / available * 100;
  double get coverage => available; // Максимум всех девяти этапов равен 100.
  String get label => normalized == null ? 'Нет данных' : number(normalized!);
  String get level {
    final score = normalized;
    if (score == null) return 'Недостаточно данных';
    if (score >= 90) return 'Отличный уровень';
    if (score >= 80) return 'Хороший уровень';
    if (score >= 70) return 'Удовлетворительный уровень';
    if (score >= 60) return 'Слабая встреча';
    return 'Неудовлетворительное качество';
  }
}

String number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1).replaceAll('.', ',');

class Utterance {
  const Utterance(this.at, this.speaker, this.text);
  final String at;
  final int speaker;
  final String text;
  String get transcriptLine => '[$at] Участник $speaker: $text';
}

class ReportSection {
  const ReportSection(this.body, [this.evidence = const []]);
  final String body;
  final List<Utterance> evidence;
}

const sectionTitles = [
  'Карточка встречи',
  'Общая оценка менеджера',
  'Что менеджер сделал хорошо',
  'Главные ошибки менеджера',
  'Анализ клиента',
  'Разбор возражений',
  'Упущенная возможность продажи',
  'Рекомендации по данному клиенту',
  'Готовый скрипт следующего звонка',
  'Готовое сообщение клиенту',
  'Три рекомендации менеджеру',
  'Краткое резюме для CRM',
  'Заключение руководителю отдела продаж',
];

enum CheckStatus {
  done('Выполнено'),
  notDone('Не выполнено'),
  notApplicable('Неприменимо'),
  noData('Нет данных');

  const CheckStatus(this.label);
  final String label;
}

const priceSteps = [
  'Количество панелей в штуках',
  'Полная цена по прайсу',
  'Рассрочка с акцентом на месячный платёж',
  'Проверка распродажи и озвучивание скидки',
  'Немедленное предложение оформления',
];

class PriceAudit {
  const PriceAudit({
    required this.checks,
    required this.sequence,
    required this.comment,
  });
  final List<CheckStatus> checks;
  final String sequence;
  final String comment;
}

class AuditReport {
  const AuditReport({
    required this.stages,
    required this.sections,
    required this.price,
    this.isAi = false,
    this.model,
  });

  factory AuditReport.fromJson(Map<String, dynamic> json) {
    AssessmentStatus status(String value) => switch (value) {
      'scored' => AssessmentStatus.scored,
      'not_applicable' => AssessmentStatus.notApplicable,
      'no_data' => AssessmentStatus.noData,
      _ => throw const FormatException('Неизвестный статус оценки'),
    };
    CheckStatus check(String value) => switch (value) {
      'done' => CheckStatus.done,
      'not_done' => CheckStatus.notDone,
      'not_applicable' => CheckStatus.notApplicable,
      'no_data' => CheckStatus.noData,
      _ => throw const FormatException('Неизвестный статус проверки цены'),
    };
    final rawStages = json['stages'] as List;
    final rawSections = json['sections'] as List;
    final price = json['price'] as Map<String, dynamic>;
    if (rawStages.length != 9 ||
        rawSections.length != 13 ||
        (price['checks'] as List).length != 5 ||
        json['source'] != 'openai') {
      throw const FormatException('Неверная структура отчёта');
    }
    final report = AuditReport(
      isAi: true,
      model: json['model'] as String,
      stages: rawStages
          .map(
            (stage) => StageEvaluation(
              status: status(stage['status'] as String),
              points: (stage['points'] as num?)?.toDouble(),
              comment: stage['comment'] as String,
            ),
          )
          .toList(),
      sections: rawSections
          .map(
            (section) => ReportSection(
              section['body'] as String,
              (section['evidence'] as List)
                  .map(
                    (quote) => Utterance(
                      quote['at'] as String? ?? 'Без метки',
                      quote['speaker'] as int,
                      quote['text'] as String,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
      price: PriceAudit(
        checks: (price['checks'] as List)
            .map((value) => check(value as String))
            .toList(),
        sequence: price['sequence'] as String,
        comment: price['comment'] as String,
      ),
    );
    final calculated =
        report.score; // Проверяем границы и отсутствие баллов у Н/П.
    final serverScore = json['score'] as Map<String, dynamic>;
    if ((calculated.coverage - (serverScore['coverage'] as num)).abs() > 0.01 ||
        (calculated.earned - (serverScore['earned'] as num)).abs() > 0.01) {
      throw const FormatException('Баллы сервера не совпадают с критериями');
    }
    return report;
  }

  final List<StageEvaluation> stages;
  final List<ReportSection> sections;
  final PriceAudit price;
  final bool isAi;
  final String? model;
  ScoreSummary get score => ScoreSummary.calculate(stages);
  String get crmText => sections[11].body;

  String sectionText(int index) {
    final section = sections[index];
    final buffer = StringBuffer('${index + 1}. ${sectionTitles[index]}\n\n');
    if (index == 1) {
      buffer.writeln('Итог: ${score.label}/100. ${score.level}.');
      buffer.writeln('Охват оценки: ${number(score.coverage)}%.');
      buffer.writeln(
        'Баллы: ${number(score.earned)} из ${number(score.available)} доступных.\n',
      );
      for (var i = 0; i < stages.length; i++) {
        buffer.writeln(
          '${criteria[i].title}: ${stages[i].label} '
          '(максимум ${number(criteria[i].maximum)}). ${stages[i].comment}',
        );
      }
      buffer.writeln('\nПроверка презентации цены:');
      for (var i = 0; i < priceSteps.length; i++) {
        buffer.writeln(
          '${i + 1}. ${priceSteps[i]} — ${price.checks[i].label}.',
        );
      }
      buffer.writeln('Последовательность презентации цены: ${price.sequence}.');
      buffer.writeln('${price.comment}\n');
    }
    buffer.writeln(section.body);
    for (final quote in section.evidence) {
      buffer.writeln(
        '\n[${quote.at}] Участник ${quote.speaker}: «${quote.text}»',
      );
    }
    return buffer.toString().trim();
  }

  String toPlainText() =>
      '${isAi ? 'ROYAL BRICK · ИИ-АНАЛИЗ' : 'ROYAL BRICK · УЧЕБНЫЙ ДЕМОАНАЛИЗ'}\n'
      '${isAi ? 'Отчёт сформирован ИИ. Важные выводы проверьте по записи.' : 'Подготовленный пример, не результат работы ИИ.'}\n\n'
      '${List.generate(sectionTitles.length, sectionText).join('\n\n──────────\n\n')}';
}

class DemoMeeting {
  const DemoMeeting({
    required this.id,
    required this.title,
    required this.description,
    required this.context,
    required this.utterances,
    required this.report,
    this.partial = false,
  });

  final String id;
  final String title;
  final String description;
  final String context;
  final List<Utterance> utterances;
  final AuditReport report;
  final bool partial;
  String get transcript => utterances.map((u) => u.transcriptLine).join('\n\n');

  bool matches(String text, ParticipantRole first, ParticipantRole second) {
    String normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalize(text) == normalize(transcript) &&
        first == ParticipantRole.manager &&
        second == ParticipantRole.client;
  }
}
