import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/classifier.dart';
import 'package:gosafe/services/dev_ml.dart';
import 'package:gosafe/services/edge_ai.dart';

ModelClassifier withModel(Map<String, (String, double)> answers) =>
    ModelClassifier((_) async => ('normal', 0.5))..raw.addAll(answers);

void main() {
  test(
    'two confident threat lines in the window raise threat on the model alone',
    () {
      final c = withModel({
        'kamu jangan macam-macam gitu ya': ('threat', 0.97),
        'saya mutilasi kamu': ('threat', 0.99),
      });
      expect(
        c.classify(['kamu jangan macam-macam gitu ya']).label,
        Label.uncomfortable,
        reason: 'one line only warns',
      );
      final v = c.classify([
        'kamu jangan macam-macam gitu ya',
        'saya mutilasi kamu',
      ]);
      expect((v.label, v.score), (Label.threat, 0.99));
    },
  );

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

  test(
    'the 5-label model maps onto the app labels; victim speech alone never warns',
    () {
      final c = withModel({
        'Lu jangan macem-macem.': ('threat', 0.97),
        'Pak, itu bukan urusan bapak.': ('victim', 0.95),
      });
      expect(
        c.classify(['Lu jangan macem-macem.']).label,
        Label.uncomfortable,
        reason: 'the model alone still only warns',
      );
      expect(
        c.classify(['Pak, itu bukan urusan bapak.']).label,
        Label.normal,
        reason: 'a refusal is no offence: the model misreads plain questions as victim',
      );
    },
  );

  test('the phone model\'s logits become the top label and its probability', () {
    final (label, p) = EdgeAi.best([0.0, 2.0, 0.0], ['normal', 'threat', 'victim']);
    expect(label, 'threat');
    expect(p, closeTo(0.787, 0.001)); // e^2 / (1 + e^2 + 1)
  });
}
