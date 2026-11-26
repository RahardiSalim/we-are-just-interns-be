import 'classifier.dart';

/// Test rides built from the real recorded sentences in `stt/dialog_script.csv` (c01.wav … c24.wav).
/// Each line carries the label the model would give it (the CSV's `label` column for the person
/// causing trouble; the other person's replies are normal). [ScenarioClassifier] plays that label
/// back, so the real engine, screen, storage and uploads run as if the model had said it.
///
/// Pick one in the app with `--dart-define=DEMO_SCRIPT=<name>`, in the browser preview with
/// `?scenario=<name>`. The widget tests in `test/scenario_test.dart` run every one.
class RideScenario {
  const RideScenario(this.name, this.title, this.lines);

  final String name;
  final String title;
  final List<(String text, Label label)> lines;
}

const _n = Label.normal;
const _u = Label.uncomfortable;
const _sh = Label.sexualHarassment;

// The sentences, by their recording in stt/dialog_script.csv.
const _c01 = 'Selamat siang mbak, tujuannya ke Stasiun Tebet ya?';
const _c02 = 'Iya pak, lewat jalan biasa aja nggak apa-apa.';
const _c03 = 'Macet banget hari ini, saya lewat gang aja ya biar cepat.';
const _c04 = 'Boleh pak, tolong pelan-pelan aja soalnya saya bawa laptop.';
const _c05 = 'Udah sampai ya mbak, makasih ya, hati-hati.';
const _c06 = 'Makasih banyak pak, saya kasih bintang lima.';
const _c07 = 'Mbak cantik banget hari ini, mau ke mana sih?';
const _c08 = 'Mau ke kantor pak, tolong fokus ke jalan aja ya.';
const _c09 = 'Udah punya pacar belum mbak? Kok sendirian terus.';
const _c10 = 'Bapak nggak perlu tanya yang pribadi ya.';
const _c11 = 'Boleh minta nomor WhatsApp mbak? Biar gampang kalau mau ngobrol.';
const _c12 = 'Maaf pak, saya nggak kasih nomor saya.';
const _c13 = 'Badan mbak bagus banget ya, kayak model.';
const _c14 = 'Pak, tolong jangan ngomong kayak gitu, saya nggak nyaman.';
const _c15 = 'Ah jangan sok jual mahal mbak, aku cuma muji kok.';
const _c16 = 'Berhenti ngomong begitu, saya mau turun sekarang.';
const _c17 = 'Duduknya geser dekat sini aja, biar nggak dingin.';
const _c18 = 'Nggak usah pak, saya duduk di sini aja.';

const scenarios = [
  RideScenario('none', 'Nothing happens', [
    (_c01, _n),
    (_c02, _n),
    (_c03, _n),
    (_c04, _n),
    (_c05, _n),
    (_c06, _n),
  ]),
  RideScenario('warning1', 'Warning once', [
    (_c01, _n),
    (_c02, _n),
    (_c07, _u),
    (_c08, _n),
    (_c05, _n),
    (_c06, _n),
  ]),
  RideScenario('warning2', 'Warning twice', [
    (_c01, _n),
    (_c07, _u),
    (_c08, _n),
    (_c09, _u),
    (_c10, _n),
    (_c05, _n),
  ]),
  RideScenario('warning3', 'Warning three times', [
    (_c07, _u),
    (_c08, _n),
    (_c09, _u),
    (_c10, _n),
    (_c11, _u),
    (_c12, _n),
  ]),
  RideScenario('high1', 'High flag once', [
    (_c01, _n),
    (_c02, _n),
    (_c13, _sh),
    (_c14, _n),
    (_c04, _n),
  ]),
  RideScenario('high2', 'High flag twice', [
    (_c01, _n),
    (_c13, _sh),
    (_c14, _n),
    (_c15, _sh),
    (_c16, _n),
  ]),
  RideScenario('high3', 'High flag three times', [
    (_c13, _sh),
    (_c14, _n),
    (_c15, _sh),
    (_c16, _n),
    (_c17, _sh),
    (_c18, _n),
  ]),
];

RideScenario? scenarioNamed(String name) {
  for (final s in scenarios) {
    if (s.name == name) return s;
  }
  return null;
}

/// Stands in for the model during a [RideScenario]: each known line gets its scripted label, with
/// a score above the warning threshold (uncomfortable) or the high threshold (harassment, threat).
/// The window's label is the most severe one in it, as the real classifier does.
class ScenarioClassifier implements Classifier {
  ScenarioClassifier(RideScenario scenario)
    : _labels = {for (final (t, l) in scenario.lines) t: l};

  final Map<String, Label> _labels;

  static const _score = {
    Label.normal: 0.5,
    Label.uncomfortable: 0.7,
    Label.sexualHarassment: 0.9,
    Label.threat: 0.9,
  };

  @override
  Verdict classify(List<String> lines) {
    final labels = [for (final l in lines) _labels[l] ?? Label.normal];
    // Most severe first, as KeywordClassifier orders them.
    const order = [Label.threat, Label.sexualHarassment, Label.uncomfortable];
    final label = order.firstWhere(labels.contains, orElse: () => Label.normal);
    return Verdict(label, _score[label]!, [
      for (final l in labels) l != Label.normal,
    ]);
  }
}
