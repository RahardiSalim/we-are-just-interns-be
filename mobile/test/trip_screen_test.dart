import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safety_engine.dart';
import 'package:gosafe/features/safety/are_you_ok.dart';
import 'package:gosafe/features/trip/trip_screen.dart';
import 'package:gosafe/services/api.dart';
import 'package:gosafe/services/recorder.dart';
import 'package:material_ui/material_ui.dart';

/// Records calls instead of hitting the backend.
class FakeApi extends Api {
  FakeApi() : super(token: () async => 't', baseUrl: 'http://fake');
  final calls = <String>[];
  final reports = <(String trigger, Decision? evidence)>[];
  List<Marker>? uploadedMarkers;
  List<String>? uploadedTranscript;

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
    reports.add((trigger, evidence));
    return 'inc-${reports.length}';
  }

  @override
  Future<void> uploadRecording(
    String tripId,
    Recording rec,
    List<Marker> markers,
    List<(Duration, String)> transcript,
  ) async {
    calls.add('upload:$tripId:${rec.contentType}');
    uploadedMarkers = markers;
    uploadedTranscript = [for (final (_, t) in transcript) t];
  }

  @override
  Future<void> replyCheckin(String checkinId, bool ok) async =>
      calls.add('reply:$checkinId:$ok');
}

class FakeRecorder implements TripRecorder {
  bool allowMic = true;
  String state = 'idle';

  @override
  Future<bool> start() async {
    if (allowMic) state = 'recording';
    return allowMic;
  }

  @override
  Future<Recording?> stop() async {
    state = 'stopped';
    return Recording(
      () async => Uint8List(4),
      'audio/mp4',
      const Duration(seconds: 25),
    );
  }

  @override
  Future<void> discard() async => state = 'discarded';
}

class Harness {
  final api = FakeApi();
  final recorder = FakeRecorder();
  final heard = StreamController<String>();
  final checkins = StreamController<List<String>>();
  final alerts = <String>[];
  bool driverSafeRide = true;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TripScreen(
          api: api,
          recorder: recorder,
          listen: () => heard.stream,
          tripInfo: (_) async => (
            riderConsent: api.calls.contains('start:true'),
            driverConsent: driverSafeRide,
          ),
          checkins: checkins.stream,
          alert: ({required loud}) async =>
              alerts.add(loud ? 'alarm' : 'alert'),
          clearAlert: () async => alerts.add('clear'),
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
        'upload:GR-TEST:audio/mp4',
      ]);
      expect(h.api.uploadedMarkers!.map((m) => m.kind), ['warning', 'high']);
      expect(h.api.uploadedTranscript, [
        uncomfortable,
        harassment,
      ], reason: 'the whole ride, for the AI review');
      expect(h.recorder.state, 'stopped');
    },
  );

  testWidgets('a ride with only warnings deletes its recording instead', (
    tester,
  ) async {
    final h = Harness();
    await h.pump(tester);
    await h.startRide(tester);
    await h.say(tester, uncomfortable);
    await h.endRide(tester);

    expect(h.api.calls, ['start:true', 'end:GR-TEST'], reason: 'no upload');
    expect(h.recorder.state, 'discarded');
    expect(find.textContaining('recording was deleted'), findsOneWidget);
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
}
