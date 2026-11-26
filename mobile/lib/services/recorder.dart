import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class Recording {
  const Recording(this.read, this.contentType, this.length);
  final Future<Uint8List> Function() read;
  final String contentType; // what the backend accepts: audio/mp4 | audio/wav
  final Duration length;
}

/// Records the whole ride from the microphone.
abstract interface class TripRecorder {
  /// False if the user denied the microphone.
  Future<bool> start();
  Future<Recording?> stop();

  /// Stops and deletes the recording: the ride had nothing serious enough to share.
  Future<void> discard();
}

class MicRecorder implements TripRecorder {
  final _rec = AudioRecorder();
  DateTime? _startedAt;

  // Browsers can't record AAC, so the web preview records WAV.
  static const _web = kIsWeb;

  @override
  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    // shortcut: a plain temp file, deleted after upload; encrypt it (Android Keystore + AES-GCM)
    // before keeping audio on the phone for any length of time.
    final path = _web
        ? ''
        : '${(await getTemporaryDirectory()).path}/ride-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      RecordConfig(
        encoder: _web ? AudioEncoder.wav : AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 32000,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
    return true;
  }

  @override
  Future<Recording?> stop() async {
    final path = await _rec.stop();
    if (path == null || _startedAt == null) return null;
    // On the web `path` is a blob URL; on Android it's a file.
    Future<Uint8List> read() async => _web
        ? (await http.get(Uri.parse(path))).bodyBytes
        : File(path).readAsBytes();
    return Recording(
      read,
      _web ? 'audio/wav' : 'audio/mp4',
      DateTime.now().difference(_startedAt!),
    );
  }

  @override
  Future<void> discard() => _rec.cancel(); // record's cancel() stops and deletes the file
}
