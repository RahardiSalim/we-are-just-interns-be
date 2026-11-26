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
  const Decision(this.action, this.verdict, this.window);
  final SafetyAction action;
  final Verdict verdict;
  final List<Line> window; // the evidence: the last 30 s of transcript
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
    this.window = const Duration(seconds: 30),
    this.warnCooldown = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  final Classifier classifier;
  final double warnAt, highAt;
  final Duration window, warnCooldown;
  final DateTime Function() _clock;

  final _heard = <(DateTime, String)>[];
  DateTime? _lastWarning;
  bool _reported = false;

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
    return Decision(_decide(verdict, now), verdict, lines);
  }

  SafetyAction _decide(Verdict v, DateTime now) {
    if (_reported) {
      return SafetyAction
          .none; // one automatic report per trip; the case is with an agent
    }
    if (_harmful.contains(v.label) && v.score >= highAt) {
      _reported = true;
      return SafetyAction.high;
    }
    final cooling =
        _lastWarning != null && now.difference(_lastWarning!) < warnCooldown;
    if (v.label != Label.normal && v.score >= warnAt && !cooling) {
      _lastWarning = now;
      return SafetyAction.warn;
    }
    return SafetyAction.none;
  }
}
