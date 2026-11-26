import 'classifier.dart';

export 'classifier.dart';

enum SafetyAction { none, warn, high }

/// One transcript line as the API wants it: seconds from the window start.
class Line {
  const Line(this.start, this.end, this.text, {this.flagged = false});
  final double start;
  final double end;
  final String text;
  final bool flagged;

  Map<String, Object> toJson() => {'start': start, 'end': end, 'text': text};
}

/// A moment in the ride recording an agent should check.
class Marker {
  const Marker(this.at, this.kind, {this.verdict, this.text});
  final Duration at; // from the start of the recording
  final String kind; // warning | high | sos | manual_unsafe
  final Verdict? verdict;
  final String? text;

  Map<String, Object?> toJson() => {
    'at': at.inMilliseconds / 1000,
    'kind': kind,
    if (verdict != null) 'label': verdict!.label.api,
    if (verdict != null) 'score': verdict!.score,
    'text': ?text,
  };
}

class Decision {
  const Decision(this.action, this.verdict, this.window, {this.nth = 0});
  final SafetyAction action;
  final Verdict verdict;
  final List<Line> window; // the evidence: the last 15 s of transcript

  /// Which time this is on the ride: the 1st, 2nd, 3rd warning (or high flag). Each step does more;
  /// see "The ladder" in mobile/README.md.
  final int nth;
}

/// The phone's judgement: transcript in, warn / high / nothing out.
/// See contracts/ARCHITECTURE.md "On-device listening".
class SafetyEngine {
  SafetyEngine({
    required this.classifier,
    DateTime Function()? clock,
    // shortcut: placeholder thresholds; the modelling team sets the real ones from their test set.
    this.warnAt = 0.6,
    this.highAt = 0.8,
    this.window = const Duration(seconds: 15),
    this.warningsToHigh = 3,
  }) : _clock = clock ?? DateTime.now;

  final Classifier classifier;
  final double warnAt, highAt;
  final Duration window;

  /// The warning that counts as a high flag: repeated discomfort is serious on its own.
  final int warningsToHigh;
  final DateTime Function() _clock;

  final _heard = <(DateTime, String)>[];
  int _warnings = 0;
  int _highs = 0;

  static const _harmful = {Label.threat, Label.sexualHarassment};

  /// Feed one finished utterance (what speech-to-text produced).
  Decision hear(String text, {Duration length = const Duration(seconds: 4)}) {
    final now = _clock();
    _heard
      ..add((now, text))
      ..removeWhere((h) => now.difference(h.$1) > window);

    final verdict = classifier.classify([for (final h in _heard) h.$2]);
    final t0 = _heard.first.$1;
    final lines = [
      for (final (i, h) in _heard.indexed)
        Line(
          h.$1.difference(t0).inMilliseconds / 1000,
          h.$1.difference(t0).inMilliseconds / 1000 +
              length.inMilliseconds / 1000,
          h.$2,
          flagged: verdict.flagged[i],
        ),
    ];
    final action = _decide(verdict);
    return Decision(
      action,
      verdict,
      lines,
      nth: switch (action) {
        SafetyAction.warn => _warnings,
        SafetyAction.high => _highs,
        SafetyAction.none => 0,
      },
    );
  }

  /// The safe phrase was heard in the line [heard] judged: the person is telling us they're in danger,
  /// so that line is a high flag whatever the classifier said (`threat`, score 1.0). It counts on the
  /// ladder like any high flag: a later one is the 2nd, the one after that the 3rd.
  Decision safePhrase(Decision heard) {
    if (heard.action == SafetyAction.high) return heard; // already counted
    if (heard.action == SafetyAction.warn) _warnings--; // the same line: count it once, as high
    _highs++;
    final w = heard.window;
    return Decision(
      SafetyAction.high,
      Verdict(Label.threat, 1.0, [
        for (final (i, f) in heard.verdict.flagged.indexed) i == w.length - 1 || f,
      ]),
      [
        for (final (i, l) in w.indexed)
          Line(l.start, l.end, l.text, flagged: i == w.length - 1 || l.flagged),
      ],
      nth: _highs,
    );
  }

  SafetyAction _decide(Verdict v) {
    // Only a new offending line counts: the same remark staying in the 15 s window isn't a repeat.
    if (v.flagged.isEmpty || !v.flagged.last) return SafetyAction.none;
    if (_harmful.contains(v.label) && v.score >= highAt) {
      _highs++;
      return SafetyAction.high;
    }
    if (v.label != Label.normal && v.score >= warnAt) {
      _warnings++;
      if (_warnings >= warningsToHigh) {
        _highs++;
        return SafetyAction.high;
      }
      return SafetyAction.warn;
    }
    return SafetyAction.none;
  }
}
