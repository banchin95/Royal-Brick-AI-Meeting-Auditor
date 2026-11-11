import 'dart:typed_data';

class AudioFileData {
  const AudioFileData({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
  final String name;
  final Uint8List bytes;
  final String mimeType;
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.speakers,
    required this.duration,
    required this.notice,
    required this.hasSpeakers,
  });
  final String text;
  final List<int> speakers;
  final double duration;
  final String notice;
  final bool hasSpeakers;

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    final segments = json['segments'] as List;
    return TranscriptionResult(
      text: json['text'] as String,
      speakers: segments.map((s) => s['speaker'] as int).toSet().toList()
        ..sort(),
      duration: (json['duration_seconds'] as num).toDouble(),
      notice: json['notice'] as String,
      hasSpeakers: json['has_speakers'] as bool,
    );
  }
}

String audioTime(int seconds) {
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
