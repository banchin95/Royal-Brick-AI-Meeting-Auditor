import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/audio.dart';
import '../services/audio_recorder.dart';
import '../services/audit_api.dart';
import 'audio_preview.dart';
import 'workspace_widgets.dart';

class AudioPanel extends StatefulWidget {
  const AudioPanel({
    super.key,
    required this.api,
    required this.enabled,
    required this.onBusy,
    required this.onResult,
    required this.onUseText,
    this.autoPrepareRoles = false,
  });
  final AuditApi api;
  final bool enabled;
  final ValueChanged<bool> onBusy;
  final ValueChanged<TranscriptionResult> onResult;
  final VoidCallback onUseText;
  final bool autoPrepareRoles;
  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> {
  final _recorder = BrowserAudioRecorder();
  AudioFileData? _audio;
  Timer? _timer;
  int _seconds = 0;
  DateTime? _recordingStartedAt;
  int _generation = 0;
  bool _recording = false, _working = false, _recognizing = false;
  String? _jobId, _error;
  String _status = '';

  bool get _locked => !widget.enabled || _working || _recognizing || _recording;

  Future<void> _pick() async {
    if (_locked) return;
    setState(() {
      _working = true;
      _error = null;
      _status = '';
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'm4a',
          'mp3',
          'wav',
          'webm',
          'ogg',
          'flac',
          'aac',
          'mp4',
        ],
        withData: false,
        withReadStream: true,
      );
      if (selection == null || !mounted) return;
      final file = selection.files.single;
      if (file.size > 100 * 1024 * 1024) {
        throw const AuditApiException(
          'Выберите файл размером не более 100 МБ.',
        );
      }
      final builder = BytesBuilder(copy: false);
      if (file.bytes != null) {
        builder.add(file.bytes!);
      } else if (file.readStream != null) {
        await for (final chunk in file.readStream!) {
          builder.add(chunk);
          if (builder.length > 100 * 1024 * 1024) {
            throw const AuditApiException('Файл превышает лимит 100 МБ.');
          }
        }
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const AuditApiException('Не удалось прочитать аудиофайл.');
      }
      final ext = file.name.split('.').last.toLowerCase();
      final mime =
          {
            'mp3': 'audio/mpeg',
            'm4a': 'audio/mp4',
            'mp4': 'audio/mp4',
            'webm': 'audio/webm',
            'wav': 'audio/wav',
            'ogg': 'audio/ogg',
            'flac': 'audio/flac',
            'aac': 'audio/aac',
          }[ext] ??
          'audio/mpeg';
      if (mounted) {
        setState(() {
          _audio = AudioFileData(name: file.name, bytes: bytes, mimeType: mime);
          _seconds = 0;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AuditApiException
              ? error.message
              : 'Не удалось выбрать аудиофайл.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _start() async {
    if (_locked) return;
    setState(() {
      _working = true;
      _error = null;
    });
    widget.onBusy(true);
    try {
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _seconds = 0;
        _recordingStartedAt = DateTime.now();
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(
            () => _seconds = DateTime.now()
                .difference(_recordingStartedAt!)
                .inSeconds,
          );
        }
        if (_seconds >= 3600) unawaited(_stop());
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
      widget.onBusy(false);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording || _working) return;
    _timer?.cancel();
    setState(() => _working = true);
    try {
      final audio = await _recorder.stop();
      if (mounted) setState(() => _audio = audio);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Не удалось завершить запись. Попробуйте ещё раз.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _recording = false;
          _working = false;
        });
      }
      widget.onBusy(false);
    }
  }

  Future<void> _recognize() async {
    final audio = _audio;
    if (_locked || audio == null) return;
    final generation = ++_generation;
    setState(() {
      _recognizing = true;
      _error = null;
      _status = 'Загружаем аудио…';
    });
    widget.onBusy(true);
    try {
      var job = await widget.api.startTranscription(audio, false);
      if (!mounted || generation != _generation) {
        await widget.api.cancelTranscription(job['id'] as String);
        return;
      }
      _jobId = job['id'] as String;
      final deadline = DateTime.now().add(const Duration(minutes: 16));
      while (mounted && generation == _generation) {
        final status = job['status'] as String;
        if (status == 'completed') {
          widget.onResult(
            TranscriptionResult.fromJson(job['result'] as Map<String, dynamic>),
          );
          setState(
            () => _status =
                'Распознавание готово. Проверьте участников и текст ниже.',
          );
          return;
        }
        if (status == 'failed') {
          throw AuditApiException((job['error'] as Map)['message'] as String);
        }
        if (status == 'cancelled') {
          throw const AuditApiException('Распознавание отменено.');
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const AuditApiException(
            'Время ожидания истекло. Попробуйте запись короче.',
          );
        }
        setState(
          () => _status =
              '${status == 'preparing' ? 'Подготавливаем аудио' : 'Распознаём речь'}'
              '${(job['total_parts'] as num? ?? 0) > 1 ? ' · готово частей ${job['completed_parts']} из ${job['total_parts']}' : ''} · '
              '${audioTime((job['elapsed_seconds'] as num).toInt())}',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || generation != _generation) return;
        job = await widget.api.transcriptionStatus(_jobId!);
      }
    } catch (error) {
      if (_jobId != null) {
        try {
          await widget.api.cancelTranscription(_jobId!);
        } catch (_) {}
      }
      if (mounted && generation == _generation) {
        setState(() {
          _error = error is AuditApiException
              ? error.message
              : 'Не удалось распознать запись. Проверьте соединение.';
          _status = 'Распознавание не завершено.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _recognizing = false;
          _jobId = null;
        });
        widget.onBusy(false);
      }
    }
  }

  Future<void> _cancel() async {
    final id = _jobId;
    _generation++;
    try {
      if (id != null) await widget.api.cancelTranscription(id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось подтвердить отмену на сервере. Ожидание в интерфейсе остановлено.',
        );
      }
    }
    if (mounted) {
      setState(() {
        _recognizing = false;
        _jobId = null;
        _status = 'Ожидание остановлено.';
      });
    }
    widget.onBusy(false);
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _recorder.dispose();
    if (_jobId != null) {
      unawaited(
        widget.api.cancelTranscription(_jobId!).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          number: 1,
          title: 'Добавьте разговор',
          subtitle: 'Загрузите аудио или запишите встречу с микрофона.',
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _locked ? null : _pick,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Загрузить аудио'),
            ),
            OutlinedButton.icon(
              onPressed: !widget.enabled || _working || _recognizing
                  ? null
                  : _recording
                  ? _stop
                  : _start,
              icon: Icon(
                _recording
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none_outlined,
              ),
              label: Text(
                _recording
                    ? 'Остановить · ${audioTime(_seconds)}'
                    : 'Записать разговор',
              ),
            ),
            TextButton(
              onPressed: _locked ? null : widget.onUseText,
              child: const Text('У меня есть текст'),
            ),
          ],
        ),
        if (_recording) ...[
          const SizedBox(height: 12),
          const Text(
            'Идёт запись с микрофона. Максимум 60 минут. Нажмите «Остановить», чтобы сохранить её в этой вкладке.',
            style: TextStyle(color: Color(0xFF933D32), height: 1.6),
          ),
        ],
        if (_audio != null && !_recording) ...[
          const SizedBox(height: 18),
          Text(
            '${_audio!.name} · ${(_audio!.bytes.length / 1024 / 1024).toStringAsFixed(1)} МБ',
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.6),
          ),
          const SizedBox(height: 10),
          AudioPreview(audio: _audio!),
          const SizedBox(height: 12),
          Text(
            widget.autoPrepareRoles
                ? 'Получим текст и автоматически определим участников.'
                : 'Получим текст разговора для проверки.',
            style: const TextStyle(fontSize: 13, color: muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _locked ? null : _recognize,
                icon: const Icon(Icons.graphic_eq),
                label: const Text('Распознать аудио'),
              ),
              if (_recognizing && _jobId != null)
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Отменить распознавание'),
                ),
            ],
          ),
        ],
        if (_working || _recognizing) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(height: 1.6)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF933D32), height: 1.6),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'MP3, M4A, WAV и другие форматы · до 100 МБ · до 60 минут',
          style: TextStyle(fontSize: 12, color: muted, height: 1.5),
        ),
      ],
    ),
  );
}
