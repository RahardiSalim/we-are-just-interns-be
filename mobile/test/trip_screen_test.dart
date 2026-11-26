import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safe_phrase.dart';
import 'package:gosafe/engine/safety_engine.dart';
import 'package:gosafe/features/safety/are_you_ok.dart';
import 'package:gosafe/features/trip/trip_screen.dart';
import 'package:gosafe/services/api.dart';
import 'package:gosafe/services/recorder.dart';
import 'package:gosafe/services/ride_store.dart';
import 'package:material_ui/material_ui.dart';

/// Records calls instead of hitting the backend.
class FakeApi extends Api {
  FakeApi() : super(token: () async => 't', baseUrl: 'http://fake');
  final calls = <String>[];
  final reports = <(String trigger, Decision? evidence)>[];
  final saves = <String>[]; // "pieces:live:done" per recording-details call
  final pieces = <int, Uint8List>{};
  RideMeta? lastSaved;
  int failReports = 0; // the next n reports fail, as with no internet
  int failUploads = 0;
  bool rideWaiting = true;

  @override
  Future<bool> health() async => true;
  @override
  Future<String> startTrip({
    bool riderConsent = false,
    String role = 'rider',
    String? orderId,
  }) async {
    if (role == 'driver') {
      calls.add('join');
      if (!rideWaiting) throw ApiException(404, 'No ride is waiting');
    } else {
      calls.add('start:$riderConsent');
    }
    return 'GR-TEST';
  }

  @override
  Future<void> setSafeRide(bool on) async => calls.add('safeRide:$on');
  @override
  Future<void> endTrip(String tripId) async => calls.add('end:$tripId');
  @override
  Future<String> report(
    String tripId,
    String trigger,
    Decision? evidence,
  ) async {
    if (failReports > 0) {
      failReports--;
      throw ApiException(0, 'offline');
    }
    reports.add((trigger, evidence));
    return 'inc-${reports.length}';
  }

  @override
  Future<void> saveRecording(
    RideMeta ride, {
    required int pieces,
    required bool live,
    required bool done,
  }) async {
    if (failUploads > 0) {
      failUploads--;
      throw ApiException(0, 'offline');
    }
    saves.add('$pieces:${live ? 'live' : '-'}:${done ? 'done' : '-'}');
    lastSaved = RideMeta.decode(ride.encode());
  }

  @override
  Future<void> uploadPiece(
    String tripId,
    int n,
    String contentType,
    Uint8List bytes,
  ) async => pieces[n] = bytes;

  List<String> get kinds => [
    for (final m in lastSaved!.markers) m['kind'] as String,
  ];
}

class FakeRecorder implements TripRecorder {
  FakeRecorder(this.store);
  final RideStore store;
  bool allowMic = true;
  bool live = false;
  String state = 'idle';

  @override
  String get contentType => 'audio/aac';

  @override
  Future<bool> start(String tripId) async {
    if (!allowMic) return false;
    state = 'recording';
    // Two pieces, as if 30 seconds had passed.
    await store.addPiece(tripId, 0, Uint8List.fromList([1, 2]));
    await store.addPiece(tripId, 1, Uint8List.fromList([3, 4]));
    return true;
  }

  @override
  void goLive() => live = true;

  @override
  Future<Duration> stop() async {
    state = 'stopped';
    return const Duration(seconds: 25);
  }
}

class Harness {
  final api = FakeApi();
  final store = MemoryRideStore();
  late final recorder = FakeRecorder(store);
  final heard = StreamController<String>();
  final alerts = <String>[];
  final dialed = <String>[];
  bool driverSafeRide = true;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TripScreen(
          api: api,
          recorder: recorder,
          store: store,
          listen: () => heard.stream,
          tripInfo: (_) async => (
            riderConsent: !api.calls.contains('start:false'),
            driverConsent: driverSafeRide,
          ),
          alert: ({required loud}) async => alerts.add(loud ? 'alarm' : 'buzz'),
          clearAlert: () async => alerts.add('clear'),
          dial: (number) async => dialed.add(number),
          safePhrase: const SafePhrase('Pak, nanti lewat jalan biasa aja ya'),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> startRide(WidgetTester tester, {bool consent = true}) async {
    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();
    expect(find.text(SafetyText.consentTitle), findsOneWidget);
    await tester.tap(
      find.text(consent ? SafetyText.consentYes : SafetyText.consentNo),
    );
    await tester.pumpAndSettle();
  }

  Future<void> say(WidgetTester tester, String text) async {
    heard.add(text);
    await tester.pump();
    await tester.pump();
  }

  Future<void> endRide(WidgetTester tester) async {
    await tester.tap(find.text('End ride'));
    await tester.pumpAndSettle();
  }
}

const uncomfortable = 'Mbak udah punya pacar belum?';
const harassment = 'Cantik banget sih, nanti mampir ke tempat saya dulu.';

void main() {
  testWidgets(
    'one tap: the rider agrees, the ride starts recording and listening',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);

      expect(h.api.calls, ['start:true']);
      expect(h.recorder.state, 'recording');
      expect(find.textContaining('Recording on'), findsOneWidget);
      expect(find.text('Your driver has Safe Ride on'), findsOneWidget);
      await h.say(tester, 'Selamat sore Mbak.');
      expect(find.text('Selamat sore Mbak.'), findsOneWidget);
    },
  );

  testWidgets('"Not now": no recording, no listening, but SOS still works', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester, consent: false);

    expect(h.api.calls, ['start:false']);
    expect(h.recorder.state, 'idle');
    expect(h.heard.hasListener, isFalse, reason: 'never opened');
    expect(find.textContaining('Not recording'), findsOneWidget);
    await tester.tap(find.text('SOS'));
    await tester.pump();
    expect(h.api.reports.single.$1, 'sos');
  });

  testWidgets('a driver without Safe Ride means no recording', (tester) async {
    final h = Harness()..driverSafeRide = false;
    await h.pump(tester);
    await h.startRide(tester);
    expect(h.recorder.state, 'idle');
    expect(find.text("Your driver hasn't turned on Safe Ride"), findsOneWidget);
  });

  testWidgets('microphone denied: told plainly, nothing recorded', (
    tester,
  ) async {
    final h = Harness()..recorder.allowMic = false;
    await h.pump(tester);
    await h.startRide(tester);
    expect(find.textContaining('Allow microphone access'), findsOneWidget);
    expect(h.heard.hasListener, isFalse);
  });

  testWidgets(
    'a warning, ignored: nothing leaves the phone, the flag is kept',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);
      expect(find.text(SafetyText.warning), findsOneWidget);
      expect(h.alerts, isEmpty, reason: 'a warning never buzzes');
      await h.endRide(tester);

      expect(h.api.reports, isEmpty);
      expect(h.api.saves, isEmpty, reason: 'no upload');
      final ride = (await h.store.rides()).single;
      expect(
        (ride.share, ride.ended, ride.markers.single['kind']),
        (Share.local, true, 'warning'),
      );
      expect(find.text(SafetyText.keptOnPhone), findsOneWidget);
    },
  );

  testWidgets(
    'a warning, reported: the case opens now, the whole ride goes at the end',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);
      await tester.tap(find.text(SafetyText.warningReport));
      await tester.pumpAndSettle();
      expect(h.api.reports.single.$1, 'manual_unsafe');
      expect(find.text("We've reported this driver"), findsOneWidget);
      await tester.tap(find.text(SafetyText.needHelpNo));
      await tester.pumpAndSettle();
      expect(find.text(SafetyText.reportThanks), findsOneWidget);
      expect(h.api.saves, isEmpty, reason: 'nothing streams for a report');

      await h.endRide(tester);
      expect(h.api.saves.last, '2:-:done');
      expect(h.api.pieces, {
        0: [1, 2],
        1: [3, 4],
      });
      expect(h.api.kinds, ['warning', 'manual_unsafe']);
      expect(find.text(SafetyText.recordingSent), findsOneWidget);
    },
  );

  testWidgets('a report that needs help becomes an SOS and goes live', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await tester.tap(
      find.text('Report driver'),
    ); // the button, no warning needed
    await tester.pumpAndSettle();
    await tester.tap(find.text(SafetyText.needHelpYes));
    await tester.pumpAndSettle();

    expect(h.api.reports.map((r) => r.$1), ['manual_unsafe', 'sos']);
    expect(h.recorder.live, isTrue, reason: '10-second pieces');
    expect(h.api.saves.last, '2:live:-', reason: 'the ride so far, now');
    expect(find.text(SafetyText.live), findsOneWidget);
  });

  testWidgets(
    'a high flag, answered okay: the flag goes now, the whole ride at the end',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);
      await h.say(tester, harassment);

      final (trigger, evidence) = h.api.reports.single;
      expect(trigger, 'auto');
      expect(evidence!.verdict.label, Label.sexualHarassment);
      expect(h.alerts, ['buzz'], reason: 'silent first');
      await tester.tap(find.text(SafetyText.askOk));
      await tester.pumpAndSettle();
      expect(h.alerts, ['buzz', 'clear']);
      await h.endRide(tester);

      expect(h.api.saves.last, '2:-:done');
      expect(h.api.kinds, ['warning', 'high']);
      expect(
        [for (final t in h.api.lastSaved!.transcript) t['text']],
        [uncomfortable, harassment],
        reason: 'the whole ride, so the cloud computes nothing again',
      );
    },
  );

  testWidgets('a high flag, need help: SOS and live', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, harassment);
    await tester.tap(find.text(SafetyText.askHelp));
    await tester.pumpAndSettle();
    expect(h.api.reports.map((r) => r.$1), ['auto', 'sos']);
    expect(h.recorder.live, isTrue);
    expect(find.text(SafetyText.helpSent), findsOneWidget);
  });

  testWidgets(
    'a high flag nobody answers: buzz, live at 60 s, alarm at 120 s, a shout sends SOS',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, harassment);

      await tester.pump(const Duration(seconds: 50));
      expect(h.alerts, List.filled(6, 'buzz'));
      expect(h.recorder.live, isFalse);
      await tester.pump(const Duration(seconds: 10)); // 60 s
      expect(h.recorder.live, isTrue, reason: 'an agent hears it now');
      expect(h.api.reports.map((r) => r.$1), ['auto'], reason: 'no extra case');
      expect(h.alerts.contains('alarm'), isFalse);
      await tester.pump(const Duration(seconds: 60)); // 120 s
      expect(h.alerts.last, 'alarm');
      expect(find.text(SafetyText.shout), findsOneWidget);

      await h.say(tester, 'TOLONG!');
      await tester.pumpAndSettle();
      expect(h.api.reports.map((r) => r.$1), ['auto', 'sos']);
      expect(h.alerts.last, 'clear');
      expect(find.text(SafetyText.askTitle), findsNothing);
      expect(find.text(SafetyText.shout), findsNothing);
    },
  );

  testWidgets('"tolong" in normal talk does nothing', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, 'Pak, tolong belok kiri di depan ya.');
    expect(h.api.reports, isEmpty);
  });

  testWidgets('a flagged ride recorded offline is sent once there is signal', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, harassment);
    await tester.tap(find.text(SafetyText.askOk));
    await tester.pumpAndSettle();
    h.api.failUploads = 1;
    await h.endRide(tester);
    expect(find.text(SafetyText.recordingQueued), findsOneWidget);
    expect((await h.store.rides()).single.uploaded, isFalse);

    await tester.pump(const Duration(minutes: 1)); // the next try
    expect(h.api.saves.last, '2:-:done');
    expect((await h.store.rides()).single.uploaded, isTrue);
  });

  testWidgets(
    'a ride the app never ended (killed) is closed and sent at launch',
    (tester) async {
      final h = Harness();
      await h.store.addPiece('GR-OLD', 0, Uint8List.fromList([9]));
      await h.store.save(
        RideMeta(
          tripId: 'GR-OLD',
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
          contentType: 'audio/aac',
          share: Share.live,
          markers: [
            {'at': 42.0, 'kind': 'sos'},
          ],
        ),
      );
      await h.pump(tester);
      await tester.pump();

      expect(h.api.calls, ['end:GR-OLD']);
      expect(h.api.saves.last, '1:-:done');
      final ride = (await h.store.rides()).single;
      expect((ride.ended, ride.uploaded, ride.durationSec), (true, true, 42.0));
    },
  );

  testWidgets('rides older than 7 days are deleted, sent or not', (
    tester,
  ) async {
    final h = Harness();
    await h.store.save(
      RideMeta(
        tripId: 'GR-WEEK',
        startedAt: DateTime.now().subtract(const Duration(days: 8)),
        contentType: 'audio/aac',
        ended: true,
      ),
    );
    await h.pump(tester);
    await tester.pump();
    expect(await h.store.rides(), isEmpty);
  });

  testWidgets(
    'SOS offline: offers 112 and keeps trying until it goes through',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      h.api.failReports = 2;
      await tester.tap(find.text('SOS'));
      await tester.pump();
      expect(find.text(SafetyText.sosOffline), findsOneWidget);
      await tester.tap(find.text(SafetyText.call112));
      expect(h.dialed, ['112']);

      await tester.pump(
        const Duration(seconds: 5),
      ); // second try, still offline
      expect(h.api.reports, isEmpty);
      await tester.pump(const Duration(seconds: 10)); // third try goes through
      expect(h.api.reports.map((r) => r.$1), ['sos']);
      expect(find.text(SafetyText.helpSent), findsOneWidget);
      expect(find.text(SafetyText.call112), findsNothing);
    },
  );

  testWidgets('the safe phrase sends a silent SOS, once, and goes live', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, 'Pak nanti lewat jalan biasa saja ya');

    expect(h.api.reports.map((r) => r.$1), ['sos']);
    expect(find.text(SafetyText.askTitle), findsNothing, reason: 'silent');
    expect(h.alerts, isEmpty, reason: 'nothing the other person could hear');
    expect(h.recorder.live, isTrue);
    await h.say(tester, 'Pak, nanti lewat jalan biasa aja ya.');
    expect(h.api.reports, hasLength(1), reason: 'once per ride');
  });

  testWidgets(
    'driver mode: no consent prompt, Safe Ride sent, joins the ride',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();
      expect(find.text('Safe Ride'), findsOneWidget);
      await tester.tap(find.text('Start ride'));
      await tester.pumpAndSettle();

      expect(find.text(SafetyText.consentTitle), findsNothing);
      expect(h.api.calls, ['safeRide:true', 'join']);
      expect(h.recorder.state, 'recording');
      expect((await h.store.rides()).single.role, 'driver');
      expect(find.text('Report passenger'), findsOneWidget);
    },
  );

  testWidgets('a driver with no ride waiting is told what to do', (
    tester,
  ) async {
    final h = Harness()..api.rideWaiting = false;
    await h.pump(tester);
    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();
    expect(find.text(SafetyText.noRideWaiting), findsOneWidget);
    expect(h.recorder.state, 'idle');
  });

  testWidgets(
    'each person sets their own safe phrase; the ride listens for it',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Mas, AC-nya dingin banget ya',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(await h.store.safePhrase(), 'Mas, AC-nya dingin banget ya');
      expect(find.text(SafetyText.safePhraseSaved), findsOneWidget);

      await h.startRide(tester);
      await h.say(tester, 'Pak, nanti lewat jalan biasa aja ya.');
      expect(h.api.reports, isEmpty, reason: 'the old phrase no longer counts');
      await h.say(
        tester,
        'mas ac nya dingin banget ya',
      ); // as speech-to-text writes it
      expect(h.api.reports.map((r) => r.$1), ['sos']);
    },
  );

  testWidgets('a too-short safe phrase is refused', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tolong');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 4 words'), findsOneWidget);
    expect(await h.store.safePhrase(), isNull);
  });

  testWidgets('a saved phrase is loaded at start, for the driver too', (
    tester,
  ) async {
    final h = Harness();
    await h.store.setSafePhrase('Bang, helmnya kebesaran nih kayaknya');
    await h.pump(tester);
    await tester.pump();
    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    expect(find.textContaining('helmnya kebesaran'), findsOneWidget);
  });
}
