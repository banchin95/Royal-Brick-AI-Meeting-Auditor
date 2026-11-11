import '../domain/audio.dart';

class BrowserAudioRecorder {
  Future<void> start() async =>
      throw UnsupportedError('Запись доступна в браузере.');
  Future<AudioFileData> stop() async =>
      throw UnsupportedError('Запись не запущена.');
  Future<void> cancel() async {}
  void dispose() {}
}
