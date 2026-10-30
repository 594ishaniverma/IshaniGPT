import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ChatApiException implements Exception {
  const ChatApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract class TokenStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class CancellationToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!isCancelled) _completer.complete();
  }
}

class ChatApiCancelledException implements Exception {
  const ChatApiCancelledException();

  @override
  String toString() => 'The request was cancelled.';
}

class ChatApi {
  ChatApi({
    http.Client? client,
    TokenStorage? storage,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _storage = storage ?? SecureTokenStorage();

  static const _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const _tokenKey = 'ishanigpt_access_token';

  final http.Client _client;
  final TokenStorage _storage;
  final Duration requestTimeout;
  String? _accessToken;

  Future<bool> restoreSession() async {
    _accessToken = await _storage.read(key: _tokenKey);
    if (_accessToken == null) return false;

    try {
      await currentUser();
      return true;
    } on ChatApiException catch (error) {
      if (error.statusCode == 401) {
        _accessToken = null;
        await _storage.delete(key: _tokenKey);
        return false;
      }
      rethrow;
    }
  }

  Future<UserProfile> signIn(
    String email,
    String password, {
    CancellationToken? cancellationToken,
  }) async {
    final response = await _send(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
      cancellationToken: cancellationToken,
    );
    return _saveAuthResponse(response);
  }

  Future<UserProfile> signUp(String name, String email, String password) async {
    final response = await _send(
      'POST',
      '/auth/signup',
      body: {'name': name, 'email': email, 'password': password},
      authenticated: false,
    );
    return _saveAuthResponse(response);
  }

  Future<UserProfile> currentUser() async {
    final json = await _send('GET', '/auth/me');
    return UserProfile.fromJson(json);
  }

  Future<void> signOut() async {
    try {
      await _send('POST', '/auth/logout');
    } finally {
      _accessToken = null;
      await _storage.delete(key: _tokenKey);
    }
  }

  Future<List<Conversation>> conversations() async {
    final json = await _send('GET', '/conversations');
    return (json as List<dynamic>)
        .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> createConversation() async {
    final json = await _send('POST', '/conversations');
    return Conversation.fromJson(json);
  }

  Future<List<ChatMessage>> messages(String threadId) async {
    final json = await _send('GET', '/conversations/$threadId/messages');
    return (json as List<dynamic>)
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage(
    String threadId,
    String content, {
    CancellationToken? cancellationToken,
  }) async {
    final json = await _send(
      'POST',
      '/conversations/$threadId/messages',
      body: {'content': content},
      cancellationToken: cancellationToken,
    );
    return ChatMessage.fromJson(json);
  }

  Stream<String> sendMessageStream(
    String threadId,
    String content, {
    CancellationToken? cancellationToken,
  }) async* {
    if (cancellationToken?.isCancelled ?? false) {
      throw const ChatApiCancelledException();
    }

    final uri = Uri.parse('$_baseUrl/conversations/$threadId/messages/stream');
    final request = http.StreamedRequest('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });
    request.sink.add(utf8.encode(jsonEncode({'content': content})));
    await request.sink.close();
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    final responseFuture = _client.send(request);
    late final http.StreamedResponse response;
    try {
      response = cancellationToken == null
          ? await responseFuture.timeout(requestTimeout)
          : await Future.any<http.StreamedResponse>([
              responseFuture,
              cancellationToken.whenCancelled.then<http.StreamedResponse>((_) {
                throw const ChatApiCancelledException();
              }),
            ]).timeout(requestTimeout);
    } on TimeoutException {
      throw const ChatApiException(
        'The request took too long. Please try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        _accessToken = null;
        await _storage.delete(key: _tokenKey);
      }
      throw ChatApiException(
        _errorMessage(body),
        statusCode: response.statusCode,
      );
    }

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const ChatApiCancelledException();
      }
      buffer += chunk;
      var eventEnd = buffer.indexOf('\n\n');
      while (eventEnd >= 0) {
        final event = buffer.substring(0, eventEnd).replaceAll('\r\n', '\n');
        buffer = buffer.substring(eventEnd + 2);
        for (final line in event.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          final payload = jsonDecode(data);
          if (payload is Map<String, dynamic>) {
            if (payload['error'] is String) {
              throw ChatApiException(payload['error'] as String);
            }
            final delta = payload['delta'];
            if (delta is String && delta.isNotEmpty) yield delta;
          }
        }
        eventEnd = buffer.indexOf('\n\n');
      }
    }
  }

  Future<UserProfile> _saveAuthResponse(Map<String, dynamic> response) async {
    final token = response['access_token'] as String;
    _accessToken = token;
    await _storage.write(key: _tokenKey, value: token);
    return UserProfile.fromJson(response['user'] as Map<String, dynamic>);
  }

  String _errorMessage(String body) {
    try {
      final error = jsonDecode(body) as Map<String, dynamic>;
      final detail = error['detail'];
      if (detail is String) return detail;
      if (detail is List<dynamic>) {
        return detail
            .map((item) {
              if (item is Map<String, dynamic>) return item['msg']?.toString();
              return item.toString();
            })
            .join('\n');
      }
    } on FormatException {
      // Keep the generic message if the server did not return JSON.
    } on TypeError {
      // Keep the generic message if the error body has an unexpected shape.
    }
    return 'Something went wrong. Please try again.';
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw const ChatApiCancelledException();
    }
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    late final http.Response response;
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        _ => throw StateError('Unsupported request method: $method'),
      };
      response = await request.timeout(requestTimeout);
      if (cancellationToken?.isCancelled ?? false) {
        throw const ChatApiCancelledException();
      }
    } on http.ClientException {
      throw const ChatApiException(
        'Could not reach IshaniGPT. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const ChatApiException(
        'The request took too long. Please try again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _errorMessage(response.body);
      if (response.statusCode == 401) {
        _accessToken = null;
        await _storage.delete(key: _tokenKey);
      }
      throw ChatApiException(message, statusCode: response.statusCode);
    }

    if (response.statusCode == 204 || response.body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
