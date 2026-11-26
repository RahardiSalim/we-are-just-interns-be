import 'package:material_ui/material_ui.dart';

import '../../services/api.dart';

/// Demo trip: consent, "recording on" banner, SOS and "I feel unsafe".
/// shortcut: trip and incidents are local mock state; wire to POST /trips and POST /incidents in Phase 2.
class TripScreen extends StatefulWidget {
  const TripScreen({super.key, required this.api});

  final Api api;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  bool _consent = false;
  bool _onTrip = false;
  bool? _backendUp; // null = still checking

  @override
  void initState() {
    super.initState();
    widget.api.health().then((up) {
      if (mounted) setState(() => _backendUp = up);
    });
  }

  void _report(String trigger) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$trigger sent to GoSafe (mock). A safety agent will follow up.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GoSafe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: Text(switch (_backendUp) {
                null => 'Checking server…',
                true => 'Server online',
                false => 'Server offline',
              }),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_onTrip)
              MaterialBanner(
                leading: const Icon(Icons.mic, color: Colors.red),
                content: const Text(
                  'Recording on. Audio is only sent if you report a problem.',
                ),
                actions: const [SizedBox.shrink()],
              ),
            SwitchListTile(
              title: const Text('Allow audio recording during trips'),
              subtitle: const Text('Both rider and driver must agree.'),
              value: _consent,
              onChanged: _onTrip ? null : (v) => setState(() => _consent = v),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _consent
                    ? () => setState(() => _onTrip = !_onTrip)
                    : null,
                child: Text(_onTrip ? 'End trip' : 'Start demo trip'),
              ),
            ),
            const Spacer(),
            if (_onTrip)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: () => _report('"I feel unsafe"'),
                      child: const Text('I feel unsafe'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                        minimumSize: const Size.fromHeight(64),
                      ),
                      onPressed: () => _report('SOS'),
                      child: const Text(
                        'SOS',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
