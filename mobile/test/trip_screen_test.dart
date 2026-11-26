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
  List<String>? uploadedMarkers;
  List<String>? uploadedTranscript;
  Uint8List? uploadedAudio;
  int failReports = 0; // the next n reports fail, as with no internet
  int failUploads = 0;

  @override
  Future<bool> health() async => true;
  @override
  Future<String> startTrip({
    required bool riderConsent,
    String? orderId,
  }) async {
    calls.add('start:$riderConsent');
    return 'GR-TEST';
  }

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
  Future<void> uploadRecording(RideMeta ride, Uint8List audio) async {
    if (failUploads > 0) {
      failUploads--;
      throw ApiException(0, 'offline');
    }
    calls.add('upload:${ride.tripId}:${ride.contentType}');
    uploadedMarkers = [for (final m in ride.markers) m['kind'] as String];
    uploadedTranscript = [for (final t in ride.transcript) t['text'] as String];
    uploadedAudio = audio;
  }

  @override
  Future<void> replyCheckin(String checkinId, bool ok) async =>
      calls.add('reply:$checkinId:$ok');
}

class FakeRecorder implements TripRecorder {
  FakeRecorder(this.store);
  final RideStore store;
  bool allowMic = true;
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
  final checkins = StreamController<List<String>>();
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
            riderConsent: api.calls.contains('start:true'),
            driverConsent: driverSafeRide,
          ),
          checkins: checkins.stream,
          alert: ({required loud}) async =>
              alerts.add(loud ? 'alarm' : 'alert'),
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
    expect(
      h.heard.hasListener,
      isFalse,
      reason: 'the transcript stream is never opened',
    );
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
    'an uncomfortable remark gets a kind warning and nothing is sent',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);

      expect(find.text(SafetyText.warning), findsOneWidget);
      expect(h.api.reports, isEmpty, reason: 'a warning stays on the phone');
      await tester.tap(find.text(SafetyText.warningReport));
      await tester.pump();
      expect(h.api.reports.single.$1, 'manual_unsafe');
    },
  );

  testWidgets(
    'a high flag is sent at once and the rider is asked; need help sends SOS',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, harassment);

      final (trigger, evidence) = h.api.reports.single;
      expect(trigger, 'auto');
      expect(evidence!.verdict.label, Label.sexualHarassment);
      expect(find.text(SafetyText.askTitle), findsOneWidget);

      await tester.tap(find.text(SafetyText.askHelp));
      await tester.pumpAndSettle();
      expect(h.api.reports.map((r) => r.$1), ['auto', 'sos']);
      expect(find.text(SafetyText.helpSent), findsOneWidget);
    },
  );

  testWidgets(
    'after a flagged ride, the full recording uploads with every moment to check',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);
      await h.say(tester, harassment);
      await tester.tap(find.text(SafetyText.askOk));
      await tester.pumpAndSettle();
      await h.endRide(tester);

      expect(h.api.calls, [
        'start:true',
        'end:GR-TEST',
        'upload:GR-TEST:audio/aac',
      ]);
      expect(h.api.uploadedMarkers, ['warning', 'high']);
      expect(h.api.uploadedAudio, [
        1,
        2,
        3,
        4,
      ], reason: 'every piece, in order');
      expect(h.api.uploadedTranscript, [
        uncomfortable,
        harassment,
      ], reason: 'the whole ride, for the AI review');
      expect(h.recorder.state, 'stopped');
    },
  );

  testWidgets('a ride with only warnings keeps its recording on the phone', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, uncomfortable);
    await h.endRide(tester);

    expect(h.api.calls, ['start:true', 'end:GR-TEST'], reason: 'no upload');
    final ride = (await h.store.rides()).single;
    expect(
      (ride.ended, ride.uploaded, ride.transcript.length),
      (true, false, 1),
    );
    expect(find.text(SafetyText.keptOnPhone), findsOneWidget);
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
    expect(h.api.calls.last, 'upload:GR-TEST:audio/aac');
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
          markers: [
            {'at': 42.0, 'kind': 'sos'},
          ],
        ),
      );
      await h.pump(tester);
      await tester.pump();

      expect(h.api.calls, ['end:GR-OLD', 'upload:GR-OLD:audio/aac']);
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

  testWidgets('a backend check-in is answered once', (tester) async {
    final h = Harness();
    await h.pump(tester);
    h.checkins.add(['c1']);
    await tester.pumpAndSettle();
    await tester.tap(find.text(SafetyText.askOk));
    await tester.pumpAndSettle();
    h.checkins.add([
      'c1',
    ]); // the same unanswered check-in arriving again must not re-prompt
    await tester.pumpAndSettle();
    expect(find.text(SafetyText.askTitle), findsNothing);
    expect(h.api.calls, ['reply:c1:true']);
  });

  testWidgets(
    'a high flag sounds the alarm until answered; a check-in alerts quietly',
    (tester) async {
      final h = Harness();
      await h.pump(tester);
      await h.startRide(tester);
      await h.say(tester, uncomfortable);
      expect(h.alerts, isEmpty, reason: 'a warning never sounds an alarm');
      await h.say(tester, harassment);
      expect(h.alerts, ['alarm']);
      await tester.tap(find.text(SafetyText.askOk));
      await tester.pumpAndSettle();
      expect(h.alerts, ['alarm', 'clear']);

      h.checkins.add(['c1']);
      await tester.pumpAndSettle();
      await tester.tap(find.text(SafetyText.askOk));
      await tester.pumpAndSettle();
      expect(h.alerts, ['alarm', 'clear', 'alert', 'clear']);
    },
  );

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

  testWidgets('the safe phrase sends a silent SOS, once, with no tap', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, 'Pak nanti lewat jalan biasa saja ya');

    expect(h.api.reports.map((r) => r.$1), ['sos']);
    expect(find.text(SafetyText.askTitle), findsNothing, reason: 'silent');
    expect(h.alerts, isEmpty, reason: 'no alarm the driver could hear');
    await h.say(tester, 'Pak, nanti lewat jalan biasa aja ya.');
    expect(h.api.reports, hasLength(1), reason: 'once per ride');
  });
}
