import 'package:flutter/material.dart';
import '../domain/audit.dart';
import 'report_scores.dart';
import 'workspace_widgets.dart';

class ReportPanel extends StatelessWidget {
  const ReportPanel({super.key, required this.report, required this.onCopy});
  final AuditReport? report;
  final ValueChanged<String> onCopy;
  @override
  Widget build(BuildContext context) {
    final data = report;
    if (data == null) {
      return const SectionCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Готовим отчёт',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Разбираем разговор по 9 критериям. Это может занять несколько минут.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            number: 3,
            title: 'Отчёт по встрече',
            subtitle: '13 разделов с оценкой, выводами и следующим шагом.',
          ),
          const SizedBox(height: 24),
          ScoreOverview(score: data.score),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCopy(data.toPlainText()),
                icon: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Скопировать отчёт'),
              ),
              TextButton.icon(
                onPressed: () => onCopy(data.crmText),
                icon: const Icon(Icons.assignment_outlined, size: 17),
                label: const Text('Резюме для CRM'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Отчёт подготовлен ИИ. Важные выводы проверьте по записи.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < sectionTitles.length; i++)
            ExpansionTile(
              key: ValueKey('${identityHashCode(data)}-section-$i'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 20),
              title: Text(
                '${i + 1}. ${sectionTitles[i]}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              children: [
                if (i == 1) ...[
                  ScoreTable(report: data),
                  const SizedBox(height: 20),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    data.sections[i].body,
                    style: const TextStyle(height: 1.7, fontSize: 14),
                  ),
                ),
                for (final quote in data.sections[i].evidence)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F5F2),
                      border: Border(
                        left: BorderSide(color: Color(0xFFC9A69E), width: 3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${quote.at} · Участник ${quote.speaker}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          '«${quote.text}»',
                          style: const TextStyle(fontSize: 13, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onCopy(data.sectionText(i)),
                    icon: const Icon(Icons.copy_outlined, size: 15),
                    label: const Text('Скопировать раздел'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
