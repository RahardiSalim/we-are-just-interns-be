import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safe_phrase.dart';
import 'package:gosafe/engine/safety_engine.dart';
import 'package:gosafe/services/dev_ml.dart';

/// Replays eval transcripts (stt/eval/score.py transcribe) through the app's own decision code:
/// the keywords + team model (DevClassifier), the safe phrase, and SafetyEngine's rules.
/// Skipped unless EVAL_ASR is set; stt/eval/run.sh runs it.
void main() {
  final input = Platform.environment['EVAL_ASR'];
  test('replay eval transcripts through the app rules', () {
    const phrase = SafePhrase(
      String.fromEnvironment(
        'SAFE_PHRASE',
        defaultValue: 'Pak, nanti lewat jalan biasa aja ya',
      ),
    );
    final out = [];
    for (final f in jsonDecode(File(input!).readAsStringSync()) as List) {
      final lines = (f['lines'] as List).cast<Map<String, dynamic>>();
      final clf = DevClassifier(Uri.parse('http://unused'));
      for (final l in lines) {
        final m = l['model'] as List;
        clf.raw[l['text'] as String] = (
          m[0] as String,
          (m[1] as num).toDouble(),
        );
      }
      var now = DateTime(2026);
      final engine = SafetyEngine(classifier: clf, clock: () => now);
      var safePhraseUsed = false;
      final actions = [];
      for (final l in lines) {
        now = DateTime(2026)
            .add(Duration(milliseconds: ((l['end'] as num) * 1000).round()));
        final text = l['text'] as String;
        // As in TripScreen._onHeard: the safe phrase is a silent SOS and the line goes no further.
        if (!safePhraseUsed && phrase.heardIn(text)) {
          safePhraseUsed = true;
          actions.add({'action': 'sos'});
          continue;
        }
        final d = engine.hear(text);
        actions.add({
          'action': switch (d.action) {
            SafetyAction.warn => 'warning',
            SafetyAction.high => 'high',
            SafetyAction.none => 'none',
          },
          'label': d.verdict.label.api,
          'score': d.verdict.score,
        });
      }
      out.add({'file': f['file'], 'actions': actions});
    }
    File(Platform.environment['EVAL_ACTIONS']!)
        .writeAsStringSync(jsonEncode(out));
  }, skip: input == null ? 'set EVAL_ASR to run (stt/eval/run.sh)' : false);
}
