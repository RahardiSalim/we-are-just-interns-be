import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import 'features/trip/trip_screen.dart';
import 'services/api.dart';
import 'services/mock_listener.dart';
import 'services/recorder.dart';

// shortcut: only the local emulators exist so far (offline project demo-gosafe). Use real
// FirebaseOptions (flutterfire configure) and USE_EMULATORS=false once the Firebase project exists.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS', defaultValue: true);
// 10.0.2.2 is this Mac as seen from the Android emulator.
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1:android:1',
      messagingSenderId: '1',
      projectId: 'demo-gosafe',
    ),
  );
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
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  runApp(GoSafeApp(user: user));
}

class GoSafeApp extends StatelessWidget {
  const GoSafeApp({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return MaterialApp(
      title: 'GoSafe',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF00AA13)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00AA13),
        brightness: Brightness.dark,
      ),
      home: TripScreen(
        api: Api(token: () => user.getIdToken()),
        recorder: MicRecorder(),
        listen: scriptedListener,
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
        checkins: db
            .collection('checkins')
            .where('userId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'sent')
            .snapshots()
            .map((q) => [for (final d in q.docs) d.id]),
      ),
    );
  }
}
