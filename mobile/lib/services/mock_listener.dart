/// Stand-in for microphone + VAD + Whisper: replays a scripted trip conversation,
/// one finished utterance at a time.
///
/// shortcut: replace with the sherpa_onnx listener (Silero VAD + Whisper) behind the same
/// `Stream<String> Function()` shape; nothing else in the app changes.
const demoConversation = [
  'Selamat sore Mbak, sesuai aplikasi ya, ke Senayan.',
  'Iya Pak, lewat Sudirman aja.',
  'Mbak kerja di mana? Udah punya pacar belum?',
  'Hmm, Pak, fokus nyetir aja ya.',
  'Tinggal sendiri ya? Rumahnya di mana?',
  'Cantik banget sih, nanti mampir ke tempat saya dulu.',
  'Pak, saya mau turun di depan aja.',
];

/// For demoing the hands-free SOS (`--dart-define=DEMO_SCRIPT=safe_phrase`): nothing rude is said,
/// the rider just says the safe phrase, and a silent SOS goes out.
const safePhraseConversation = [
  'Selamat malam Mbak, sesuai aplikasi ya.',
  'Iya Pak.',
  'Mbak, rumahnya sendirian ya? Nanti saya antar sampai dalam.',
  'Pak, nanti lewat jalan biasa aja ya.',
  'Iya Mbak.',
];

Stream<String> scriptedListener({
  List<String> lines = demoConversation,
  Duration gap = const Duration(seconds: 3),
}) async* {
  for (final line in lines) {
    await Future<void>.delayed(gap);
    yield line;
  }
}
