import 'dart:io' show Directory;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/safe_phrase.dart';
import 'features/safety/are_you_ok.dart' show SafetyText;
import 'features/trip/trip_screen.dart';
import 'engine/safety_engine.dart';
import 'services/api.dart';
import 'services/dev_ml.dart';
import 'services/mock_listener.dart';
import 'services/file_ride_store.dart';
import 'services/recorder.dart';
import 'services/ride.dart';
import 'services/ride_store.dart';
import 'theme.dart';

// Defaults are the offline emulator project (demo-gosafe). For a real Firebase project pass
// USE_EMULATORS=false and FIREBASE_API_KEY / FIREBASE_APP_ID / FIREBASE_PROJECT_ID / FIREBASE_SENDER_ID
// (Firebase console > Project settings > Your apps > the Android app). These are public client
// settings, not secrets.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS', defaultValue: true);
const _firebaseOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'demo-key'),
  appId: String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:1:android:1'),
  messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '1'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'demo-gosafe'),
);
// 10.0.2.2 is this Mac as seen from the Android emulator.
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST');
const _devMlUrl = String.fromEnvironment('DEV_ML');
final _devMl = _devMlUrl.isEmpty ? null : DevClassifier(Uri.parse(_devMlUrl));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: _firebaseOptions);
  final auth = FirebaseAuth.instance;
  if (_useEmulators) {
    final host = _emulatorHost.isNotEmpty
        ? _emulatorHost
        : (kIsWeb ? '127.0.0.1' : '10.0.2.2');
    await auth.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
  // No login screen for the hackathon: each install gets an anonymous account, so the backend
  // still knows whose ride and report it is. In production the GoJek app's own login replaces this.
  // A login restored from an earlier run refreshes its token against Google, not the emulator,
  // and fails after an hour. Anonymous accounts are throwaway here, so start fresh each launch.
  if (_useEmulators) await auth.signOut();
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  // Rides live in the app's private folder, every file encrypted. The web preview keeps them in memory.
  final RideStore store = kIsWeb
      ? MemoryRideStore()
      : FileRideStore(
          Directory('${(await getApplicationSupportDirectory()).path}/rides'),
          seal: Ride.seal,
          open: Ride.open,
        );
  runApp(GoSafeApp(user: user, store: store));
}

class GoSafeApp extends StatelessWidget {
  const GoSafeApp({super.key, required this.user, required this.store});

  final User user;
  final RideStore store;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final dev = _devMl;
    return MaterialApp(
      title: 'GoSafe',
      // Plus Jakarta Sans stands in for Asphalt's Maison Neue (licensed); see contracts/DESIGN.md.
      theme: goSafeTheme(
        Brightness.light,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      ),
      darkTheme: goSafeTheme(
        Brightness.dark,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      ),
      home: TripScreen(
        api: Api(token: () => user.getIdToken()),
        recorder: MicRecorder(store),
        store: store,
        // DEV_ML: the real mic through the laptop's Whisper and classifier (stt/dev_server.py).
        listen: dev == null
            ? () => scriptedListener(
                lines:
                    const String.fromEnvironment('DEMO_SCRIPT') == 'safe_phrase'
                    ? safePhraseConversation
                    : demoConversation,
              )
            : () => devListener(dev.server, dev),
        engine: dev == null ? null : () => SafetyEngine(classifier: dev),
        describe: dev == null
            ? null
            : (line) => switch (dev.raw[line]) {
                (final label, final p) => '$label ${p.toStringAsFixed(2)}',
                null => null,
              },
        // shortcut: one phrase for everyone; let each rider pick theirs in settings later.
        safePhrase: const SafePhrase(
          String.fromEnvironment(
            'SAFE_PHRASE',
            defaultValue: 'Pak, nanti lewat jalan biasa aja ya',
          ),
        ),
        tripInfo: (id) async {
          final consent =
              (await db.doc('trips/$id').get()).data()?['consent'] as Map?;
          return consent == null
              ? null
              : (
                  riderConsent: consent['rider'] == true,
                  driverConsent: consent['driver'] == true,
                );
        },
        // Lock-screen alerts are Android-only; the web preview shows the dialog alone.
        alert: kIsWeb
            ? null
            : ({required loud}) => Ride.alert(
                SafetyText.askTitle,
                SafetyText.askAlertBody,
                loud: loud,
              ),
        clearAlert: kIsWeb ? null : Ride.clearAlert,
        dial: kIsWeb ? null : Ride.dial,
      ),
    );
  }
}
