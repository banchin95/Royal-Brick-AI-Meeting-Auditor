import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../domain/audio.dart';

class AudioPreview extends StatefulWidget {
  const AudioPreview({super.key, required this.audio});
  final AudioFileData audio;
  @override
  State<AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<AudioPreview> {
  late String _url;
  web.HTMLAudioElement? _element;

  @override
  void initState() {
    super.initState();
    _createUrl();
  }

  void _createUrl() {
    _url = web.URL.createObjectURL(
      web.Blob(
        [widget.audio.bytes.toJS].toJS,
        web.BlobPropertyBag(type: widget.audio.mimeType),
      ),
    );
  }

  @override
  void didUpdateWidget(AudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      _element?.pause();
      web.URL.revokeObjectURL(_url);
      _createUrl();
    }
  }

  @override
  void dispose() {
    _element?.pause();
    web.URL.revokeObjectURL(_url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    width: double.infinity,
    child: HtmlElementView.fromTagName(
      key: ValueKey(_url),
      tagName: 'audio',
      onElementCreated: (element) {
        final audio = element as web.HTMLAudioElement;
        _element = audio;
        audio
          ..src = _url
          ..controls = true
          ..preload = 'metadata';
        audio.style.width = '100%';
      },
    ),
  );
}
