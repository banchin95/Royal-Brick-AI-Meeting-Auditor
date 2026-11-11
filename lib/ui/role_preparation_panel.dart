import 'package:flutter/material.dart';
import '../domain/preparation.dart';

class RolePreparationPanel extends StatelessWidget {
  const RolePreparationPanel({
    super.key,
    required this.enabled,
    required this.busy,
    required this.hasText,
    required this.suggestion,
    required this.canUndo,
    required this.onRequest,
    required this.onApply,
    required this.onDismiss,
    required this.onUndo,
  });
  final bool enabled, busy, hasText, canUndo;
  final TranscriptPreparation? suggestion;
  final VoidCallback onRequest, onApply, onDismiss, onUndo;

  @override
  Widget build(BuildContext context) {
    final result = suggestion;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E0D9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Кто говорит?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'ИИ предложит менеджера и клиента по смыслу текста. '
            'Если меток нет, предложит границы реплик. Проверьте результат по записи: '
            'такая разметка может ошибаться.',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('prepare-roles'),
            onPressed: enabled && hasText ? onRequest : null,
            icon: const Icon(Icons.people_alt_outlined),
            label: Text(
              busy ? 'Определяю участников…' : 'Определить роли по тексту',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'При нажатии текст передаётся в OpenAI. Оценка встречи запускается отдельно.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF746F69),
              height: 1.5,
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (canUndo) ...[
            const SizedBox(height: 12),
            const Text(
              'Предложенная разметка применена. Проверьте подписи и роли ниже.',
              style: TextStyle(height: 1.5),
            ),
            TextButton(
              key: const ValueKey('undo-role-preparation'),
              onPressed: enabled ? onUndo : null,
              child: const Text('Вернуть исходный текст и роли'),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            Text(
              'Предположение ИИ · ${result.model}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(result.notice, style: const TextStyle(height: 1.5)),
            for (final participant in result.participants) ...[
              const SizedBox(height: 14),
              Text(
                'Участник ${participant.speaker} — ${participant.role.label}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Уверенность модели: ${participant.confidence.label}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF746F69)),
              ),
              const SizedBox(height: 4),
              Text(participant.reason, style: const TextStyle(height: 1.5)),
              Text(
                '«${participant.evidence}»',
                style: const TextStyle(
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Посмотреть разметку реплик'),
              children: [
                SizedBox(
                  height: 260,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result.transcript,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('apply-role-preparation'),
                  onPressed: enabled ? onApply : null,
                  child: const Text('Применить разметку'),
                ),
                TextButton(
                  onPressed: enabled ? onDismiss : null,
                  child: const Text('Оставить исходный текст'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
