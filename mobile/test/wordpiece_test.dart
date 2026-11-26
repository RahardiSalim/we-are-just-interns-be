import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/wordpiece.dart';

void main() {
  // The fixture is what the model's own Python tokenizer (BertTokenizer) gives for each text.
  test('the Dart tokenizer gives the same ids as the Python one', () {
    final tok = WordPiece(File('assets/models/vocab.txt').readAsLinesSync());
    final cases = (jsonDecode(
      File('test/fixtures/tokenizer_parity.json').readAsStringSync(),
    ) as List).cast<Map>();
    for (final c in cases) {
      expect(tok.encode(c['text'] as String), c['ids'], reason: c['text'] as String);
    }
  });
}
