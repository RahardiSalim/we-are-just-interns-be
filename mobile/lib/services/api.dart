import 'package:http/http.dart' as http;

/// FastAPI client. Every write goes through here, never to Firestore directly.
class Api {
  Api({String? baseUrl})
    // 10.0.2.2 is the host machine as seen from the Android emulator.
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: 'http://10.0.2.2:8000',
          );

  final String baseUrl;

  Future<bool> health() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
