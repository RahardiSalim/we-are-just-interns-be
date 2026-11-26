import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../features/safety/are_you_ok.dart' show SafetyText;
import 'ride.dart';

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
    var path = '';
    if (!_web) {
      final dir = await getApplicationSupportDirectory(); // app-private, never in backups or the gallery
      // The last ride's encrypted file has been uploaded (or wasn't needed) by now.
      // shortcut: a failed upload is lost here too; keep it and retry once uploads can fail in the field.
      for (final f in Directory(dir.path).listSync().whereType<File>()) {
        if (f.path.contains('/ride-')) f.deleteSync();
      }
      path = '${dir.path}/ride-${DateTime.now().millisecondsSinceEpoch}.m4a';
      // Before the mic starts: Android only lets a foreground service keep it on in the background.
      await Ride.startListening(
        SafetyText.listeningTitle,
        SafetyText.listeningBody,
      );
    }
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
    if (!_web) await Ride.stopListening();
    if (path == null || _startedAt == null) return null;
    // On the web `path` is a blob URL. On Android the audio is encrypted the moment recording stops.
    // shortcut: the file is plain while the ride is on; encrypt in chunks while recording if rides get long.
    final stored = _web ? path : await Ride.encrypt(path);
    Future<Uint8List> read() async => _web
        ? (await http.get(Uri.parse(path))).bodyBytes
        : Ride.decrypt(stored);
    return Recording(
      read,
      _web ? 'audio/wav' : 'audio/mp4',
      DateTime.now().difference(_startedAt!),
    );
  }

  @override
  Future<void> discard() async {
    await _rec.cancel(); // record's cancel() stops and deletes the file
    if (!_web) await Ride.stopListening();
  }
}
