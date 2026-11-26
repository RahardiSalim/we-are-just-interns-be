import 'dart:math' show min;

/// A natural-sounding sentence the rider chose that sends a silent SOS when heard, so help can
/// be called on a motorbike without touching the phone. No model: it matches the speech-to-text
/// output, allowing for small transcription slips ("aja" → "saja", "ya" → "yah", one word missed).
class SafePhrase {
  const SafePhrase(this.phrase);
  final String phrase;

  /// True when the line contains the phrase, give or take one word per six.
  bool heardIn(String line) {
    final p = _words(phrase);
    final w = _words(line);
    if (p.isEmpty || w.isEmpty) return false;
    // Word-level edit distance from the phrase to the best-matching stretch of the line
    // (free start and end in the line, so it can sit inside a longer sentence).
    var prev = List<int>.filled(w.length + 1, 0);
    for (var i = 1; i <= p.length; i++) {
      final cur = List<int>.filled(w.length + 1, i);
      for (var j = 1; j <= w.length; j++) {
        cur[j] = min(
          min(prev[j] + 1, cur[j - 1] + 1),
          prev[j - 1] + (_close(p[i - 1], w[j - 1]) ? 0 : 1),
        );
      }
      prev = cur;
    }
    return prev.reduce(min) <= p.length ~/ 6;
  }

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((x) => x.isNotEmpty)
      .toList();

  /// Same word, or one letter added, dropped or changed.
  static bool _close(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = [i, ...List<int>.filled(b.length, 0)];
      for (var j = 1; j <= b.length; j++) {
        cur[j] = min(
          min(prev[j] + 1, cur[j - 1] + 1),
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
      prev = cur;
    }
    return prev[b.length] <= 1;
  }
}
