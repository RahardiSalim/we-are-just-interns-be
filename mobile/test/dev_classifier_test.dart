import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/classifier.dart';
import 'package:gosafe/services/dev_ml.dart';

DevClassifier withModel(Map<String, (String, double)> answers) =>
    DevClassifier(Uri.parse('http://x'))..raw.addAll(answers);

void main() {
  test('the model alone can only warn, and only when very sure', () {
    final c = withModel({
      'Kamu cantik.': ('APPEARANCE_SEXUAL', 0.95),
      'Selamat pagi.': ('INTIMIDATION', 0.85), // a false alarm below 0.9
    });
    expect(c.classify(['Kamu cantik.']).label, Label.uncomfortable);
    expect(c.classify(['Selamat pagi.']).label, Label.normal);
  });

  test('the keywords decide where the model misses', () {
    final c = withModel({'Buka bajunya dong.': ('LOGISTICS', 0.98)});
    final v = c.classify(['Buka bajunya dong.']);
    expect(v.label, Label.sexualHarassment);
    expect(v.flagged, [true]);
  });

  test('agreement takes the higher score, which can make it high', () {
    const line = 'Mbak, buka baju dong.';
    final alone = withModel({}).classify([line]).score;
    final agreed = withModel({line: ('SEXUAL_EXPLICIT', 0.93)})
        .classify([line]);
    expect(agreed.label, Label.sexualHarassment);
    expect(agreed.score, greaterThan(alone));
    expect(agreed.score, 0.93);
  });

  test('a window takes its most severe line', () {
    final c = withModel({'Minta nomor WA-nya.': ('CONTACT_SOLICIT', 0.99)});
    final v = c.classify(['Halo Pak.', 'Minta nomor WA-nya.']);
    expect(v.label, Label.uncomfortable);
    expect(v.flagged, [false, true]);
  });
}
