import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../engine/classifier.dart';

/// The text classifier's rules, and the laptop shortcut for testing with a real voice.
///
/// [ModelClassifier] combines the keywords with the IndoBERT-lite model, wherever the model runs: on the
/// phone (`lib/services/edge_ai.dart`, the default on Android) or on the laptop (`stt/dev_server.py`,
/// turned on with `--dart-define=DEV_ML=http://localhost:7088`, used by the web preview).

/// The team classifier's labels (the original 11, or the 5-label scheme) mapped onto the app's 4.
// shortcut: our mapping, not the model author's; the team should confirm it.
const devLabelMap = {
  'LOGISTICS': Label.normal,
  'SERVICE_CONFLICT': Label.normal,
  'NON_PARTICIPANT': Label.normal,
  'PERSONAL_PROBING': Label.uncomfortable,
  'CONTACT_SOLICIT': Label.uncomfortable,
  'INSULT_DEGRADING': Label.uncomfortable,
  'REFUSAL': Label.uncomfortable,
  'APPEARANCE_SEXUAL': Label.sexualHarassment,
  'SEXUAL_EXPLICIT': Label.sexualHarassment,
  'INTIMIDATION': Label.threat,
  'DISTRESS': Label.threat, // the person being harmed asking for help
  // The 5-label scheme (stt/eval/train_classifier.py --scheme 5).
  'normal': Label.normal,
  'uncomfortable': Label.uncomfortable,
  'sexual': Label.sexualHarassment,
  'threat': Label.threat,
  // Refusal or distress from the person being harmed: a reaction, not an offence. On its own it only warns;
  // with harassment or a threat in the same window, those raise the flag.
  'victim': Label.uncomfortable,
};

/// The team model together with the keyword filter, line by line:
/// - The keywords decide on their own, as before: they're precise.
/// - The model alone adds a **warning** at [modelAloneAt] or more. It raises **threat or sexual** on its own
///   only when 2+ lines in the window agree (persistence), so one misread line can't escalate.
/// - Where both say the same harmful label, the higher score counts, which can make it high.
/// A window takes the most severe line, scored by that label's best line.
class ModelClassifier implements Classifier {
  /// [score] gives the model's label and score for one line.
  ModelClassifier(this.score);

  /// The model on the laptop's `stt/dev_server.py`.
  ModelClassifier.server(Uri server) : this((line) => _ask(server, line));

  final Future<(String, double)> Function(String line) score;
  static const modelAloneAt = 0.9;
  static const _victim = {'victim', 'REFUSAL', 'DISTRESS'}; // the person being harmed, in both schemes
  final _keywords = KeywordClassifier();

  /// Each line's raw model answer, e.g. ("threat", 0.97). Shown under the line on screen.
  final raw = <String, (String, double)>{};

  /// Scores a line before the engine hears it, so [classify] (synchronous) already knows it.
  Future<void> learn(String line) async {
    raw[line] = await score(line);
    // Only the recent lines are ever judged (the engine's 15 s window); don't keep a whole day of talk.
    while (raw.length > 200) {
      raw.remove(raw.keys.first);
    }
  }

  static Future<(String, double)> _ask(Uri server, String line) async {
    final res = await http.post(
      server.resolve('/classify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'lines': [line],
      }),
    );
    final r = (jsonDecode(res.body)['results'] as List).single as Map;
    return (r['label'] as String, (r['score'] as num).toDouble());
  }

  /// The line's label and score, plus what the model saw when it decided alone (for the persistence rule).
  (Label, double, Label?) _line(String line) {
    final k = _keywords.classify([line]);
    final r = raw[line];
    final m = r == null ? Label.normal : devLabelMap[r.$1] ?? Label.normal;
    final p = r?.$2 ?? 0;
    if (k.label != Label.normal) {
      return (k.label, m == k.label && p > k.score ? p : k.score, null);
    }
    // Victim speech alone ("halo bagaimana situasi saat ini" read as victim 0.99) is no offence: it only adds
    // weight when a keyword already flagged the window, so the model alone never warns on it.
    if (m != Label.normal && !_victim.contains(r!.$1) && p >= modelAloneAt) {
      return (Label.uncomfortable, p, m);
    }
    return (Label.normal, 0.5, null);
  }

  @override
  Verdict classify(List<String> lines) {
    final each = [
      for (final l in lines)
        switch (_line(l)) {
          (final label, final p, _) => (label, p),
        },
    ];
    // Persistence: the model alone raises threat or sexual when 2+ lines in the window agree (each at
    // modelAloneAt or more). One confident line only warns, so a single misread line can't escalate.
    final alone = [for (final l in lines) _line(l).$3];
    for (final severe in [Label.threat, Label.sexualHarassment]) {
      final idx = [
        for (var i = 0; i < lines.length; i++)
          if (alone[i] == severe) i,
      ];
      if (idx.length >= 2) {
        for (final i in idx) {
          each[i] = (severe, each[i].$2);
        }
      }
    }
    final worst = each
        .map((e) => e.$1)
        .reduce((a, b) => a.index >= b.index ? a : b);
    if (worst == Label.normal) {
      return Verdict(Label.normal, 0.5, List.filled(lines.length, false));
    }
    final score = each
        .where((e) => e.$1 == worst)
        .map((e) => e.$2)
        .reduce((a, b) => a > b ? a : b);
    return Verdict(worst, score, [for (final e in each) e.$1 != Label.normal]);
  }
}

/// Finished utterances from the real microphone, transcribed by the laptop's Whisper.
/// Audio is sent every [chunkSecs] seconds as WAV, carrying an unfinished sentence into the next piece; each line is classified
/// before it's handed on, so [ModelClassifier] already knows it when the engine asks.
// shortcut: a second recorder on the same mic. Fine in a browser; on Android the ride recorder and
// this one would compete for the mic, so use it on the web preview.
Stream<String> devListener(
  Uri server,
  ModelClassifier classifier, {
  int chunkSecs = 15,
  double maxCarrySecs = 10, // a very long sentence is taken anyway, so the buffer can't grow forever
}) async* {
  const sampleRate = 16000;
  const bytesPerSec = sampleRate * 2;
  final rec = AudioRecorder();
  final stream = await rec.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ),
  );
  final buffer = BytesBuilder();
  var offset = 0.0; // where the buffer starts, in seconds since recording began
  var carried =
      0.0; // seconds of a held-back sentence at the start of the buffer
  try {
    await for (final chunk in stream) {
      buffer.add(chunk);
      // A held-back sentence goes again after 3 more seconds, not a full piece: the last thing said (often the
      // safe phrase) must not wait 15 s or be lost when the ride ends.
      final due = carried > 0 ? carried + 3 : chunkSecs;
      if (buffer.length < due * bytesPerSec) continue;
      final pcm = buffer.takeBytes();
      final start = offset;
      final secs = pcm.length / bytesPerSec;
      // The laptop's voice detection finds the speech inside the piece: silence gives no lines.
      final res = await http.post(
        server.resolve('/listen?offset=$start'),
        headers: {'Content-Type': 'audio/wav'},
        body: _wav(pcm, sampleRate),
      );
      // A sentence still going at the end of the piece isn't taken yet: its audio is carried into
      // the next piece, so it's transcribed whole (never cut at the boundary, never twice).
      var keepFrom = secs;
      for (final line in (jsonDecode(res.body)['lines'] as List).cast<Map>()) {
        final from = (line['start'] as num) - start;
        final stillTalking = (line['end'] as num) - start > secs - 0.5;
        if (stillTalking && secs - from < maxCarrySecs) {
          keepFrom = from.toDouble();
          break;
        }
        final text = line['text'] as String;
        await classifier.learn(text);
        yield text;
      }
      final cut = (keepFrom * sampleRate).floor() * 2; // whole 16-bit samples
      buffer.add(pcm.sublist(cut));
      carried = (pcm.length - cut) / bytesPerSec;
      offset = start + cut / bytesPerSec;
    }
  } finally {
    await rec.stop();
    await rec.dispose();
  }
}

Uint8List _wav(Uint8List pcm, int rate) {
  final h = ByteData(44);
  void str(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  h.setUint32(4, 36 + pcm.length, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  str(36, 'data');
  h.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder()
        ..add(h.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
