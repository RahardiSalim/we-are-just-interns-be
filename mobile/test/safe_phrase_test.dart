import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safe_phrase.dart';

void main() {
  const phrase = SafePhrase('Pak, nanti lewat jalan biasa aja ya');

  test('hears the phrase the way speech-to-text writes it', () {
    for (final heard in [
      'Pak, nanti lewat jalan biasa aja ya.',
      'pak nanti lewat jalan biasa aja ya',
      'Pak nanti lewat jalan biasa saja ya', // aja → saja
      'Pak, nanti lewat jalan biasa aja yah', // ya → yah
      'Oh iya, Pak, nanti lewat jalan biasa aja ya, saya buru-buru.', // inside a longer line
      'Pak nanti lewat jalan biasa aja', // last word missed
    ]) {
      expect(phrase.heardIn(heard), isTrue, reason: heard);
    }
  });

  test('ignores ordinary talk that shares words with it', () {
    for (final heard in [
      'Iya Pak, lewat Sudirman aja.',
      'Jalan biasa macet nggak, Pak?',
      'Nanti lewat tol aja ya Pak.',
      'Pak, nanti belok kiri di depan ya.',
      '',
    ]) {
      expect(phrase.heardIn(heard), isFalse, reason: heard);
    }
  });
}
