import 'package:flutter/material.dart';
import '../domain/audit.dart';
import '../domain/preparation.dart';
import 'workspace_widgets.dart';

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
    required this.onRoleChanged,
    this.error,
  });
  final bool enabled, busy, hasText, canUndo;
  final TranscriptPreparation? suggestion;
  final VoidCallback onRequest, onApply, onDismiss, onUndo;
  final void Function(int speaker, ParticipantRole role) onRoleChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final result = suggestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Участники',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (result == null && !busy)
              TextButton.icon(
                key: const ValueKey('prepare-roles'),
                onPressed: enabled && hasText ? onRequest : null,
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('Определить участников'),
              ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 10),
          const Text('Определяем участников…', style: TextStyle(color: muted)),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: const TextStyle(color: brick, height: 1.5),
            ),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Проверьте предложенные роли. Если нужно, выберите другую.',
            style: TextStyle(color: muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 760
                  ? 3
                  : constraints.maxWidth > 460
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in result.participants.take(6))
                    SizedBox(width: width, child: _person(p)),
                ],
              );
            },
          ),
          if (result.participants.length > 6)
            ExpansionTile(
              title: Text('Ещё участники: ${result.participants.length - 6}'),
              children: [
                for (final p in result.participants.skip(6)) _person(p),
              ],
            ),
          ExpansionTile(
            key: const ValueKey('role-reasons'),
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Почему такие роли?',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            children: [
              if (result.sourceSpeakerCount > 0)
                Text(
                  'Исходных меток: ${result.sourceSpeakerCount} → '
                  'ИИ предлагает участников: ${result.participants.length}',
                ),
              Text(
                result.notice,
                style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
              ),
              for (final p in result.participants)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Участник ${p.speaker}: ${p.manuallyEdited ? 'роль изменена вами' : p.reason}'
                      '${p.sourceSpeakers.length > 1 ? '\nОбъединены метки: ${p.sourceSpeakers.join(', ')}' : ''}',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.transcript,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('apply-role-preparation'),
                onPressed: enabled ? onApply : null,
                child: const Text('Подтвердить участников'),
              ),
              TextButton(
                onPressed: enabled ? onDismiss : null,
                child: const Text('Оставить мой текст'),
              ),
            ],
          ),
        ] else if (!busy)
          const Text(
            'Выберите роли или определите их автоматически.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        if (canUndo)
          TextButton(
            key: const ValueKey('undo-role-preparation'),
            onPressed: enabled ? onUndo : null,
            child: const Text('Отменить разметку'),
          ),
      ],
    );
  }

  Widget _person(SpeakerSuggestion person) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F5F2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ParticipantRole>(
          key: ValueKey('suggested-role-${person.speaker}-${person.role.name}'),
          initialValue: person.role,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Участник ${person.speaker}'),
          items: ParticipantRole.values
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(
                    r.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (role) {
                  if (role != null) onRoleChanged(person.speaker, role);
                }
              : null,
        ),
        const SizedBox(height: 10),
        Text(
          '«${person.evidence}»',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
        ),
      ],
    ),
  );
}
