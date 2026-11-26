import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../engine/safety_engine.dart';
import 'ride_store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'API $status: $body';
}

/// FastAPI client. Every write goes through here, never to Firestore directly.
class Api {
  Api({required this.token, String? baseUrl, http.Client? client})
    : baseUrl =
          baseUrl ??
          // 10.0.2.2 is the host machine as seen from the Android emulator.
          const String.fromEnvironment(
            'API_URL',
          ).ifEmpty(kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000'),
      _http = client ?? http.Client();

  /// The signed-in user's Firebase ID token.
  final Future<String?> Function() token;
  final String baseUrl;
  final http.Client _http;

  Future<bool> health() async {
    try {
      final res = await _http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, Object?>? body,
  ]) => _send('POST', path, body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Authorization'] = 'Bearer ${await token()}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body ?? {});
    // A dead connection must fail, not hang: the callers retry, and an SOS shows the 112 banner.
    final res = await http.Response.fromStream(
      await _http.send(req).timeout(const Duration(seconds: 15)),
    );
    if (res.statusCode >= 300) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Starts a ride with the rider's answer to the consent prompt. The driver opted in earlier in their
  /// settings. Without an order ID the backend makes one up (demo); in production pass GoJek's.
  /// A driver's phone joins the rider's trip (`role: driver`); its consent is the Safe Ride setting.
  Future<String> startTrip({
    bool riderConsent = false,
    String role = 'rider',
    String? orderId,
  }) async =>
      (await _post('/trips', {
            'riderConsent': riderConsent,
            'role': role,
            'orderId': ?orderId,
          }))['tripId']
          as String;

  /// The driver's Safe Ride setting: their consent to record rides.
  Future<void> setSafeRide(bool on) =>
      _post('/me/consent', {'audioConsent': on});

  Future<void> endTrip(String tripId) => _post('/trips/$tripId/end');

  /// trigger: sos | manual_unsafe | auto. Sends the phone's transcript window and verdict.
  Future<String> report(
    String tripId,
    String trigger,
    Decision? evidence,
  ) async {
    final now = DateTime.now().toUtc();
    final windowSec = evidence == null || evidence.window.isEmpty
        ? 30.0
        : evidence.window.last.end;
    final created = await _post('/incidents', {
      'tripId': tripId,
      'trigger': trigger,
      'windowStart': now
          .subtract(Duration(milliseconds: (windowSec * 1000).round()))
          .toIso8601String(),
      'windowEnd': now.toIso8601String(),
      if (evidence != null) ...{
        'deviceTranscript': [for (final l in evidence.window) l.toJson()],
        'deviceLabel': evidence.verdict.label.api,
        'deviceScore': evidence.verdict.score,
      },
    });
    final id = created['incidentId'] as String;
    // The ride already had an open case (this phone or the other one): the report joined it.
    if (created['merged'] == true) return id;
    // shortcut: no audio yet (input is mocked), so nothing goes to uploadUrl before finalize.
    await _post('/incidents/$id/finalize');
    return id;
  }

  /// This phone's recording details: markers, transcript and how many pieces are up.
  /// Sent before the first piece, and again as pieces go up.
  Future<void> saveRecording(
    RideMeta ride, {
    required int pieces,
    required bool live,
    required bool done,
  }) => _send('PUT', '/trips/${ride.tripId}/recording', {
    'durationSec': ride.durationSec,
    'contentType': ride.contentType,
    'markers': ride.markers,
    'transcript': ride.transcript,
    'pieces': pieces,
    'live': live,
    'done': done,
  });

  /// Uploads audio piece [n]. Sending it twice overwrites it, so retries are safe.
  Future<void> uploadPiece(
    String tripId,
    int n,
    String contentType,
    Uint8List bytes,
  ) async {
    final target = await _post('/trips/$tripId/recording/pieces/$n');
    final put =
        http.Request(
            target['uploadMethod'] as String,
            Uri.parse(target['uploadUrl'] as String),
          )
          ..headers['Content-Type'] = contentType
          ..bodyBytes = bytes;
    final res = await _http.send(put).timeout(const Duration(seconds: 30));
    if (res.statusCode >= 300) {
      throw ApiException(res.statusCode, await res.stream.bytesToString());
    }
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
