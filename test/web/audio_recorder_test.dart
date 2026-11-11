@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:royal_brick_meeting_auditor/services/audio_recorder_web.dart';

void main() {
  test(
    'MediaRecorder сохраняет аудио и останавливает все треки синтетического источника',
    () async {
      final context = web.AudioContext();
      final destination = context.createMediaStreamDestination();
      final oscillator = context.createOscillator();
      oscillator.connect(destination);
      final silentOutput = context.createGain();
      silentOutput.gain.value = 0;
      oscillator.connect(silentOutput);
      silentOutput.connect(context.destination);
      oscillator.start();
      await context.resume().toDart.timeout(const Duration(seconds: 3));
      final tracks = destination.stream.getTracks().toDart;
      final recorder = BrowserAudioRecorder(
        streamFactory: () async => destination.stream,
      );
      try {
        await recorder.start();
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (context.currentTime < 1 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(context.state, 'running');
        expect(context.currentTime, greaterThan(1));
        final audio = await recorder.stop();
        expect(audio.bytes.length, greaterThan(0));
        expect(audio.mimeType, startsWith('audio/'));
        expect(tracks.every((track) => track.readyState == 'ended'), isTrue);
      } finally {
        recorder.dispose();
        oscillator.stop();
        await context.close().toDart;
      }
    },
  );
}
