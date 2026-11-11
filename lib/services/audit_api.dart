import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/audit.dart';

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
    required ParticipantRole first,
    required ParticipantRole second,
    required String context,
    required bool partial,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'transcript': transcript,
              'participants': [
                {'speaker': 1, 'role': first.name},
                {'speaker': 2, 'role': second.name},
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
}
