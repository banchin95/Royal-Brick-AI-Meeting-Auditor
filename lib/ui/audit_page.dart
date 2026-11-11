import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/audit.dart';
import '../domain/audio.dart';
import '../domain/preparation.dart';
import '../services/audit_api.dart';
import 'audio_panel.dart';
import 'report_panel.dart';
import 'role_preparation_panel.dart';
import 'workspace_widgets.dart';

class AuditPage extends StatefulWidget {
  const AuditPage({super.key, this.api, this.autoPrepareAudio = true});
  final AuditApi? api;
  final bool autoPrepareAudio;
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _transcript = TextEditingController();
  final _context = TextEditingController();
  final _reviewKey = GlobalKey();
  final _reportKey = GlobalKey();
  late final AuditApi _api;
  bool _busy = false, _audioBusy = false, _preparingRoles = false;
  bool _showReview = false, _partial = false, _autoPreparationPending = false;
  int _revision = 0, _session = 0;
  String? _error, _rolePreparationError, _transcriptionNotice, _roleUndoText;
  Map<int, ParticipantRole> _roles = {};
  Map<int, ParticipantRole>? _roleUndoRoles;
  TranscriptPreparation? _roleSuggestion;
  AuditReport? _report;

  bool get _locked => _busy || _audioBusy || _preparingRoles;
  bool get _hasText => _transcript.text.trim().isNotEmpty;
  bool get _validRoles =>
      _roles.length >= 2 &&
      _roles.length <= 12 &&
      _roles.keys.every((id) => id >= 1 && id <= 12) &&
      _roles.values.where((role) => role == ParticipantRole.manager).length ==
          1 &&
      _roles.values.contains(ParticipantRole.client) &&
      !_roles.values.contains(ParticipantRole.unknown);
  bool get _canAnalyze =>
      !_locked && _validRoles && _transcript.text.trim().length >= 30;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? AuditApi();
  }

  @override
  void dispose() {
    _transcript.dispose();
    _context.dispose();
    _api.close();
    super.dispose();
  }

  void _discardReport() {
    _revision++;
    _report = null;
    _error = null;
  }

  void _clearPreparation() {
    _roleSuggestion = null;
    _roleUndoText = null;
    _roleUndoRoles = null;
    _rolePreparationError = null;
    _autoPreparationPending = false;
  }

  void _syncRoles() {
    _clearPreparation();
    final ids =
        RegExp(r'Участник\s+(\d+)\s*:', caseSensitive: false)
            .allMatches(_transcript.text)
            .map((m) => int.parse(m[1]!))
            .toSet()
            .toList()
          ..sort();
    _roles = {for (final id in ids) id: _roles[id] ?? ParticipantRole.unknown};
  }

  void _newMeeting() => setState(() {
    _session++;
    _transcript.clear();
    _context.clear();
    _roles = {};
    _partial = false;
    _showReview = false;
    _transcriptionNotice = null;
    _clearPreparation();
    _discardReport();
  });
  void _mergeSpeaker(int source, int target) => setState(() {
    _transcript.text = _transcript.text.replaceAll(
      RegExp('Участник\\s+$source\\s*:', caseSensitive: false),
      'Участник $target:',
    );
    _syncRoles();
    _discardReport();
  });
  void _tryAutoPreparation() {
    if (!mounted || !_autoPreparationPending || _locked) return;
    _autoPreparationPending = false;
    unawaited(_prepareRoles());
  }

  void _onTranscribed(TranscriptionResult result) {
    if (!mounted) return;
    setState(() {
      _clearPreparation();
      _transcript.text = result.text;
      _context.clear();
      _showReview = true;
      _partial = true;
      _roles = {for (final id in result.speakers) id: ParticipantRole.unknown};
      _transcriptionNotice = result.notice;
      _discardReport();
      _autoPreparationPending = widget.autoPrepareAudio;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoPreparation());
  }

  Future<void> _prepareRoles() async {
    if (_locked || _transcript.text.trim().length < 30) return;
    final source = _transcript.text;
    setState(() {
      _preparingRoles = true;
      _roleSuggestion = null;
      _rolePreparationError = null;
      _discardReport();
    });
    try {
      final suggestion = await _api.prepareTranscript(source);
      if (!mounted || _transcript.text != source) return;
      setState(() => _roleSuggestion = suggestion);
    } on AuditApiException catch (error) {
      if (mounted) setState(() => _rolePreparationError = error.message);
    } finally {
      if (mounted) setState(() => _preparingRoles = false);
    }
  }

  void _editSuggestion(int speaker, ParticipantRole role) {
    final suggestion = _roleSuggestion;
    if (suggestion == null || _locked) return;
    setState(
      () => _roleSuggestion = TranscriptPreparation(
        transcript: suggestion.transcript,
        notice: suggestion.notice,
        model: suggestion.model,
        sourceSpeakerCount: suggestion.sourceSpeakerCount,
        participants: [
          for (final p in suggestion.participants)
            p.speaker == speaker ? p.withRole(role) : p,
        ],
      ),
    );
  }

  void _applyPreparation() {
    final suggestion = _roleSuggestion;
    if (suggestion == null || _locked) return;
    setState(() {
      _roleUndoText = _transcript.text;
      _roleUndoRoles = Map.of(_roles);
      _transcript.text = suggestion.transcript;
      _roles = {for (final p in suggestion.participants) p.speaker: p.role};
      _roleSuggestion = null;
      _discardReport();
    });
  }

  void _undoPreparation() {
    if (_roleUndoText == null || _locked) return;
    setState(() {
      _transcript.text = _roleUndoText!;
      _roles = _roleUndoRoles!;
      _clearPreparation();
      _discardReport();
    });
  }

  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await _api.analyze(
        transcript: _transcript.text,
        roles: _roles,
        context: _context.text,
        partial: _partial,
      );
      if (!mounted || revision != _revision) return;
      setState(() => _report = report);
      _scrollTo(_reportKey);
    } on AuditApiException catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scrollTo(GlobalKey key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Скопировано')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось скопировать. Выделите текст вручную.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 36,
            24,
            narrow ? 16 : 36,
            40,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'ROYAL BRICK',
                          style: TextStyle(
                            color: brick,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                        if (_showReview || _hasText)
                          TextButton.icon(
                            key: const ValueKey('new-meeting'),
                            onPressed: _locked ? null : _newMeeting,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Новая встреча'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Аудитор встреч',
                    style: TextStyle(
                      fontSize: narrow ? 30 : 38,
                      color: ink,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Из разговора — в понятный отчёт и следующий шаг.',
                    style: TextStyle(color: muted, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  WorkflowSteps(
                    current: _report != null || _busy
                        ? 2
                        : _hasText
                        ? 1
                        : 0,
                  ),
                  const SizedBox(height: 28),
                  AudioPanel(
                    key: ValueKey('audio-$_session'),
                    api: _api,
                    enabled: !_busy && !_preparingRoles,
                    autoPrepareRoles: widget.autoPrepareAudio,
                    onBusy: (value) {
                      if (!mounted) return;
                      setState(() {
                        _audioBusy = value;
                        if (value) _discardReport();
                      });
                      if (!value) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _tryAutoPreparation(),
                        );
                      }
                    },
                    onResult: _onTranscribed,
                    onUseText: () {
                      setState(() => _showReview = true);
                      _scrollTo(_reviewKey);
                    },
                  ),
                  if (_showReview || _hasText) ...[
                    const SizedBox(height: 20),
                    _review(),
                  ],
                  if (_busy || _report != null) ...[
                    const SizedBox(height: 20),
                    ReportPanel(
                      key: _reportKey,
                      report: _report,
                      onCopy: _copy,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Аудио и текст обрабатываются в OpenAI. Данные встречи хранятся в этой вкладке.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _review() => SectionCard(
    key: _reviewKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          number: 2,
          title: 'Проверьте разговор',
          subtitle: 'Исправьте текст и убедитесь, что роли определены верно.',
        ),
        const SizedBox(height: 24),
        TextField(
          key: const ValueKey('transcript'),
          controller: _transcript,
          readOnly: _locked,
          minLines: 6,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: const InputDecoration(
            labelText: 'Текст разговора',
            alignLabelWithHint: true,
            hintText: 'Вставьте разговор или получите текст из аудио.',
          ),
          onChanged: (_) => setState(() {
            _syncRoles();
            _discardReport();
          }),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: !_locked && _hasText
                ? () => _copy(_transcript.text)
                : null,
            icon: const Icon(Icons.copy_outlined, size: 15),
            label: const Text('Скопировать текст'),
          ),
        ),
        const SizedBox(height: 8),
        RolePreparationPanel(
          enabled: !_locked,
          busy: _preparingRoles,
          hasText: _transcript.text.trim().length >= 30,
          suggestion: _roleSuggestion,
          canUndo: _roleUndoText != null,
          error: _rolePreparationError,
          onRequest: _prepareRoles,
          onApply: _applyPreparation,
          onDismiss: () => setState(() => _roleSuggestion = null),
          onUndo: _undoPreparation,
          onRoleChanged: _editSuggestion,
        ),
        if (_roles.isNotEmpty &&
            _roleSuggestion == null &&
            !_preparingRoles) ...[
          const SizedBox(height: 16),
          _participantFields(),
        ],
        const SizedBox(height: 16),
        ExpansionTile(
          key: const ValueKey('meeting-options'),
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Дополнительно',
            style: TextStyle(fontSize: 14, color: muted),
          ),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _partial,
              title: const Text(
                'Записана только часть встречи',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                'Отсутствующие в записи этапы не снижают оценку.',
              ),
              onChanged: _locked
                  ? null
                  : (value) => setState(() {
                      _partial = value;
                      _discardReport();
                    }),
            ),
            TextField(
              key: const ValueKey('analysis-context'),
              controller: _context,
              readOnly: _locked,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Что нужно учесть',
                hintText: 'Дата, условия сделки и другая известная информация.',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(_discardReport),
            ),
            if (_transcriptionNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _transcriptionNotice!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    height: 1.5,
                  ),
                ),
              ),
            if (_roles.length > 2) _mergeTools(),
            const SizedBox(height: 16),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: brick, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('analyze-meeting'),
            onPressed: _canAnalyze ? _analyze : null,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(_busy ? 'Создаём отчёт…' : 'Создать отчёт'),
          ),
        ),
        if (!_validRoles && _hasText && !_preparingRoles) ...[
          const SizedBox(height: 10),
          const Text(
            'Для отчёта выберите одного менеджера и хотя бы одного клиента. Неопределённые роли нужно уточнить.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    ),
  );
  Widget _participantFields() {
    final fields = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 760
            ? 3
            : constraints.maxWidth > 460
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in _roles.entries)
              SizedBox(
                width: width,
                child: DropdownButtonFormField<ParticipantRole>(
                  key: ValueKey('role-${entry.key}-${entry.value.name}'),
                  initialValue: entry.value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Участник ${entry.key}',
                  ),
                  items: ParticipantRole.values
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            r.label,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _locked
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _roles[entry.key] = value;
                              _discardReport();
                            });
                          }
                        },
                ),
              ),
          ],
        );
      },
    );
    return _roles.length <= 6
        ? fields
        : ExpansionTile(
            key: ValueKey('source-speakers-${_roles.length}'),
            title: Text('Исходные метки: ${_roles.length}'),
            subtitle: const Text(
              'Определите участников, чтобы объединить повторы.',
            ),
            children: [fields],
          );
  }

  Widget _mergeTools() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'Исправить метки вручную',
      style: TextStyle(fontSize: 13),
    ),
    children: [
      for (final id in _roles.keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<int>(
            key: ValueKey('merge-$id-${_roles.keys.join('-')}'),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Участник $id — тот же человек, что…',
            ),
            items: [
              for (final target in _roles.keys.where((other) => other != id))
                DropdownMenuItem(
                  value: target,
                  child: Text('Участник $target'),
                ),
            ],
            onChanged: _locked
                ? null
                : (target) {
                    if (target != null) _mergeSpeaker(id, target);
                  },
          ),
        ),
    ],
  );
}
