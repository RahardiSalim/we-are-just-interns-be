import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../features/safety/are_you_ok.dart' show SafetyText;
import 'ride.dart';
import 'ride_store.dart';

/// Records the whole ride from the microphone into a [RideStore], piece by piece.
abstract interface class TripRecorder {
  /// `audio/aac` on Android, `audio/wav` on the web preview.
  String get contentType;

  /// False if the user denied the microphone.
  Future<bool> start(String tripId);

  /// Stops and saves the last piece. Returns how long it recorded.
  Future<Duration> stop();
}

class MicRecorder implements TripRecorder {
  MicRecorder(this.store);

  final RideStore store;
  final _rec = AudioRecorder();
  static const _piece = Duration(seconds: 30);

  late String _tripId;
  DateTime? _startedAt;
  final _buffer = BytesBuilder(copy: false);
  var _index = 0;
  Future<void> _writes = Future.value();
  Timer? _timer;
  Completer<void>? _streamDone;

  @override
  String get contentType => kIsWeb ? 'audio/wav' : 'audio/aac';

  @override
  Future<bool> start(String tripId) async {
    if (!await _rec.hasPermission()) return false;
    _tripId = tripId;
    _index = 0;
    _startedAt = DateTime.now();
    if (kIsWeb) {
      // Browsers can't stream AAC: the web preview records one WAV and stores it at stop.
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '',
      );
      return true;
    }
    // Before the mic starts: Android only lets a foreground service keep it on in the background.
    await Ride.startListening(
      SafetyText.listeningTitle,
      SafetyText.listeningBody,
    );
    // A stream (not a file) gives AAC in ADTS frames, which can be cut anywhere and joined again.
    // Each 30-second piece is encrypted and saved at once, so a crash loses at most 30 seconds.
    final stream = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
        // Keep recording through everything: our own alarm, a call, music, a Bluetooth headset
        // dropping. The plugin's default pauses on each, which silenced rides at the alarm.
        audioInterruption: AudioInterruptionMode.none,
        audioRouteChange:
            AudioRouteChangeMode.follow, // switch to the next mic, never stop
      ),
    );
    final done = _streamDone = Completer<void>();
    stream.listen(_buffer.add, onDone: done.complete);
    _timer = Timer.periodic(_piece, (_) => _savePiece());
    return true;
  }

  void _savePiece() {
    if (_buffer.isEmpty) return;
    final bytes = _buffer.takeBytes();
    final index = _index++;
    _writes = _writes.then((_) => store.addPiece(_tripId, index, bytes));
  }

  @override
  Future<Duration> stop() async {
    final length = DateTime.now().difference(_startedAt ?? DateTime.now());
    _timer?.cancel();
    final path = await _rec.stop();
    if (kIsWeb) {
      if (path != null) {
        await store.addPiece(
          _tripId,
          0,
          (await http.get(Uri.parse(path))).bodyBytes,
        );
      }
      return length;
    }
    await _streamDone?.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    _savePiece();
    await _writes;
    await Ride.stopListening();
    return length;
  }
}
