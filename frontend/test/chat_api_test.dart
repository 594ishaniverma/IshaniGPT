import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/chat_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStorage implements TokenStorage {
  String? value;

  @override
  Future<void> delete({required String key}) async => value = null;

  @override
  Future<String?> read({required String key}) async => value;

  @override
  Future<void> write({required String key, required String value}) async {
    this.value = value;
  }
}

void main() {
  test('uses Bearer authorization after sign in', () async {
    String? authorization;
    final storage = MemoryTokenStorage();
    final api = ChatApi(
      storage: storage,
      client: MockClient((request) async {
        authorization = request.headers['Authorization'];
        if (request.url.path == '/auth/login') {
          return http.Response('''{
            "access_token":"test-token",
            "user":{"id":1,"name":"Ishani","email":"i@example.com"}
          }''', 200);
        }
        return http.Response('''{
          "id":1,"name":"Ishani","email":"i@example.com"
        }''', 200);
      }),
    );

    await api.signIn('i@example.com', 'password');
    await api.currentUser();

    expect(authorization, 'Bearer test-token');
    expect(storage.value, 'test-token');
  });

  test('clears stored session on 401', () async {
    final storage = MemoryTokenStorage()..value = 'expired-token';
    final api = ChatApi(
      storage: storage,
      client: MockClient(
        (request) async => http.Response('{"detail":"Unauthorized"}', 401),
      ),
    );

    await expectLater(api.restoreSession(), completion(false));
    expect(storage.value, isNull);
  });

  test('cancellation stops an in-flight request', () async {
    final cancellation = CancellationToken();
    final api = ChatApi(
      client: MockClient(
        (request) => Future.delayed(
          const Duration(seconds: 1),
          () => http.Response('{}', 200),
        ),
      ),
      requestTimeout: const Duration(seconds: 5),
    );

    final request = api.signIn(
      'i@example.com',
      'password',
      cancellationToken: cancellation,
    );
    cancellation.cancel();

    await expectLater(request, throwsA(isA<ChatApiCancelledException>()));
  });

  test('maps request timeout to ChatApiException', () async {
    final api = ChatApi(
      client: MockClient(
        (request) => Future.delayed(
          const Duration(milliseconds: 50),
          () => http.Response('{}', 200),
        ),
      ),
      requestTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(api.currentUser(), throwsA(isA<ChatApiException>()));
  });
}
