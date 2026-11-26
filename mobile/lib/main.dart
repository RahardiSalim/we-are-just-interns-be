import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import 'features/auth/login_screen.dart';
import 'features/trip/trip_screen.dart';
import 'services/api.dart';
import 'services/mock_listener.dart';

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
  if (_useEmulators) {
    final host = _emulatorHost.isNotEmpty ? _emulatorHost : (kIsWeb ? '127.0.0.1' : '10.0.2.2');
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
  runApp(const GoSafeApp());
}

class GoSafeApp extends StatelessWidget {
  const GoSafeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GoSafe',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF00AA13)),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF00AA13), brightness: Brightness.dark),
        home: const _AuthGate(),
      );
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return LoginScreen(signIn: (email, pw) => auth.signInWithEmailAndPassword(email: email, password: pw));
        }
        return FutureBuilder(
          future: user.getIdTokenResult(),
          builder: (context, token) {
            final role = token.data?.claims?['role'];
            if (role == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (role != 'rider' && role != 'driver') {
              auth.signOut();
              return const SizedBox.shrink();
            }
            final db = FirebaseFirestore.instance;
            return TripScreen(
              api: Api(token: () => user.getIdToken()),
              role: role as String,
              listen: scriptedListener,
              tripInfo: (id) async {
                final trip = (await db.doc('trips/$id').get()).data();
                if (trip == null) return null;
                final consent = trip['consent'] as Map;
                return (mode: trip['mode'] as String, bothConsented: consent['rider'] == true && consent['driver'] == true);
              },
              checkins: db
                  .collection('checkins')
                  .where('userId', isEqualTo: user.uid)
                  .where('status', isEqualTo: 'sent')
                  .snapshots()
                  .map((q) => [for (final d in q.docs) d.id]),
              onSignOut: auth.signOut,
            );
          },
        );
      },
    );
  }
}
