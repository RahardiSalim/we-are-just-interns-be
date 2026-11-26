import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/engine/safety_engine.dart';
import 'package:gosafe/features/trip/trip_screen.dart';
import 'package:gosafe/services/api.dart';
import 'package:material_ui/material_ui.dart';

/// Records calls instead of hitting the backend.
class FakeApi extends Api {
  FakeApi() : super(token: () async => 't', baseUrl: 'http://fake');
  final calls = <String>[];
  final reports = <(String trigger, Decision? evidence)>[];

  @override
  Future<bool> health() async => true;
  @override
  Future<void> setConsent(bool on) async => calls.add('consent:$on');
  @override
  Future<String> startTrip(String orderId, String mode) async {
    calls.add('start:$orderId:$mode');
    return orderId;
  }

  @override
  Future<void> endTrip(String tripId) async => calls.add('end:$tripId');
  @override
  Future<String> report(String tripId, String trigger, Decision? evidence) async {
    reports.add((trigger, evidence));
    return 'inc-${reports.length}';
  }

  @override
  Future<void> replyCheckin(String checkinId, bool ok) async => calls.add('reply:$checkinId:$ok');
}

class Harness {
  final api = FakeApi();
  final heard = StreamController<String>();
  final checkins = StreamController<List<String>>();
  TripInfo? trip = (mode: 'goride', bothConsented: true);

  Future<void> pump(WidgetTester tester, {String role = 'rider'}) async {
    await tester.pumpWidget(MaterialApp(
      home: TripScreen(
        api: api,
        role: role,
        listen: () => heard.stream,
        tripInfo: (_) async => trip,
        checkins: checkins.stream,
      ),
    ));
    await tester.pump();
  }

  Future<void> startTrip(WidgetTester tester, {String orderId = 'GR-1'}) async {
    await tester.tap(find.text('Allow audio recording during trips'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), orderId);
    await tester.tap(find.textContaining(RegExp(r'^(Start|Join) trip$')));
    await tester.pump();
  }

  Future<void> say(WidgetTester tester, String text) async {
    heard.add(text);
    await tester.pump();
    await tester.pump();
  }
}

const harassment = 'Cantik banget sih, nanti mampir ke tempat saya dulu.';

void main() {
  testWidgets('no trip without consent; with it, the trip starts and the phone listens', (tester) async {
    final h = Harness();
    await h.pump(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start trip')).onPressed, isNull);

    await h.startTrip(tester, orderId: 'GR-42');
    expect(h.api.calls, ['consent:true', 'start:GR-42:goride']);
    expect(find.textContaining('Recording on'), findsOneWidget);
    await h.say(tester, 'Selamat sore Mbak.');
    expect(find.text('Selamat sore Mbak.'), findsOneWidget);
  });

  testWidgets('if the other person did not consent, nothing is recorded but SOS works', (tester) async {
    final h = Harness()..trip = (mode: 'goride', bothConsented: false);
    await h.pump(tester);
    await h.startTrip(tester);
    expect(find.textContaining('Not recording'), findsOneWidget);
    expect(h.heard.hasListener, isFalse, reason: 'the microphone stream is never opened');

    await tester.tap(find.text('SOS'));
    await tester.pump();
    expect(h.api.reports.single.$1, 'sos');
  });

  testWidgets('an uncomfortable remark shows a neutral warning with a Report button', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await h.startTrip(tester);
    await h.say(tester, 'Mbak udah punya pacar belum?');

    expect(find.textContaining('Please keep it respectful'), findsOneWidget);
    expect(h.api.reports, isEmpty, reason: 'a warning sends nothing by itself');
    await tester.tap(find.text('Report'));
    await tester.pump();
    expect(h.api.reports.single.$1, 'manual_unsafe');
  });

  testWidgets('harassment: the phone reports on its own and asks the rider; need help sends SOS', (tester) async {
    final h = Harness();
    await h.pump(tester);
    await h.startTrip(tester);
    await h.say(tester, harassment);

    final (trigger, evidence) = h.api.reports.single;
    expect(trigger, 'auto');
    expect(evidence!.verdict.label, Label.sexualHarassment);
    expect(evidence.window.single.text, harassment);

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('I need help'));
    await tester.pump();
    expect(h.api.reports.map((r) => r.$1), ['auto', 'sos']);
  });

  testWidgets('a GoRide driver gets a banner, never a blocking dialog', (tester) async {
    final h = Harness();
    await h.pump(tester, role: 'driver');
    await h.startTrip(tester);
    expect(h.api.calls, ['consent:true'], reason: 'drivers join by order ID; only riders create trips');
    await h.say(tester, harassment);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Answer when you have stopped'), findsOneWidget);
    expect(h.api.reports.single.$1, 'auto');
  });

  testWidgets('a GoCar driver can be asked with a dialog', (tester) async {
    final h = Harness()..trip = (mode: 'gocar', bothConsented: true);
    await h.pump(tester, role: 'driver');
    await h.startTrip(tester);
    await h.say(tester, harassment);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('a backend check-in is answered once', (tester) async {
    final h = Harness();
    await h.pump(tester);
    h.checkins.add(['c1']);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text("I'm OK"));
    await tester.pump();
    h.checkins.add(['c1']); // the same unanswered check-in arriving again must not re-prompt
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.api.calls, ['reply:c1:true']);
  });
}
