import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../engine/safety_engine.dart';
import '../../services/api.dart';
import '../../services/recorder.dart';
import '../safety/are_you_ok.dart';

typedef TripInfo = ({bool riderConsent, bool driverConsent});

/// The whole ride: consent, recording, listening, every safety response, and what happens afterwards.
/// The phone decides (SafetyEngine); the backend only receives reports.
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    required this.api,
    required this.recorder,
    required this.listen,
    required this.tripInfo,
    required this.checkins,
    this.engine,
  });

  final Api api;
  final TripRecorder recorder;

  /// Finished utterances from speech-to-text. Mocked until VAD + Whisper are ready.
  final Stream<String> Function() listen;

  /// Both consents as the backend stored them for the trip.
  final Future<TripInfo?> Function(String tripId) tripInfo;

  /// IDs of this user's unanswered backend check-ins (after an "I feel unsafe" press).
  final Stream<List<String>> checkins;
  final SafetyEngine Function()? engine;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

/// Only a ride with a high flag or an SOS sends its full recording; anything less stays private.
const uploadWhen = {'high', 'sos'};

class _TripScreenState extends State<TripScreen> {
  String? _tripId;
  bool _recording = false;
  bool? _driverSafeRide;
  bool? _backendUp;
  bool _busy = false;
  bool _warning = false;
  String? _notice;
  String? _message;
  final _heard = <String>[];
  final _markers = <Marker>[];
  DateTime? _rideStart;
  Decision? _last;
  late SafetyEngine _engine;
  StreamSubscription<String>? _listening;
  StreamSubscription<List<String>>? _checkinSub;
  final _answered = <String>{};

  @override
  void initState() {
    super.initState();
    widget.api.health().then(
      (up) => mounted ? setState(() => _backendUp = up) : null,
    );
    _checkinSub = widget.checkins.listen(_onCheckins);
  }

  @override
  void dispose() {
    _listening?.cancel();
    _checkinSub?.cancel();
    super.dispose();
  }

  // Shown at the top, never as a snackbar: nothing may ever cover the SOS button.
  void _say(String text) => setState(() => _message = text);

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _notice = 'Something went wrong: $e');
    }
  }

  Duration get _sinceStart => _rideStart == null
      ? Duration.zero
      : DateTime.now().difference(_rideStart!);

  Future<void> _startRide() async {
    final consent = await askConsent(context);
    setState(() => _busy = true);
    await _guard(() async {
      final tripId = await widget.api.startTrip(riderConsent: consent);
      final trip = await widget.tripInfo(tripId);
      final both = trip != null && trip.riderConsent && trip.driverConsent;
      // Nothing is recorded unless the rider agreed now and the driver opted in beforehand.
      final micOn = both && await widget.recorder.start();
      _engine =
          (widget.engine ??
          () => SafetyEngine(classifier: KeywordClassifier()))();
      if (micOn) _listening = widget.listen().listen(_onHeard);
      setState(() {
        _tripId = tripId;
        _recording = micOn;
        _driverSafeRide = trip?.driverConsent;
        _rideStart = DateTime.now();
        _notice = both && !micOn
            ? 'Allow microphone access to record your rides.'
            : null;
        _heard.clear();
        _markers.clear();
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _endRide() async {
    setState(() => _busy = true);
    await _guard(() async {
      _listening?.cancel(); // nothing to wait for; stop hearing before the ride closes
      final tripId = _tripId!;
      await widget.api.endTrip(tripId);
      if (_recording) {
        if (_markers.any((m) => uploadWhen.contains(m.kind))) {
          // The full ride goes to the safety team, with every moment to check, then leaves the phone.
          final rec = await widget.recorder.stop();
          if (rec != null) {
            await widget.api.uploadRecording(tripId, rec, List.of(_markers));
          }
          if (mounted) {
            _say('Ride ended. The recording was sent to our safety team.');
          }
        } else {
          await widget.recorder.discard();
          if (mounted) {
            _say(
              'Ride ended. Nothing needed checking, so the recording was deleted.',
            );
          }
        }
      }
      setState(() {
        _tripId = _last = null;
        _recording = _warning = false;
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  void _onHeard(String text) {
    final d = _engine.hear(text);
    setState(() {
      _heard.add(text);
      _last = d;
    });
    switch (d.action) {
      case SafetyAction.warn:
        _markers.add(
          Marker(_sinceStart, 'warning', verdict: d.verdict, text: text),
        );
        setState(() => _warning = true);
      case SafetyAction.high:
        _markers.add(
          Marker(_sinceStart, 'high', verdict: d.verdict, text: text),
        );
        // The flag goes to the safety team at once, as an escalated case.
        _guard(() async {
          await widget.api.report(_tripId!, 'auto', d);
        });
        _askAreYouOk((ok) => ok ? _say(SafetyText.okThanks) : _report('sos'));
      case SafetyAction.none:
        break;
    }
  }

  void _askAreYouOk(void Function(bool ok) answer) =>
      askAreYouOk(context).then((ok) => ok == null ? null : answer(ok));

  void _onCheckins(List<String> ids) {
    for (final id in ids.where(_answered.add)) {
      _askAreYouOk(
        (ok) => _guard(() async {
          await widget.api.replyCheckin(id, ok);
          if (mounted) _say(ok ? SafetyText.okThanks : SafetyText.helpSent);
        }),
      );
    }
  }

  Future<void> _report(String trigger) => _guard(() async {
    _markers.add(Marker(_sinceStart, trigger, verdict: _last?.verdict));
    await widget.api.report(_tripId!, trigger, _last);
    if (mounted) {
      _say(trigger == 'sos' ? SafetyText.helpSent : SafetyText.reportSent);
    }
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final onRide = _tripId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GoSafe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              label: Text(switch (_backendUp) {
                null => 'Checking…',
                true => 'Online',
                false => 'Offline',
              }),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // Everything scrolls except the bottom buttons, so SOS is always on screen.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (onRide)
                    MaterialBanner(
                      leading: Icon(
                        _recording ? Icons.mic : Icons.mic_off,
                        color: _recording ? Colors.red : null,
                      ),
                      content: Text(
                        _recording
                            ? 'Recording on. Only shared if something serious happens.'
                            : 'Not recording this ride. SOS still works.',
                      ),
                      actions: const [SizedBox.shrink()],
                    ),
                  if (_warning)
                    MaterialBanner(
                      backgroundColor: colors.tertiaryContainer,
                      leading: const Icon(Icons.volunteer_activism),
                      content: const Text(SafetyText.warning),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _warning = false),
                          child: const Text(SafetyText.warningFine),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _warning = false);
                            _report('manual_unsafe');
                          },
                          child: const Text(SafetyText.warningReport),
                        ),
                      ],
                    ),
                  if (_message != null)
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: ListTile(
                        leading: const Icon(Icons.favorite_outline),
                        title: Text(_message!),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Dismiss',
                          onPressed: () => setState(() => _message = null),
                        ),
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _notice!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  if (onRide) ...[
                    ListTile(
                      leading: Icon(
                        _driverSafeRide == true
                            ? Icons.verified_user
                            : Icons.shield_outlined,
                      ),
                      title: Text('Ride $_tripId'),
                      subtitle: Text(
                        _driverSafeRide == true
                            ? 'Your driver has Safe Ride on'
                            : "Your driver hasn't turned on Safe Ride",
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Heard (temporary speech-to-text)',
                        style: text.labelMedium,
                      ),
                    ),
                    for (final (i, t) in _heard.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          t,
                          key: ValueKey('heard-$i'),
                          style: text.bodySmall,
                        ),
                      ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
                      child: Column(
                        spacing: 16,
                        children: [
                          Icon(Icons.shield, size: 64, color: colors.primary),
                          Text(
                            'Ride with peace of mind',
                            style: text.titleLarge,
                          ),
                          const Text(
                            'GoSafe listens for trouble during your ride and gets help fast if you need it.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: onRide
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: () => _report('manual_unsafe'),
                          child: const Text('I feel unsafe'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.error,
                            foregroundColor: colors.onError,
                            minimumSize: const Size.fromHeight(64),
                          ),
                          onPressed: () => _report('sos'),
                          child: const Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _endRide,
                          child: const Text('End ride'),
                        ),
                      ],
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: _busy ? null : _startRide,
                      child: const Text('Start ride'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
