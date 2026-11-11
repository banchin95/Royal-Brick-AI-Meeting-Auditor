import 'package:flutter/material.dart';
import '../domain/audio.dart';

class AudioPreview extends StatelessWidget {
  const AudioPreview({super.key, required this.audio});
  final AudioFileData audio;
  @override
  Widget build(BuildContext context) =>
      const Text('Прослушивание доступно в Web-версии.');
}
