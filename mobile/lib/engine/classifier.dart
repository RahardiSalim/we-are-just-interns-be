/// Stand-in for the on-device IndoBERT classifier: an Indonesian keyword filter.
///
/// shortcut: swap for IndoBERT (ONNX) when the modelling team ships it; keep the
/// `Classifier` interface so nothing else changes. Same lexicon as the backend's
/// `app/services/classify.py`.
enum Label { normal, uncomfortable, sexualHarassment, threat }

extension LabelApi on Label {
  /// The value the API and Firestore use.
  String get api => switch (this) {
    Label.normal => 'normal',
    Label.uncomfortable => 'uncomfortable',
    Label.sexualHarassment => 'sexual_harassment',
    Label.threat => 'threat',
  };
}

class Verdict {
  const Verdict(this.label, this.score, this.flagged);
  final Label label;
  final double score;
  final List<bool> flagged; // one per input line
}

abstract interface class Classifier {
  Verdict classify(List<String> lines);
}

class KeywordClassifier implements Classifier {
  // Most severe first: a window takes the most severe label any line hits.
  static const _lexicon = {
    Label.threat: [
      'bunuh',
      'pukul',
      'hajar',
      'tusuk',
      'pisau',
      'culik',
      'awas kamu',
      'diem aja',
      'diam aja',
      'jangan banyak tanya',
      'tahu rumah',
      'tau rumah',
      'jangan lapor',
      'lapor-lapor',
      'turun sini',
    ],
    Label.sexualHarassment: [
      'cantik banget',
      'seksi',
      'bodinya',
      'pegang',
      'cium',
      'raba',
      'tidur bareng',
      'ke hotel',
      'mampir ke tempat',
      'tempat saya',
      'kamar saya',
      'buka baju',
      'telanjang',
      'bugil',
      // Slurs that call a woman a prostitute: harassment, not just swearing.
      'lonte',
      'perek',
      'pelacur',
      'jablay',
    ],
    Label.uncomfortable: [
      'tinggal sendiri',
      'sendirian',
      'punya pacar',
      'rumahnya di mana',
      'minta nomor',
      'nomor wa',
      'umur berapa',
      'sayang',
      // Swearing and insults: a kind warning, never a high flag on their own (anger isn't danger).
      'anjing',
      'anjir',
      'babi',
      'bangsat',
      'bajingan',
      'brengsek',
      'keparat',
      'kampret',
      'sialan',
      'setan',
      'tai',
      'tahi',
      'asu',
      'jancok',
      'jancuk',
      'ngentot',
      'entot',
      'kontol',
      'memek',
      'goblok',
      'goblog',
      'tolol',
      'bego',
      'bodoh',
      'idiot',
      'fuck',
      'fucking',
      'shit',
      'bitch',
      'bastard',
    ],
  };

  static const _noSuffix = {'sayang', 'anjing', 'babi', 'setan', 'tai', 'asu'};

  static final _patterns = {
    for (final e in _lexicon.entries)
      // Indonesian suffixes stay part of the word: "buka bajunya", "rumahmu", "pegangku". Not for
      // words where a suffix changes the meaning ("sayangnya" is "unfortunately").
      e.key: RegExp(
        r'\b(?:(?:' +
            e.value
                .where((w) => !_noSuffix.contains(w))
                .map(RegExp.escape)
                .join('|') +
            r')(?:nya|mu|ku)?' +
            [
              for (final w in e.value.where(_noSuffix.contains))
                '|${RegExp.escape(w)}',
            ].join() +
            r')\b',
      ),
  };

  @override
  Verdict classify(List<String> lines) {
    final hits = <Label, int>{};
    final flagged = [
      for (final line in lines)
        () {
          final text = line.toLowerCase();
          var any = false;
          for (final e in _patterns.entries) {
            final n = e.value
                .allMatches(text)
                .length; // phrases, not lines: two in one sentence is stronger
            if (n > 0) {
              hits[e.key] = (hits[e.key] ?? 0) + n;
              any = true;
            }
          }
          return any;
        }(),
    ];
    final label = _lexicon.keys.firstWhere(
      hits.containsKey,
      orElse: () => Label.normal,
    );
    final score = label == Label.normal
        ? 0.5
        : (0.5 + 0.15 * hits[label]!).clamp(0.0, 0.95);
    return Verdict(label, score, flagged);
  }
}
