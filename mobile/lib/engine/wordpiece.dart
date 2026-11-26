/// BERT's WordPiece tokenizer (lower case), as the classifier was trained with: text in, token ids out.
/// Same steps as Hugging Face's BertTokenizer: clean, split on spaces and punctuation, then longest
/// vocabulary pieces first, continuing pieces marked "##". Checked against it in test/wordpiece_test.dart.
class WordPiece {
  WordPiece(List<String> vocab) : _ids = {for (var i = 0; i < vocab.length; i++) vocab[i]: i};

  final Map<String, int> _ids;
  int get _unk => _ids['[UNK]']!;

  /// [CLS] pieces [SEP], at most [maxLen] ids.
  List<int> encode(String text, {int maxLen = 64}) {
    final ids = [for (final w in _words(text)) ..._pieces(w)];
    return [_ids['[CLS]']!, ...ids.take(maxLen - 2), _ids['[SEP]']!];
  }

  Iterable<String> _words(String text) sync* {
    final buf = StringBuffer();
    Iterable<String> flush() sync* {
      if (buf.isNotEmpty) yield buf.toString();
      buf.clear();
    }

    for (final r in text.toLowerCase().runes) {
      if (r == 0 || r == 0xFFFD || _control(r)) continue;
      final c = String.fromCharCode(r);
      if (_space.hasMatch(c)) {
        yield* flush();
      } else if (_punct(r) || _cjk(r)) {
        yield* flush();
        yield c;
      } else {
        buf.write(_plain[c] ?? c);
      }
    }
    yield* flush();
  }

  List<int> _pieces(String word) {
    if (word.runes.length > 100) return [_unk];
    final out = <int>[];
    var start = 0;
    while (start < word.length) {
      var end = word.length;
      int? id;
      while (start < end) {
        id = _ids[start > 0 ? '##${word.substring(start, end)}' : word.substring(start, end)];
        if (id != null) break;
        end--;
        // Never split a surrogate pair (emoji): Python counts code points.
        if (end > start && _lowSurrogate(word.codeUnitAt(end))) end--;
      }
      if (id == null) return [_unk];
      out.add(id);
      start = end;
    }
    return out;
  }

  static final _space = RegExp(r'\s');
  static final _unicodePunct = RegExp(r'\p{P}', unicode: true);
  static final _format = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

  static bool _control(int r) =>
      r != 9 && r != 10 && r != 13 && _format.hasMatch(String.fromCharCode(r));
  static bool _punct(int r) =>
      (r >= 33 && r <= 47) ||
      (r >= 58 && r <= 64) ||
      (r >= 91 && r <= 96) ||
      (r >= 123 && r <= 126) ||
      _unicodePunct.hasMatch(String.fromCharCode(r));
  static bool _cjk(int r) =>
      (r >= 0x4E00 && r <= 0x9FFF) ||
      (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x20000 && r <= 0x2A6DF) ||
      (r >= 0xF900 && r <= 0xFAFF);
  static bool _lowSurrogate(int u) => u >= 0xDC00 && u <= 0xDFFF;

  // shortcut: BertTokenizer strips every accent (Unicode NFD); Dart has no NFD, so only the Latin ones
  // Indonesian names and loanwords use. Add more if a parity case fails.
  static const _plain = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e',
    'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ö': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
  };
}
