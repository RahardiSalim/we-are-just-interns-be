import 'package:material_ui/material_ui.dart';

import 'features/trip/trip_screen.dart';
import 'services/api.dart';

void main() {
  runApp(GoSafeApp(api: Api()));
}

class GoSafeApp extends StatelessWidget {
  const GoSafeApp({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoSafe',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF00AA13)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00AA13),
        brightness: Brightness.dark,
      ),
      home: TripScreen(api: api),
    );
  }
}
