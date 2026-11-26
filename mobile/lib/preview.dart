import 'dart:typed_data';

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'engine/safety_engine.dart';
import 'engine/scenarios.dart';
import 'features/trip/trip_screen.dart';
import 'services/api.dart';
import 'services/mock_listener.dart';
import 'services/recorder.dart';
import 'services/ride_store.dart';
import 'theme.dart';

/// Design preview: the app with no Firebase or backend (the microphone is real), for checking the look in a
/// browser. `flutter run -d chrome -t lib/preview.dart`. Nothing leaves the page.
final store = MemoryRideStore();
final _scenario = scenarioNamed(Uri.base.queryParameters['scenario'] ?? '');

void main() => runApp(
  MaterialApp(
    title: 'GoSafe preview',
    debugShowCheckedModeBanner: false,
    theme: goSafeTheme(
      Brightness.light,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    ),
    home: TripScreen(
      api: _PreviewApi(),
      // The real microphone, so the sound signal moves with real voices. The recording stays in
      // this page's memory.
      recorder: MicRecorder(store),
      store: store,
      autoStart: true,
      // A calm ride, so the signal moves without raising any alarm.
      // ?scenario=warning2 (none, warning1-3, high1-3) plays a test ride from
      // lib/engine/scenarios.dart; without it, a calm ride.
      listen: () => scriptedListener(
        lines: _scenario == null
            ? const [
                'Selamat sore Mbak.',
                'Lewat Sudirman ya Mbak?',
                'Iya Pak, boleh.',
              ]
            : [for (final (t, _) in _scenario!.lines) t],
      ),
      engine: _scenario == null
          ? null
          : () => SafetyEngine(classifier: ScenarioClassifier(_scenario!)),
      tripInfo: (_) async => (riderConsent: true, driverConsent: true),
    ),
  ),
);

class _PreviewApi extends Api {
  _PreviewApi()
    : super(token: () async => 'preview', baseUrl: 'http://preview');

  @override
  Future<bool> health() async => true;
  @override
  Future<String> startTrip({
    bool riderConsent = false,
    String role = 'rider',
    String? orderId,
  }) async => 'GR-PREVIEW';
  @override
  Future<void> setSafeRide(bool on) async {}
  @override
  Future<void> endTrip(String tripId) async {}
  @override
  Future<String> report(
    String tripId,
    String trigger,
    Decision? evidence,
  ) async => 'preview';
  @override
  Future<void> saveRecording(
    RideMeta ride, {
    required int pieces,
    required bool live,
    required bool done,
  }) async {}
  @override
  Future<void> uploadPiece(
    String tripId,
    int n,
    String contentType,
    Uint8List bytes,
  ) async {}
}
