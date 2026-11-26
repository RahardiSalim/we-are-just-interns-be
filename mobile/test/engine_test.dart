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
      final v = c.classify([
        'Mbak tinggal sendiri ya?',
        'Cantik banget, mampir ke tempat saya.',
      ]);
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

    test('each new uncomfortable remark is the next warning; the 3rd counts as high', () {
      final first = hear('Mbak udah punya pacar belum?');
      expect((first.action, first.nth), (SafetyAction.warn, 1));
      expect(
        hear('Oke Pak.').action,
        SafetyAction.none,
        reason: 'the same remark still in the window is not a repeat',
      );
      final second = hear('Tinggal sendiri ya?');
      expect((second.action, second.nth), (SafetyAction.warn, 2));
      final third = hear('Umur berapa sih?');
      expect((third.action, third.nth), (SafetyAction.high, 1));
    });

    test('harassment goes high, with the window as evidence, and counts each repeat', () {
      hear('Mbak tinggal sendiri ya?');
      final d = hear('Cantik banget, nanti mampir ke tempat saya.');
      expect((d.action, d.nth), (SafetyAction.high, 1));
      expect(d.verdict.label, Label.sexualHarassment);
      expect(d.window.map((l) => l.text), [
        'Mbak tinggal sendiri ya?',
        'Cantik banget, nanti mampir ke tempat saya.',
      ]);
      expect(
        d.window.first.start,
        0,
        reason: 'times are seconds from the window start',
      );
      expect(d.window.last.start, 5);

      expect(
        hear('Oke Mbak.').action,
        SafetyAction.none,
        reason: 'no new remark',
      );
      final again = hear('Ayo cium dulu.');
      expect((again.action, again.nth), (SafetyAction.high, 2));
    });

    test('only the last 15 seconds count', () {
      hear(
        'Cantik banget sih.',
        after: Duration.zero,
      ); // a warning-level hit...
      final d = hear('Oke, sampai.', after: const Duration(seconds: 16));
      expect(
        d.verdict.label,
        Label.normal,
        reason: '...that has left the window',
      );
      expect(d.window.map((l) => l.text), ['Oke, sampai.']);
    });

    test('a threat below the high threshold only warns', () {
      final weak = SafetyEngine(
        classifier: KeywordClassifier(),
        clock: () => now,
        highAt: 0.99,
      );
      expect(weak.hear('Awas kamu.').action, SafetyAction.warn);
    });
  });

  test('keywords still match with Indonesian suffixes (-nya, -mu, -ku)', () {
    final c = KeywordClassifier();
    expect(c.classify(['Buka bajunya dong.']).label, Label.sexualHarassment);
    expect(c.classify(['Saya tahu rumahmu.']).label, Label.threat);
    expect(c.classify(['Sayangnya hujan.']).label, Label.normal);
    expect(
      c.classify(['Sayang, kamu mau ke mana?']).label,
      Label.uncomfortable,
    );
  });

  test(
    'swearing is uncomfortable, slurs are harassment, neither is high alone',
    () {
      final c = KeywordClassifier();
      expect(c.classify(['Anjing lu, bangsat!']).label, Label.uncomfortable);
      expect(c.classify(['Dasar perempuan bodoh.']).label, Label.uncomfortable);
      expect(c.classify(['Fuck you, Pak.']).label, Label.uncomfortable);
      expect(
        c.classify(['Anjir, macet banget.']).label,
        Label.normal,
        reason: 'swearing at the traffic, not at anyone',
      );
      expect(
        c.classify(['Bos gue bangsat banget.']).label,
        Label.normal,
        reason: 'about a third person',
      );
      expect(c.classify(['Dasar lonte.']).label, Label.sexualHarassment);
      expect(
        c.classify(['Anjingnya lucu banget.']).label,
        Label.normal,
        reason: 'the pet, not the insult',
      );
      final e = SafetyEngine(classifier: c);
      expect(
        e.hear('Anjing! Bangsat! Bajingan! Goblok!').action,
        isNot(SafetyAction.high),
        reason: 'anger alone never sends a high flag',
      );
    },
  );

  test('threat words with Indonesian prefixes and in English', () {
    final c = KeywordClassifier();
    for (final line in [
      'saya akan membunuh kamu',
      'nanti kamu dibunuh',
      'gue pukul lu',
      'saya memukul kamu',
      'gue hajar lu',
      'saya mutilasi kamu',
      'kalau enggak i will kill you',
      'gue habisin lu',
    ]) {
      expect(c.classify([line]).label, Label.threat, reason: line);
    }
  });
}
