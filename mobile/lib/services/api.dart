import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../engine/safety_engine.dart';
import 'recorder.dart';

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
  ]) async {
    final res = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Authorization': 'Bearer ${await token()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body ?? {}),
    );
    if (res.statusCode >= 300) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Starts a ride with the rider's answer to the consent prompt. The driver opted in earlier in their
  /// settings. Without an order ID the backend makes one up (demo); in production pass GoJek's.
  Future<String> startTrip({
    required bool riderConsent,
    String? orderId,
  }) async =>
      (await _post('/trips', {
            'riderConsent': riderConsent,
            'orderId': ?orderId,
          }))['tripId']
          as String;

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
    // shortcut: no audio yet (input is mocked), so nothing goes to uploadUrl before finalize.
    await _post('/incidents/$id/finalize');
    return id;
  }

  /// After the ride: the full audio plus the moments an agent should check.
  /// `transcript`: everything speech-to-text heard, timed from the recording start.
  Future<void> uploadRecording(
    String tripId,
    Recording rec,
    List<Marker> markers,
    List<(Duration, String)> transcript,
  ) async {
    final target = await _post('/trips/$tripId/recording', {
      'durationSec': rec.length.inMilliseconds / 1000,
      'contentType': rec.contentType,
      'markers': [for (final m in markers) m.toJson()],
      'transcript': [
        for (final (at, text) in transcript)
          {'at': at.inMilliseconds / 1000, 'text': text},
      ],
    });
    final put =
        http.Request(
            target['uploadMethod'] as String,
            Uri.parse(target['uploadUrl'] as String),
          )
          ..headers['Content-Type'] = rec.contentType
          ..bodyBytes = await rec.read();
    final res = await _http.send(put);
    if (res.statusCode >= 300) {
      throw ApiException(res.statusCode, await res.stream.bytesToString());
    }
    await _post('/trips/$tripId/recording/done');
  }

  Future<void> replyCheckin(String checkinId, bool ok) =>
      _post('/checkins/$checkinId/reply', {'answer': ok ? 'ok' : 'need_help'});
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
