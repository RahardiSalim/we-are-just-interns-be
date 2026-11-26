import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/services/on_device_stt.dart';

void main() {
  const filter = SpeechFilter();

  test('keeps ordinary speech', () {
    expect(filter.clean('Mbak kerja di mana? Udah punya pacar belum?'), isNotNull);
    expect(
      filter.clean('maksud gua hp itu tempat buat insert ini loh dia bukan bukan app kayak gitu dia kayak gini kayak gini'),
      isNotNull,
    );
  });

  test('drops what Whisper invents on silence', () {
    expect(filter.clean('terima kasih telah menonton video ini dan jangan lupa like dan subscribe'), isNull);
    expect(filter.clean('[BLANK_AUDIO]'), isNull);
    expect(filter.clean('   '), isNull);
  });

  test('keeps the real speech before an invented outro', () {
    expect(filter.clean('Pak, saya mau turun di sini, jangan lupa subscribe'), 'Pak, saya mau turun di sini');
  });

  test('drops loops seen on the emulator microphone', () {
    expect(filter.clean('ayo ayo kita tidur kita tidur kita tidur kita tidur'), isNull);
    expect(filter.clean('hai hai hai hai hai hai hai hai kembali saya hai hai hai hai hai hai hai tengan dihidil dihidil'), isNull);
  });

  test('never drops a shout for help, even repeated', () {
    expect(filter.clean('tolong tolong tolong tolong tolong tolong'), isNotNull);
  });
}
