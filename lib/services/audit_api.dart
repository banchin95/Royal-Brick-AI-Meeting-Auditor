import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/audit.dart';
import '../domain/audio.dart';
import '../domain/preparation.dart';

// An empty API_BASE_URL uses the site's HTTPS origin behind the reverse proxy.
Uri apiEndpoint(String baseUrl, String path, {Uri? pageUri}) => baseUrl.isEmpty
    ? (pageUri ?? Uri.base).resolve(path)
    : Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

class AuditApiException implements Exception {
  const AuditApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuditApi {
  AuditApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8000',
          );

  final http.Client _client;
  final String _baseUrl;

  Future<AuditReport> analyze({
    required String transcript,
    required Map<int, ParticipantRole> roles,
    required String context,
    required bool partial,
  }) async {
    try {
      final response = await _client
          .post(
            apiEndpoint(_baseUrl, '/api/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transcript': transcript,
              'participants': [
                for (final entry in roles.entries)
                  {'speaker': entry.key, 'role': entry.value.name},
              ],
              'context': context,
              'is_partial': partial,
            }),
          )
          .timeout(const Duration(seconds: 135));
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw AuditApiException(
          (body['error'] as Map?)?['message'] as String? ??
              'Не удалось выполнить анализ. Повторите запрос позже.',
        );
      }
      return AuditReport.fromJson(body);
    } on AuditApiException {
      rethrow;
    } on TimeoutException {
      throw const AuditApiException(
        'Время ожидания истекло. Проверьте backend и повторите позже.',
      );
    } on http.ClientException {
      throw const AuditApiException(
        'Нет соединения с backend. Убедитесь, что локальный сервер запущен.',
      );
    } catch (_) {
      throw const AuditApiException(
        'Получен некорректный ответ сервера. Отчёт не показан.',
      );
    }
  }

  void close() => _client.close();

  Future<TranscriptPreparation> prepareTranscript(
    String transcript, {
    bool reconcileSpeakers = true,
  }) async {
    try {
      final response = await _client
          .post(
            apiEndpoint(_baseUrl, '/api/prepare-transcript'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transcript': transcript,
              'reconcile_speakers': reconcileSpeakers,
            }),
          )
          .timeout(const Duration(seconds: 135));
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw AuditApiException(
          (body['error'] as Map?)?['message'] as String? ??
              'Не удалось определить участников. Исходный текст сохранён.',
        );
      }
      return TranscriptPreparation.fromJson(body);
    } on AuditApiException {
      rethrow;
    } on TimeoutException {
      throw const AuditApiException(
        'Время определения участников истекло. Исходный текст сохранён.',
      );
    } on http.ClientException {
      throw const AuditApiException(
        'Нет соединения с backend. Проверьте, что локальный сервер запущен.',
      );
    } catch (_) {
      throw const AuditApiException(
        'Не удалось прочитать разметку сервера. Исходный текст сохранён.',
      );
    }
  }

  Future<Map<String, dynamic>> startTranscription(
    AudioFileData audio,
    bool diarize,
  ) async {
    try {
      final request =
          http.MultipartRequest(
              'POST',
              apiEndpoint(_baseUrl, '/api/transcriptions'),
            )
            ..fields['diarize'] = diarize.toString()
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                audio.bytes,
                filename: audio.name,
              ),
            );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 120));
      final response = await http.Response.fromStream(streamed);
      return _jobResponse(response, expected: 202);
    } on AuditApiException {
      rethrow;
    } catch (_) {
      throw const AuditApiException(
        'Не удалось передать аудио. Проверьте backend и соединение.',
      );
    }
  }

  Future<Map<String, dynamic>> transcriptionStatus(String id) async {
    try {
      final response = await _client
          .get(apiEndpoint(_baseUrl, '/api/transcriptions/$id'))
          .timeout(const Duration(seconds: 15));
      return _jobResponse(response);
    } on AuditApiException {
      rethrow;
    } catch (_) {
      throw const AuditApiException(
        'Нет соединения с задачей распознавания. Проверьте backend.',
      );
    }
  }

  Future<void> cancelTranscription(String id) async {
    final response = await _client
        .delete(apiEndpoint(_baseUrl, '/api/transcriptions/$id'))
        .timeout(const Duration(seconds: 15));
    _jobResponse(response);
  }

  Map<String, dynamic> _jobResponse(
    http.Response response, {
    int expected = 200,
  }) {
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != expected) {
      throw AuditApiException(
        (body['error'] as Map?)?['message'] as String? ??
            'Ошибка обработки аудио.',
      );
    }
    return body;
  }
}
