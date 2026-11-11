import 'package:flutter/material.dart';
import '../domain/audit.dart';
import 'workspace_widgets.dart';

class ScoreOverview extends StatelessWidget {
  const ScoreOverview({super.key, required this.score});
  final ScoreSummary score;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFFF3EBE7),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          score.normalized == null ? score.label : '${score.label} / 100',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: brick,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          score.level,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        Text(
          'Охват оценки: ${number(score.coverage)}%',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: score.coverage / 100,
          minHeight: 5,
          color: brick,
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 10),
        Text(
          '${number(score.earned)} из ${number(score.available)} доступных баллов. '
          '«Н/П» и «Нет данных» исключены из расчёта.',
          style: const TextStyle(fontSize: 12, height: 1.6, color: muted),
        ),
        if (score.coverage < 100) ...[
          const SizedBox(height: 10),
          const Text(
            'Учитывайте охват при сравнении встреч: оценка фрагмента '
            'не равнозначна оценке полной записи.',
            style: TextStyle(fontSize: 12, height: 1.6, color: brick),
          ),
        ],
      ],
    ),
  );
}

class ScoreTable extends StatelessWidget {
  const ScoreTable({super.key, required this.report});
  final AuditReport report;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < criteria.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${criteria[i].title}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      report.stages[i].comment,
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 88,
                child: Text(
                  report.stages[i].status == AssessmentStatus.scored
                      ? '${report.stages[i].label} / ${number(criteria[i].maximum)}'
                      : report.stages[i].label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      const Divider(height: 32),
      const Text(
        'Проверка презентации цены',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < priceSteps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                report.price.checks[i] == CheckStatus.done
                    ? Icons.check_circle_outline
                    : report.price.checks[i] == CheckStatus.notDone
                    ? Icons.highlight_off
                    : Icons.remove_circle_outline,
                size: 18,
                color: report.price.checks[i] == CheckStatus.done
                    ? success
                    : muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${i + 1}. ${priceSteps[i]}\n${report.price.checks[i].label}',
                  style: const TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      Text(
        'Последовательность презентации цены: ${report.price.sequence}.',
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6),
      ),
      const SizedBox(height: 8),
      Text(
        report.price.comment,
        style: const TextStyle(fontSize: 13, height: 1.6, color: muted),
      ),
    ],
  );
}
