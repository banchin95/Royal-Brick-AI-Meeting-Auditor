import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/audio.dart';

@JS('MediaRecorder')
external JSAny? get _mediaRecorderConstructor;

class BrowserAudioRecorder {
  BrowserAudioRecorder({this.streamFactory});
  final Future<web.MediaStream> Function()? streamFactory;
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  Completer<web.Blob>? _stopped;
  final List<web.Blob> _chunks = [];
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed || _recorder != null) {
      throw StateError('Запись уже запущена.');
    }
    if (_mediaRecorderConstructor == null) {
      throw UnsupportedError(
        'Браузер не поддерживает запись. Используйте загрузку файла.',
      );
    }
    try {
      final stream =
          await (streamFactory?.call() ??
              web.window.navigator.mediaDevices
                  .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
                  .toDart);
      if (_disposed) {
        for (final track in stream.getTracks().toDart) {
          track.stop();
        }
        throw StateError('Запись закрыта.');
      }
      _stream = stream;
      var mime = '';
      for (final candidate in [
        'audio/webm;codecs=opus',
        'audio/mp4',
        'audio/webm',
      ]) {
        if (web.MediaRecorder.isTypeSupported(candidate)) {
          mime = candidate;
          break;
        }
      }
      _chunks.clear();
      _stopped = Completer<web.Blob>();
      // Consume asynchronous failures even if the user has not pressed Stop yet.
      unawaited(_stopped!.future.then<void>((_) {}, onError: (Object _) {}));
      final recorder = mime.isEmpty
          ? web.MediaRecorder(stream)
          : web.MediaRecorder(
              stream,
              web.MediaRecorderOptions(
                mimeType: mime,
                audioBitsPerSecond: 48000,
              ),
            );
      _recorder = recorder;
      recorder.ondataavailable = ((web.BlobEvent event) {
        if (event.data.size > 0) _chunks.add(event.data);
      }).toJS;
      recorder.onerror = ((web.Event event) {
        if (!_stopped!.isCompleted) {
          _stopped!.completeError(StateError('Не удалось записать звук.'));
        }
        _releaseTracks();
      }).toJS;
      recorder.onstop = ((web.Event event) {
        if (!_stopped!.isCompleted) {
          _stopped!.complete(
            web.Blob(
              _chunks.map<JSAny>((blob) => blob).toList().toJS,
              web.BlobPropertyBag(type: recorder.mimeType),
            ),
          );
        }
      }).toJS;
      recorder.start(1000);
    } catch (error) {
      _releaseTracks();
      _recorder = null;
      if (error.toString().contains('NotAllowed') ||
          error.toString().contains('Permission')) {
        throw StateError(
          'Доступ к микрофону не разрешён. Разрешите его в браузере или загрузите готовый файл.',
        );
      }
      rethrow;
    }
  }

  Future<AudioFileData> stop() async {
    final recorder = _recorder;
    if (recorder == null) throw StateError('Запись не запущена.');
    try {
      if (recorder.state != 'inactive') recorder.stop();
      final blob = await _stopped!.future.timeout(const Duration(seconds: 10));
      final buffer = await blob.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty) throw StateError('Запись получилась пустой.');
      final extension = blob.type.contains('mp4') ? 'm4a' : 'webm';
      return AudioFileData(
        name: 'Запись-${DateTime.now().millisecondsSinceEpoch}.$extension',
        bytes: bytes,
        mimeType: blob.type,
      );
    } finally {
      _releaseTracks();
      _recorder = null;
      _chunks.clear();
    }
  }

  Future<void> cancel() async {
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();
    _releaseTracks();
    if (_stopped != null) {
      try {
        await _stopped!.future.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    _recorder = null;
    _chunks.clear();
  }

  void _releaseTracks() {
    for (final track
        in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
  }

  void dispose() {
    _disposed = true;
    unawaited(cancel());
  }
}
