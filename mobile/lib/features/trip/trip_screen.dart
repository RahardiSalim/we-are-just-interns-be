import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../engine/safe_phrase.dart';
import '../../engine/safety_engine.dart';
import '../../services/api.dart';
import '../../services/recorder.dart';
import '../../services/ride_store.dart';
import '../../theme.dart';
import '../safety/are_you_ok.dart';

typedef TripInfo = ({bool riderConsent, bool driverConsent});

/// The whole ride: consent, recording, listening, every safety response, and what happens afterwards.
/// The phone decides (SafetyEngine); the backend only receives reports.
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    required this.api,
    required this.recorder,
    required this.store,
    required this.listen,
    required this.tripInfo,
    required this.checkins,
    this.engine,
    this.alert,
    this.clearAlert,
    this.dial,
    this.safePhrase,
  });

  final Api api;
  final TripRecorder recorder;

  /// Every ride kept on the phone for 7 days: audio pieces plus markers and transcript.
  final RideStore store;

  /// Finished utterances from speech-to-text. Mocked until VAD + Whisper are ready.
  final Stream<String> Function() listen;

  /// Both consents as the backend stored them for the trip.
  final Future<TripInfo?> Function(String tripId) tripInfo;

  /// IDs of this user's unanswered backend check-ins (after an "I feel unsafe" press).
  final Stream<List<String>> checkins;
  final SafetyEngine Function()? engine;

  /// A phone notification that reaches the user even with the screen off. `loud`: a repeating
  /// alarm, for a high flag. Null on the web preview.
  final Future<void> Function({required bool loud})? alert;
  final Future<void> Function()? clearAlert;

  /// Opens the phone's dialer with a number (no call is placed without the user). Null on the web.
  final Future<void> Function(String number)? dial;

  /// The rider's hands-free SOS: hearing it sends a silent SOS (no dialog, no alarm the driver
  /// could notice). Null turns it off.
  final SafePhrase? safePhrase;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  String? _tripId;
  bool _recording = false;
  bool? _driverSafeRide;
  bool? _backendUp;
  bool _busy = false;
  bool _warning = false;
  bool _sosOffline = false;
  bool _safePhraseUsed = false;
  String? _notice;
  String? _message;
  final _heard = <(Duration, String)>[];
  RideMeta? _ride; // null when this ride isn't recorded
  Future<void> _saving = Future.value();
  Future<Set<String>> _uploads = Future.value({});
  Timer? _retry;
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
    // Recordings that couldn't be sent (no signal, app closed mid-ride) go out once they can.
    _sendRecordings();
    _retry = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _sendRecordings(),
    );
  }

  @override
  void dispose() {
    _listening?.cancel();
    _checkinSub?.cancel();
    _retry?.cancel();
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
      final micOn = both && await widget.recorder.start(tripId);
      if (micOn) {
        _ride = RideMeta(
          tripId: tripId,
          startedAt: DateTime.now(),
          contentType: widget.recorder.contentType,
        );
        await _persist();
      }
      _engine =
          (widget.engine ??
          () => SafetyEngine(classifier: KeywordClassifier()))();
      if (micOn) _listening = widget.listen().listen(_onHeard);
      setState(() {
        _tripId = tripId;
        _safePhraseUsed = false;
        _recording = micOn;
        _driverSafeRide = trip?.driverConsent;
        _rideStart = DateTime.now();
        _notice = both && !micOn
            ? 'Allow microphone access to record your rides.'
            : null;
        _heard.clear();
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _endRide() async {
    setState(() => _busy = true);
    await _guard(() async {
      _listening?.cancel(); // nothing to wait for; stop hearing before the ride closes
      final tripId = _tripId!;
      final ride = _ride;
      if (ride != null) {
        ride.durationSec = (await widget.recorder.stop()).inMilliseconds / 1000;
        ride.ended = true;
        await _persist();
      }
      // shortcut: with no signal the backend trip stays active; nothing reads that status yet.
      await widget.api.endTrip(tripId).catchError((_) {});
      if (ride != null) {
        // A high or SOS ride goes to the safety team with every moment to check; the rest stays
        // encrypted on the phone and is deleted after 7 days.
        final sent = await _sendRecordings();
        if (mounted) {
          _say(
            !ride.flagged
                ? SafetyText.keptOnPhone
                : sent.contains(tripId)
                ? SafetyText.recordingSent
                : SafetyText.recordingQueued,
          );
        }
      }
      setState(() {
        _tripId = _last = _ride = null;
        _recording = _warning = false;
      });
    });
    if (mounted) setState(() => _busy = false);
  }

  /// Saves the ride's details as they change, one write at a time.
  Future<void> _persist() {
    final ride = _ride;
    if (ride == null) return _saving;
    return _saving = _saving.then((_) => widget.store.save(ride));
  }

  void _mark(Marker m) {
    _ride?.markers.add(m.toJson());
    _persist();
  }

  /// Sends every ended high or SOS ride not sent yet, deletes rides older than 7 days, and
  /// closes rides the app never ended (it was killed). Runs one at a time. Returns what was sent.
  Future<Set<String>> _sendRecordings() => _uploads = _uploads.then((_) async {
    final sent = <String>{};
    try {
      for (final r in await tidy(widget.store, DateTime.now())) {
        if (!r.ended && r.tripId != _tripId) {
          r.ended = true;
          r.durationSec = [
            for (final x in [...r.markers, ...r.transcript])
              (x['at'] as num).toDouble(),
          ].fold(r.durationSec, (a, b) => a > b ? a : b);
          await widget.store.save(r);
          await widget.api.endTrip(r.tripId).catchError((_) {});
        }
        if (!r.ended || !r.flagged || r.uploaded) continue;
        try {
          await widget.api.uploadRecording(
            r,
            await widget.store.audio(r.tripId),
          );
          r.uploaded = true;
          await widget.store.save(r);
          sent.add(r.tripId);
        } catch (_) {
          // No signal: the next try is in a minute, for as long as the ride is kept.
        }
      }
    } catch (_) {
      // Never break the chain: a later call must still run.
    }
    return sent;
  });

  void _onHeard(String text) {
    final d = _engine.hear(text);
    final at = _sinceStart;
    setState(() {
      _heard.add((at, text));
      _last = d;
    });
    _ride?.transcript.add({'at': at.inMilliseconds / 1000, 'text': text});
    _persist();
    if (!_safePhraseUsed && (widget.safePhrase?.heardIn(text) ?? false)) {
      _safePhraseUsed = true;
      _report('sos');
    }
    switch (d.action) {
      case SafetyAction.warn:
        _mark(Marker(at, 'warning', verdict: d.verdict, text: text));
        setState(() => _warning = true);
      case SafetyAction.high:
        _mark(Marker(at, 'high', verdict: d.verdict, text: text));
        // The flag goes to the safety team at once, as an escalated case.
        _deliver('auto', d);
        _askAreYouOk(
          (ok) => ok ? _say(SafetyText.okThanks) : _report('sos'),
          loud: true,
        );
      case SafetyAction.none:
        break;
    }
  }

  void _askAreYouOk(void Function(bool ok) answer, {bool loud = false}) {
    widget.alert?.call(loud: loud);
    askAreYouOk(context).then((ok) {
      widget.clearAlert?.call();
      if (ok != null) answer(ok);
    });
  }

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

  Future<void> _report(String trigger) async {
    _mark(Marker(_sinceStart, trigger, verdict: _last?.verdict));
    if (await _deliver(trigger, _last) && mounted) {
      _say(trigger == 'sos' ? SafetyText.helpSent : SafetyText.reportSent);
    }
  }

  /// Keeps trying until the report reaches the safety team: no signal must never swallow an SOS.
  /// While an SOS can't get through, the rider is offered 112.
  // shortcut: a reply lost after the server saved the report makes a duplicate case; add an
  // idempotency key if agents see doubles.
  Future<bool> _deliver(String trigger, Decision? evidence) async {
    final tripId = _tripId!;
    for (var wait = const Duration(seconds: 5); ; wait *= 2) {
      try {
        await widget.api.report(tripId, trigger, evidence);
        if (mounted && trigger == 'sos') setState(() => _sosOffline = false);
        return true;
      } catch (_) {
        if (!mounted) return false;
        if (trigger == 'sos') setState(() => _sosOffline = true);
        // An SOS retries at least every 10 s, so it goes out soon after signal returns.
        final most = trigger == 'sos'
            ? const Duration(seconds: 10)
            : const Duration(minutes: 1);
        await Future<void>.delayed(wait > most ? most : wait);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  if (_sosOffline)
                    MaterialBanner(
                      backgroundColor: GoSafeColors.highTint,
                      leading: const Icon(Icons.signal_cellular_off),
                      content: const Text(SafetyText.sosOffline),
                      actions: [
                        if (widget.dial != null)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: GoSafeColors.high,
                              minimumSize: const Size(0, 48),
                            ),
                            onPressed: () => widget.dial!('112'),
                            child: const Text(SafetyText.call112),
                          ),
                      ],
                    ),
                  if (onRide)
                    MaterialBanner(
                      leading: Icon(
                        _recording ? Icons.mic : Icons.mic_off,
                        color: _recording ? GoSafeColors.high : null,
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
                      backgroundColor: GoSafeColors.warnTint,
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
                        style: TextStyle(color: GoSafeColors.high),
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
                    for (final (i, (_, t)) in _heard.indexed)
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
                          Icon(
                            Icons.verified_user,
                            size: 64,
                            color: GoSafeColors.brand,
                          ),
                          Text(
                            'Ride with peace of mind',
                            style: text.titleLarge,
                            textAlign: TextAlign.center,
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
                            backgroundColor: GoSafeColors.sos,
                            foregroundColor: Colors.white,
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
