import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/main.dart';
import 'package:gosafe/services/api.dart';

class FakeApi extends Api {
  FakeApi(this.up);
  final bool up;
  @override
  Future<bool> health() async => up;
}

void main() {
  testWidgets('a trip needs consent, then shows the banner and SOS', (
    tester,
  ) async {
    await tester.pumpWidget(GoSafeApp(api: FakeApi(true)));
    await tester.pump();
    expect(find.text('Server online'), findsOneWidget);

    await tester.tap(find.text('Start demo trip'));
    await tester.pump();
    expect(
      find.text('SOS'),
      findsNothing,
      reason: 'no trip starts without consent',
    );

    await tester.tap(find.text('Allow audio recording during trips'));
    await tester.pump();
    await tester.tap(find.text('Start demo trip'));
    await tester.pump();
    expect(find.textContaining('Recording on'), findsOneWidget);

    await tester.tap(find.text('SOS'));
    await tester.pump();
    expect(find.textContaining('SOS sent'), findsOneWidget);
  });

  testWidgets('shows when the backend is down', (tester) async {
    await tester.pumpWidget(GoSafeApp(api: FakeApi(false)));
    await tester.pump();
    expect(find.text('Server offline'), findsOneWidget);
  });
}
