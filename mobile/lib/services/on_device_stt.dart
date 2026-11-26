import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Speech-to-text on the phone (experiment): whisper.cpp through `whisper_ggml`, running the
/// same Indonesian model the benchmark picked (maleo-ai/whisper-small-id, ggml q8_0).
///
/// Turned on with `--dart-define=WHISPER_MODEL=<path to the ggml file on the phone>`. The model is
/// not in the app or the repo (264 MB): put it where the app can read it, for the emulator
/// `adb push` to `/sdcard/Android/data/com.gosafe.gosafe/files/`. Optional `WHISPER_VAD` is the
/// Silero ggml file (about 1 MB) so silence never reaches the decoder.
///
/// Not measured on a phone: speed, memory and battery. Only that it runs.
///
/// Same shape as `devListener` (finished sentences, one string each), so the rest of the app does
/// not change. The words are judged by the app's own classifier, which is the keyword filter today.

/// What the speech-to-text module (stt/stt_service.py) does to a segment, ported to Dart.
class SpeechFilter {
  const SpeechFilter();

  // Same list as HALLUCINATION_PHRASES and LEAD_INS in stt/stt_service.py and stt/dev_server.py.
  static const phrases = [
    'terima kasih telah menonton', 'terima kasih sudah menonton',
    'jangan lupa subscribe', 'like dan subscribe',
    'sampai jumpa di video berikutnya', 'subtitle by', 'amara.org',
    'subscribe', 'tombol like', 'selamat datang di video',
    'selamat datang di channel', 'selamat menikmati video',
    'selamat menonton', 'menonton video ini', 'sampai jumpa di video',
    'video selanjutnya',
  ];
  static const _leadIns = ['lupa like', 'like share', 'jangan lupa like'];

  /// The sentence to use, or null to drop the segment.
  String? clean(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // [BLANK_AUDIO], [Music], (laughs): sounds, not speech.
    if (RegExp(r'^[\[(].*[\])]$').hasMatch(text)) return null;
    final low = text.toLowerCase();
    final cut = [...phrases, ..._leadIns]
        .map(low.indexOf)
        .where((i) => i >= 0)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    // Whisper invents a YouTube outro in a silent tail: keep the real speech before it.
    if (cut != null) text = text.substring(0, cut).replaceAll(RegExp(r'^[ ,.]+|[ ,.]+$'), '');
    if (text.isEmpty) return null;
    if (_compressionRatio(text) > 2.4) return null; // the same phrase over and over
    if (_loops(text)) return null;
    return text;
  }

  /// Whisper on a poor signal loops ("hai hai hai hai ... kita tidur kita tidur"): many words, few
  /// different ones. The compression test above misses short ones. A shout for help ("tolong tolong
  /// tolong") repeats on purpose, so a line with "tolong" is never dropped here.
  bool _loops(String text) {
    final words = text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 6 || words.contains('tolong')) return false;
    return words.toSet().length / words.length < 0.45;
  }

  double _compressionRatio(String text) {
    final bytes = utf8.encode(text);
    return bytes.length / zlib.encode(bytes).length;
  }
}

Uint8List _wav(Uint8List pcm, int rate) {
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(h.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}

/// A 16 kHz mono PCM16 WAV as a stream of raw PCM, as fast as it is consumed. For testing the
/// speech-to-text on a phone or emulator without a microphone.
Stream<Uint8List> pcmFromWav(String path, {int chunkBytes = 32000}) async* {
  final bytes = await File(path).readAsBytes();
  // Walk the RIFF chunks to the "data" one: `afconvert` puts a padding chunk before it.
  var at = 12;
  var from = 44;
  var end = bytes.length;
  final head = ByteData.sublistView(bytes);
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(at, at + 4));
    final size = head.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      from = at + 8;
      end = (from + size).clamp(0, bytes.length);
      break;
    }
    at += 8 + size + (size.isOdd ? 1 : 0);
  }
  for (var i = from; i < end; i += chunkBytes) {
    yield Uint8List.sublistView(bytes, i, (i + chunkBytes).clamp(0, end));
  }
}

/// Finished sentences from [pcm] (the microphone when null), transcribed on the phone.
///
/// Audio is decoded every [chunkSecs] seconds; a sentence still going at the end of a piece is
/// carried into the next one so it is never cut (same rule as `devListener`).
///
/// The microphone is read all the time, apart from the decoding: if decoding is slower than the
/// speech, audio waits in a buffer instead of being lost, and when more than [maxBacklogSecs] is
/// waiting the oldest is dropped and a line is logged, so "can't keep up" is visible.
Stream<String> onDeviceListener({
  required String modelPath,
  String? vadModelPath,
  Stream<Uint8List>? pcm,
  int chunkSecs = 6,
  double maxCarrySecs = 8,
  double? maxBacklogSecs = 30,
  SpeechFilter filter = const SpeechFilter(),
}) async* {
  const sampleRate = 16000;
  const bytesPerSec = sampleRate * 2;
  final whisper = const Whisper(model: WhisperModel.small);
  final dir = (await getTemporaryDirectory()).path;
  AudioRecorder? rec;
  final Stream<Uint8List> stream;
  if (pcm != null) {
    stream = pcm;
    maxBacklogSecs = null; // a file is read at once: nothing is lost by waiting
  } else {
    rec = AudioRecorder();
    stream = await rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );
  }
  var buffer = BytesBuilder(copy: false);
  var offset = 0.0; // seconds of the ride before the start of the buffer
  var done = false;
  var levelAt = 0;

  // Read the microphone on its own, so decoding never stops it.
  final sub = stream.listen(
    (chunk) {
      buffer.add(chunk);
      levelAt += chunk.length;
      if (levelAt >= 2 * bytesPerSec) {
        levelAt = 0;
        final s = Int16List.sublistView(
          Uint8List.fromList(chunk.sublist(0, chunk.length - chunk.length % 2)),
        );
        var sum = 0.0, peak = 0;
        for (final v in s) {
          sum += v * v;
          if (v.abs() > peak) peak = v.abs();
        }
        debugPrint('mic level rms=${s.isEmpty ? 0 : sqrt(sum / s.length).toStringAsFixed(0)} peak=$peak (16-bit, max 32767)');
      }
    },
    onDone: () => done = true,
    onError: (_) => done = true,
  );

  Future<List<({double from, double to, String text})>> decode(Uint8List pcm, int n) async {
    final file = File('$dir/piece_$n.wav')..writeAsBytesSync(_wav(pcm, sampleRate));
    final clock = Stopwatch()..start();
    try {
      final res = await whisper.transcribe(
        modelPath: modelPath,
        transcribeRequest: TranscribeRequest(
          audio: file.path,
          language: 'id', // forced, like the rest of the module
          threads: 4,
          noContext: true,
          maxContext: 0, // each piece on its own: one invented phrase can't repeat
          vadModelPath: vadModelPath,
          vadSpeechPadMs: vadModelPath == null ? null : 250,
          keepModelLoaded: true, // loading takes seconds; keep it for the ride
        ),
      );
      debugPrint('on-device STT decoded ${(pcm.length / bytesPerSec).toStringAsFixed(1)}s of audio '
          'in ${clock.elapsedMilliseconds} ms');
      final segs = res.segments;
      if (segs == null || segs.isEmpty) {
        return res.text.trim().isEmpty
            ? []
            : [(from: 0.0, to: pcm.length / bytesPerSec, text: res.text)];
      }
      return [
        for (final s in segs)
          (from: s.fromTs.inMilliseconds / 1000, to: s.toTs.inMilliseconds / 1000, text: s.text),
      ];
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  Iterable<String> keep(List<({double from, double to, String text})> lines, double secs, void Function(double) carryFrom) sync* {
    for (final line in lines) {
      final stillTalking = line.to > secs - 0.5;
      if (stillTalking && secs - line.from < maxCarrySecs) {
        carryFrom(line.from);
        return;
      }
      final text = filter.clean(line.text);
      debugPrint('on-device STT ${(offset + line.from).toStringAsFixed(1)}s '
          '${text == null ? "DROP" : "KEPT"}: ${line.text.trim()}');
      if (text != null) yield text;
    }
  }

  var n = 0;
  try {
    while (true) {
      if (buffer.length < chunkSecs * bytesPerSec) {
        if (done) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      var audio = buffer.takeBytes();
      buffer = BytesBuilder(copy: false);
      var dropped = 0.0;
      if (maxBacklogSecs != null && audio.length > maxBacklogSecs * bytesPerSec) {
        final cutBytes = (audio.length - (maxBacklogSecs * bytesPerSec).floor()) & ~1;
        audio = audio.sublist(cutBytes);
        dropped = cutBytes / bytesPerSec;
        offset += dropped;
        debugPrint('on-device STT falling behind: dropped ${dropped.toStringAsFixed(1)}s of the oldest audio');
      }
      final secs = audio.length / bytesPerSec;
      List<({double from, double to, String text})> lines;
      try {
        lines = await decode(audio, n++);
      } catch (e) {
        debugPrint('on-device STT failed: $e');
        offset += secs;
        continue;
      }
      var keepFrom = secs;
      yield* Stream.fromIterable(keep(lines, secs, (from) => keepFrom = from).toList());
      final cut = (keepFrom * sampleRate).floor() * 2;
      // Audio that arrived while decoding is already in `buffer`; the unfinished sentence goes in front of it.
      final later = buffer.takeBytes();
      buffer = BytesBuilder(copy: false)
        ..add(audio.sublist(cut))
        ..add(later);
      offset += cut / bytesPerSec;
    }
    // The stream ended (a file, or the ride stopped): decode what is left.
    final rest = buffer.takeBytes();
    if (rest.length > bytesPerSec ~/ 2) {
      try {
        final secs = rest.length / bytesPerSec;
        for (final line in await decode(Uint8List.fromList(rest), n++)) {
          final text = filter.clean(line.text);
          debugPrint('on-device STT ${(offset + line.from).toStringAsFixed(1)}s '
              '${text == null ? "DROP" : "KEPT"}: ${line.text.trim()}');
          if (text != null) yield text;
        }
        offset += secs;
      } catch (e) {
        debugPrint('on-device STT failed: $e');
      }
    }
  } finally {
    await sub.cancel();
    await rec?.stop();
    await rec?.dispose();
    await whisper.releaseModel();
  }
}
