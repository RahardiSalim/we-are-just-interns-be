import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../engine/safety_engine.dart';
import '../../services/api.dart';
import '../safety/are_you_ok.dart';

/// One trip, as rider or driver: consent, order ID, listening, and every safety response.
/// The phone decides (SafetyEngine); the backend only receives reports.
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    required this.api,
    required this.role,
    required this.listen,
    required this.tripInfo,
    required this.checkins,
    this.onSignOut,
    this.engine,
  });

  final Api api;
  final String role; // rider | driver
  /// Finished utterances from speech-to-text (mocked for now).
  final Stream<String> Function() listen;
  /// The trip as the backend stored it (null if it doesn't exist). Drivers join by order ID.
  final Future<TripInfo?> Function(String tripId) tripInfo;
  /// IDs of this user's unanswered backend check-ins (after an "I feel unsafe" press).
  final Stream<List<String>> checkins;
  final VoidCallback? onSignOut;
  final SafetyEngine Function()? engine;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

enum _Prompt { none, warning, areYouOkBanner }

typedef TripInfo = ({String mode, bool bothConsented});

class _TripScreenState extends State<TripScreen> {
  final _orderId = TextEditingController();
  String _mode = 'goride';
  bool _consent = false;
  String? _tripId;
  bool _recording = false;
  bool? _backendUp;
  String? _error;
  final _heard = <String>[];
  Decision? _last;
  _Prompt _prompt = _Prompt.none;
  late SafetyEngine _engine;
  StreamSubscription<String>? _listening;
  StreamSubscription<List<String>>? _checkinSub;
  final _answered = <String>{};

  bool get _isRider => widget.role == 'rider';
  // A GoRide driver can't tap while riding: never block their screen.
  bool get _canBlock => _isRider || _mode == 'gocar';

  @override
  void initState() {
    super.initState();
    widget.api.health().then((up) => mounted ? setState(() => _backendUp = up) : null);
    _checkinSub = widget.checkins.listen(_onCheckins);
  }

  @override
  void dispose() {
    _listening?.cancel();
    _checkinSub?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setConsent(bool on) => _run(() async {
        await widget.api.setConsent(on);
        setState(() => _consent = on);
      });

  Future<void> _start() => _run(() async {
        final orderId = _orderId.text.trim();
        if (_isRider) await widget.api.startTrip(orderId, _mode);
        final trip = await widget.tripInfo(orderId);
        if (trip == null) throw 'No trip for order $orderId yet. Ask the rider to start it.';
        _engine = (widget.engine ?? () => SafetyEngine(classifier: KeywordClassifier()))();
        // Nothing is recorded unless rider and driver both agreed.
        if (trip.bothConsented) _listening = widget.listen().listen(_onHeard);
        setState(() {
          _tripId = orderId;
          _mode = trip.mode;
          _recording = trip.bothConsented;
          _heard.clear();
        });
      });

  Future<void> _end() => _run(() async {
        await _listening?.cancel();
        if (_isRider) await widget.api.endTrip(_tripId!);
        setState(() {
          _tripId = _last = null;
          _prompt = _Prompt.none;
          _recording = false;
        });
      });

  void _onHeard(String text) {
    final d = _engine.hear(text);
    setState(() {
      _heard.add(text);
      _last = d;
    });
    switch (d.action) {
      case SafetyAction.warn:
        setState(() => _prompt = _Prompt.warning);
      case SafetyAction.high:
        _run(() async {
          await widget.api.report(_tripId!, 'auto', d);
        });
        _askAreYouOk((ok) => ok ? null : _report('sos'));
      case SafetyAction.none:
        break;
    }
  }

  /// Rider / GoCar driver: a dialog. GoRide driver: a banner that never demands an answer.
  void _askAreYouOk(void Function(bool ok) answer) {
    if (_canBlock) {
      askAreYouOk(context).then((ok) => ok == null ? null : answer(ok));
    } else {
      setState(() => _prompt = _Prompt.areYouOkBanner);
      _bannerAnswer = answer;
    }
  }

  void Function(bool ok)? _bannerAnswer;

  void _onCheckins(List<String> ids) {
    for (final id in ids.where(_answered.add)) {
      _askAreYouOk((ok) => _run(() => widget.api.replyCheckin(id, ok)));
    }
  }

  Future<void> _report(String trigger) => _run(() async {
        await widget.api.report(_tripId!, trigger, _last);
        _snack(trigger == 'sos' ? 'SOS sent. A safety agent will contact you.' : 'Report sent. Thank you for telling us.');
      });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final onTrip = _tripId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('GoSafe · ${_isRider ? 'Rider' : 'Driver'}'),
        actions: [
          Chip(label: Text(switch (_backendUp) { null => 'Checking…', true => 'Online', false => 'Offline' })),
          if (widget.onSignOut != null) IconButton(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), tooltip: 'Sign out'),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onTrip && !_recording)
              const MaterialBanner(
                leading: Icon(Icons.mic_off),
                content: Text('Not recording: both rider and driver must allow it. SOS still works.'),
                actions: [SizedBox.shrink()],
              ),
            if (_recording)
              const MaterialBanner(
                leading: Icon(Icons.mic, color: Colors.red),
                content: Text('Recording on. Audio stays encrypted on this phone for 7 days and is only sent if a problem is reported.'),
                actions: [SizedBox.shrink()],
              ),
            if (_prompt == _Prompt.warning)
              MaterialBanner(
                backgroundColor: colors.tertiaryContainer,
                leading: const Icon(Icons.warning_amber),
                content: const Text(
                  'This conversation seems uncomfortable. Please keep it respectful. '
                  'If you feel unsafe, tell us.',
                ),
                actions: [
                  TextButton(onPressed: () => setState(() => _prompt = _Prompt.none), child: const Text('Dismiss')),
                  TextButton(
                    onPressed: () {
                      setState(() => _prompt = _Prompt.none);
                      _report('manual_unsafe');
                    },
                    child: const Text('Report'),
                  ),
                ],
              ),
            if (_prompt == _Prompt.areYouOkBanner)
              AreYouOkBanner(onAnswer: (ok) {
                setState(() => _prompt = _Prompt.none);
                _bannerAnswer?.call(ok);
              }),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: colors.error))),
            SwitchListTile(
              title: const Text('Allow audio recording during trips'),
              subtitle: const Text('Both rider and driver must agree.'),
              value: _consent,
              onChanged: onTrip ? null : _setConsent,
            ),
            if (!onTrip) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(controller: _orderId, decoration: const InputDecoration(labelText: 'GoJek order ID')),
              ),
              if (_isRider)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'goride', label: Text('GoRide')), ButtonSegment(value: 'gocar', label: Text('GoCar'))],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: onTrip ? _end : (_consent ? _start : null),
                child: Text(onTrip ? 'End trip' : (_isRider ? 'Start trip' : 'Join trip')),
              ),
            ),
            if (onTrip)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Text('Heard (mock speech-to-text)', style: Theme.of(context).textTheme.labelMedium),
                    for (final (i, t) in _heard.indexed)
                      Text(t, key: ValueKey('heard-$i'), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              )
            else
              const Spacer(),
            if (onTrip)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    OutlinedButton(onPressed: () => _report('manual_unsafe'), child: const Text('I feel unsafe')),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                        minimumSize: const Size.fromHeight(64),
                      ),
                      onPressed: () => _report('sos'),
                      child: const Text('SOS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
