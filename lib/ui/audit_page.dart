import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../demo/demo_meetings.dart';
import '../domain/audit.dart';
import '../services/audit_api.dart';

const _ink = Color(0xFF302B28);
const _muted = Color(0xFF746F69);
const _brick = Color(0xFF933D32);
const _green = Color(0xFF276447);

class AuditPage extends StatefulWidget {
  const AuditPage({super.key, this.api});
  final AuditApi? api;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  DemoMeeting _meeting = demoMeetings.first;
  late final TextEditingController _transcript;
  late final TextEditingController _context;
  late final AuditApi _api;
  bool _live = false;
  bool _busy = false;
  bool _partial = false;
  int _revision = 0;
  String? _error;
  ParticipantRole _first = ParticipantRole.manager;
  ParticipantRole _second = ParticipantRole.client;
  AuditReport? _report;
  final _reportKey = GlobalKey();

  bool get _matches => _meeting.matches(_transcript.text, _first, _second);
  bool get _originalInput =>
      _matches &&
      _context.text == _meeting.context &&
      _partial == _meeting.partial;
  bool get _validRoles =>
      _first != _second &&
      _first != ParticipantRole.unknown &&
      _second != ParticipantRole.unknown;
  bool get _canAnalyze =>
      !_busy &&
      (_live ? _validRoles && _transcript.text.trim().length >= 30 : _matches);

  @override
  void initState() {
    super.initState();
    _transcript = TextEditingController(text: _meeting.transcript);
    _context = TextEditingController(text: _meeting.context);
    _api = widget.api ?? AuditApi();
  }

  @override
  void dispose() {
    _transcript.dispose();
    _context.dispose();
    _api.close();
    super.dispose();
  }

  void _load(DemoMeeting meeting) => setState(() {
    _meeting = meeting;
    _transcript.text = meeting.transcript;
    _context.text = meeting.context;
    _partial = meeting.partial;
    _first = ParticipantRole.manager;
    _second = ParticipantRole.client;
    _discardReport();
  });

  void _discardReport() {
    _revision++;
    _report = null;
    _error = null;
  }

  Future<void> _analyze() async {
    if (!_canAnalyze) return;
    if (!_live) {
      _showReport();
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await _api.analyze(
        transcript: _transcript.text,
        first: _first,
        second: _second,
        context: _context.text,
        partial: _partial,
      );
      if (!mounted || revision != _revision) return;
      setState(() => _report = report);
      _scrollToReport();
    } on AuditApiException catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showReport() {
    if (!_matches) return;
    setState(() => _report = _meeting.report);
    _scrollToReport();
  }

  void _scrollToReport() {
    if (MediaQuery.sizeOf(context).width < 1080) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final reportContext = _reportKey.currentContext;
        if (mounted && reportContext != null) {
          Scrollable.ensureVisible(
            reportContext,
            duration: const Duration(milliseconds: 350),
          );
        }
      });
    }
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Текст скопирован')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось скопировать. Выделите нужный текст в отчёте.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 16 : 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'ROYAL BRICK',
                        style: TextStyle(
                          color: _brick,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                      _Badge(
                        _live ? 'ИИ-анализ' : 'Демонстрационный режим',
                        _live
                            ? Icons.auto_awesome_outlined
                            : Icons.science_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'Аудитор встреч',
                    style: TextStyle(
                      fontSize: narrow ? 30 : 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Разбор переговоров. Понятная оценка. Следующий шаг к продаже.',
                    style: TextStyle(color: _muted, fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _live
                        ? 'Добавьте текст разговора и укажите роли. Текст и дополнительные данные '
                              'передаются в OpenAI только после нажатия «Анализировать текст».'
                        : 'Выберите учебную встречу и откройте подготовленный разбор. '
                              'Все данные примеров вымышлены. Для своего текста выберите режим ИИ.',
                    style: const TextStyle(color: _muted, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Демо'),
                        icon: Icon(Icons.science_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('ИИ-анализ'),
                        icon: Icon(Icons.auto_awesome_outlined),
                      ),
                    ],
                    selected: {_live},
                    onSelectionChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _live = value.first;
                            _discardReport();
                          }),
                  ),
                  const SizedBox(height: 28),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _Badge('01 · Транскрипция', Icons.notes_outlined),
                      _Badge('02 · Оценка по 9 этапам', Icons.rule_outlined),
                      _Badge(
                        '03 · Отчёт и следующий шаг',
                        Icons.description_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final editor = _editor();
                      final report = Container(
                        key: _reportKey,
                        child: _ReportPanel(
                          report: _report,
                          onCopy: _copy,
                          busy: _busy,
                          live: _live,
                        ),
                      );
                      if (constraints.maxWidth < 1016) {
                        return Column(
                          children: [
                            editor,
                            const SizedBox(height: 24),
                            report,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: editor),
                          const SizedBox(width: 24),
                          Expanded(flex: 6, child: report),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Локальный прототип · Этап 3 из 6 · ${_live ? 'OpenAI API' : 'Демо работает без внешних сервисов'}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editor() => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Транскрипция',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _live ? 'Текст для анализа' : 'Учебные примеры',
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('scenario-${_meeting.id}-${_live && !_originalInput}'),
          initialValue: _live && !_originalInput ? null : _meeting.id,
          isExpanded: true,
          hint: const Text('Выберите учебный пример'),
          decoration: InputDecoration(
            labelText: _live ? 'Загрузить учебный пример' : 'Пример встречи',
          ),
          items: demoMeetings
              .map((m) => DropdownMenuItem(value: m.id, child: Text(m.title)))
              .toList(),
          onChanged: _busy
              ? null
              : (id) {
                  if (id != null) {
                    _load(demoMeetings.firstWhere((m) => m.id == id));
                  }
                },
        ),
        const SizedBox(height: 12),
        Text(
          _live && !_originalInput
              ? 'Собственный текст для ИИ-анализа'
              : _meeting.description,
          style: const TextStyle(color: _muted, height: 1.5),
        ),
        if (!_live && _meeting.partial) ...[
          const SizedBox(height: 12),
          const _Badge('Неполная запись', Icons.timelapse_outlined),
        ],
        const SizedBox(height: 24),
        const Text(
          'Роли участников',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final first = _role(
              1,
              _first,
              (value) => setState(() {
                _first = value;
                _discardReport();
              }),
            );
            final second = _role(
              2,
              _second,
              (value) => setState(() {
                _second = value;
                _discardReport();
              }),
            );
            if (constraints.maxWidth < 360) {
              return Column(
                children: [first, const SizedBox(height: 12), second],
              );
            }
            return Row(
              children: [
                Expanded(child: first),
                const SizedBox(width: 12),
                Expanded(child: second),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('transcript'),
          controller: _transcript,
          readOnly: _busy,
          minLines: 12,
          maxLines: 18,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: const InputDecoration(
            labelText: 'Текст разговора',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(_discardReport),
        ),
        const SizedBox(height: 8),
        Text(
          _live
              ? 'Подпишите реплики «Участник 1: ...» и «Участник 2: ...». '
                    'Метки [00:00] необязательны. Изменения хранятся только в этой вкладке.'
              : 'Временные метки учебные. Текст можно исправлять; изменения пока не сохраняются после перезагрузки.',
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (_live) ...[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Запись неполная',
              style: TextStyle(fontSize: 14),
            ),
            value: _partial,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _partial = value;
                    _discardReport();
                  }),
          ),
          TextField(
            key: const ValueKey('analysis-context'),
            controller: _context,
            readOnly: _busy,
            minLines: 3,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Дополнительные данные и условия',
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontSize: 13, height: 1.6),
            onChanged: (_) => setState(_discardReport),
          ),
          const SizedBox(height: 10),
          const Text(
            'Укажите известные дату, имена, данные сделки и подтверждённые условия компании. '
            'Если сведений нет, оставьте поле пустым.',
            style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
          ),
          if (!_validRoles) ...[
            const SizedBox(height: 12),
            const Text(
              'Назначьте одного менеджера и одного клиента.',
              style: TextStyle(color: _brick),
            ),
          ],
        ] else
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            title: const Text(
              'Контекст учебного примера',
              style: TextStyle(fontSize: 14),
            ),
            children: [
              SelectableText(
                _meeting.context,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: _muted,
                ),
              ),
            ],
          ),
        if (!_live && !_matches) ...[
          const SizedBox(height: 12),
          const Text(
            'Текст или роли изменены. Подготовленный демоотчёт больше не соответствует '
            'этим данным. Восстановите пример, чтобы открыть его разбор.',
            style: TextStyle(color: _brick, height: 1.5),
          ),
        ],
        const SizedBox(height: 20),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: _brick, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey('show-demo-report'),
              onPressed: _canAnalyze ? _analyze : null,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(
                _busy
                    ? 'Анализирую…'
                    : _live
                    ? 'Анализировать текст'
                    : 'Показать демоанализ',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => _load(_meeting),
              child: const Text('Восстановить пример'),
            ),
            if (_live)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _transcript.clear();
                        _context.clear();
                        _partial = false;
                        _discardReport();
                      }),
                child: const Text('Очистить для своего текста'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _role(
    int speaker,
    ParticipantRole value,
    ValueChanged<ParticipantRole> onChanged,
  ) => DropdownButtonFormField<ParticipantRole>(
    key: ValueKey('role-$speaker-${value.name}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: 'Участник $speaker'),
    items: ParticipantRole.values
        .map(
          (r) => DropdownMenuItem(
            value: r,
            child: Text(r.label, style: const TextStyle(fontSize: 14)),
          ),
        )
        .toList(),
    onChanged: _busy
        ? null
        : (role) {
            if (role != null) onChanged(role);
          },
  );
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.report,
    required this.onCopy,
    required this.busy,
    required this.live,
  });
  final AuditReport? report;
  final ValueChanged<String> onCopy;
  final bool busy;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final data = report;
    if (data == null) {
      return _Panel(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Column(
            children: [
              if (busy)
                const CircularProgressIndicator()
              else
                const Icon(Icons.description_outlined, size: 48, color: _brick),
              const SizedBox(height: 20),
              Text(
                busy ? 'Анализирую разговор' : 'Здесь появится разбор встречи',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Девять критериев оценки, проверка презентации цены, '
                'профиль клиента и готовые тексты для следующего контакта.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.7),
              ),
              const SizedBox(height: 24),
              Text(
                busy
                    ? 'Запрос отправлен. Дождитесь отчёта; анализ ограничен по времени.'
                    : live
                    ? 'Добавьте текст и нажмите «Анализировать текст».'
                    : 'Выберите пример и нажмите «Показать демоанализ».',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.6),
              ),
            ],
          ),
        ),
      );
    }
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Отчёт по встрече',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            data.isAi
                ? 'ИИ-анализ · 13 разделов · Важные выводы проверьте по записи'
                : 'Подготовленный учебный разбор · 13 разделов',
            style: const TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          _ScoreOverview(score: data.score),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => onCopy(data.toPlainText()),
                icon: const Icon(Icons.copy_outlined, size: 17),
                label: const Text('Весь отчёт'),
              ),
              OutlinedButton.icon(
                onPressed: () => onCopy(data.crmText),
                icon: const Icon(Icons.assignment_outlined, size: 17),
                label: const Text('Резюме для CRM'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < sectionTitles.length; i++) ...[
            ExpansionTile(
              key: ValueKey('${identityHashCode(data)}-section-$i'),
              initiallyExpanded: i == 1,
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
                  _ScoreTable(report: data),
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
                          style: const TextStyle(color: _muted, fontSize: 12),
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
        ],
      ),
    );
  }
}

class _ScoreOverview extends StatelessWidget {
  const _ScoreOverview({required this.score});
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
            color: _brick,
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
          color: _brick,
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 10),
        Text(
          '${number(score.earned)} из ${number(score.available)} доступных баллов. '
          '«Н/П» и «Нет данных» исключены из расчёта.',
          style: const TextStyle(fontSize: 12, height: 1.6, color: _muted),
        ),
        if (score.coverage < 100) ...[
          const SizedBox(height: 10),
          const Text(
            'Учитывайте охват при сравнении встреч: оценка фрагмента '
            'не равнозначна оценке полной записи.',
            style: TextStyle(fontSize: 12, height: 1.6, color: _brick),
          ),
        ],
      ],
    ),
  );
}

class _ScoreTable extends StatelessWidget {
  const _ScoreTable({required this.report});
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
                        color: _muted,
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
                    ? _green
                    : _muted,
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
        style: const TextStyle(fontSize: 13, height: 1.6, color: _muted),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE6E0D9)),
    ),
    child: child,
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFEEEAE4),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _muted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: const TextStyle(fontSize: 12, color: _ink)),
        ),
      ],
    ),
  );
}
