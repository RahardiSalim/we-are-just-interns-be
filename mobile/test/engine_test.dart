import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safety_engine.dart';

void main() {
  late DateTime now;
  late SafetyEngine engine;

  setUp(() {
    now = DateTime.utc(2026, 11, 26, 12);
    engine = SafetyEngine(classifier: KeywordClassifier(), clock: () => now);
  });

  Decision hear(String text, {Duration after = const Duration(seconds: 5)}) {
    now = now.add(after);
    return engine.hear(text);
  }

  group('keyword classifier', () {
    final c = KeywordClassifier();

    test('labels by the most severe line and flags matching lines', () {
      final v = c.classify(['Mbak tinggal sendiri ya?', 'Cantik banget, mampir ke tempat saya.']);
      expect(v.label, Label.sexualHarassment);
      expect(v.flagged, [true, true]);
      expect(v.score, closeTo(0.8, 1e-9), reason: 'two harassment phrases');
    });

    test('ordinary talk is normal', () {
      final v = c.classify(['Lewat Sudirman aja ya Pak', 'Siap, Mbak']);
      expect(v.label, Label.normal);
      expect(v.flagged, [false, false]);
    });
  });

  group('safety engine', () {
    test('ordinary talk does nothing', () {
      expect(hear('Lewat Sudirman aja ya Pak').action, SafetyAction.none);
    });

    test('an uncomfortable remark warns once, then waits out the cooldown', () {
      expect(hear('Mbak udah punya pacar belum?').action, SafetyAction.warn);
      expect(hear('Tinggal sendiri ya?').action, SafetyAction.none, reason: 'within 10 minutes');
      // 10 minutes later the old line has left the 30 s window, so a new remark is needed
      expect(hear('Umur berapa sih?', after: const Duration(minutes: 10)).action, SafetyAction.warn);
    });

    test('harassment goes high once per trip, with the window as evidence', () {
      hear('Mbak tinggal sendiri ya?');
      final d = hear('Cantik banget, nanti mampir ke tempat saya.');
      expect(d.action, SafetyAction.high);
      expect(d.verdict.label, Label.sexualHarassment);
      expect(d.window.map((l) => l.text), ['Mbak tinggal sendiri ya?', 'Cantik banget, nanti mampir ke tempat saya.']);
      expect(d.window.first.start, 0, reason: 'times are seconds from the window start');
      expect(d.window.last.start, 5);

      expect(hear('Ayo cium dulu.').action, SafetyAction.none, reason: 'the case is already with customer service');
    });

    test('only the last 30 seconds count', () {
      hear('Cantik banget sih.', after: Duration.zero); // a warning-level hit...
      final d = hear('Oke, sampai.', after: const Duration(seconds: 31));
      expect(d.verdict.label, Label.normal, reason: '...that has left the window');
      expect(d.window.map((l) => l.text), ['Oke, sampai.']);
    });

    test('a threat below the high threshold only warns', () {
      final weak = SafetyEngine(classifier: KeywordClassifier(), clock: () => now, highAt: 0.99);
      expect(weak.hear('Awas kamu.').action, SafetyAction.warn);
    });
  });
}
