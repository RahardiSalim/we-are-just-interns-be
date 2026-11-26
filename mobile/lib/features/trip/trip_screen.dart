import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../engine/safe_phrase.dart';
import '../../engine/safety_engine.dart';
import '../../services/api.dart';
import '../../services/recorder.dart';
import '../../services/ride_store.dart';
import '../../services/ride_sync.dart';
import '../../theme.dart';
import '../safety/are_you_ok.dart';

typedef TripInfo = ({bool riderConsent, bool driverConsent});

/// A high flag nobody answers: buzz every [_pulse]; at [_goLiveAt] stream to an agent; at [_alarmAt] the
/// loud alarm and "shout TOLONG". Quiet first, so the phone doesn't give the rider away.
const _pulse = Duration(seconds: 10);
const _goLiveAt = Duration(seconds: 60);
const _alarmAt = Duration(seconds: 120);

/// Shouted for help while the alarm rings after an unanswered high flag. Only listened for then,
/// so "tolong belok kiri" in normal talk does nothing.
const _helpWords = [SafePhrase('tolong'), SafePhrase('help')];

/// The whole ride, on the rider's or the driver's phone: consent, recording, listening, every safety
/// response, and what leaves the phone and when ([Share]). The phone decides; the backend receives.
class TripScreen extends StatefulWidget {
  const TripScreen({
    super.key,
    required this.api,
    required this.recorder,
    required this.store,
    required this.listen,
    required this.tripInfo,
    this.engine,
    this.alert,
    this.clearAlert,
    this.dial,
    this.safePhrase,
    this.describe,
  });

  final Api api;
  final TripRecorder recorder;

  /// Every ride kept on the phone for 7 days: audio pieces plus markers and transcript.
  final RideStore store;

  /// Finished utterances from speech-to-text. Mocked until VAD + Whisper are ready.
  final Stream<String> Function() listen;

  /// Both consents as the backend stored them for the trip.
  final Future<TripInfo?> Function(String tripId) tripInfo;
  final SafetyEngine Function()? engine;

  /// A notification that reaches the user with the screen off. Not `loud`: vibration only, silent.
  /// `loud`: the alarm sound, repeating until answered. Null on the web preview.
  final Future<void> Function({required bool loud})? alert;
  final Future<void> Function()? clearAlert;

  /// Opens the phone's dialer with a number (no call is placed without the user). Null on the web.
  final Future<void> Function(String number)? dial;

  /// The hands-free SOS: hearing it sends a silent SOS (no dialog, no alarm the other person could
  /// notice). Null turns it off.
  final SafePhrase? safePhrase;

  /// A note shown under each heard line, e.g. the dev classifier's raw label. Null shows nothing.
  final String? Function(String line)? describe;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  // shortcut: the rider/driver switch is for the demo; in production they're two apps.
  String _role = 'rider';
  bool _safeRide = true; // the driver's setting: record my rides
  String? _tripId;
  bool _recording = false;
  bool? _driverSafeRide;
  bool? _backendUp;
  bool _busy = false;
  bool _warning = false;
  bool _sosOffline = false;
  bool _safePhraseUsed = false;
  late SafePhrase? _phrase = widget.safePhrase; // the user's own once loaded
  bool _asking = false; // "Are you okay?" is open
  bool _shout = false; // the alarm rings: listening for "tolong"
  bool _live = false;
  String? _notice;
  String? _message;
  final _heard = <(Duration, String)>[];
  RideMeta? _ride; // null when this ride isn't recorded
  Future<void> _saving = Future.value();
  Future<Set<String>> _uploads = Future.value({});
  Future<void> _streaming = Future.value();
  Timer? _retry;
  Timer? _highCheck;
  Timer? _liveTimer;
  DateTime? _rideStart;
  Decision? _last;
  late SafetyEngine _engine;
  StreamSubscription<String>? _listening;

  bool get _driver => _role == 'driver';

  @override
  void initState() {
    super.initState();
    widget.api.health().then(
      (up) => mounted ? setState(() => _backendUp = up) : null,
    );
    widget.store.safePhrase().then((saved) {
      if (saved != null && mounted) setState(() => _phrase = SafePhrase(saved));
    });
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
    _retry?.cancel();
    _highCheck?.cancel();
    _liveTimer?.cancel();
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
    // The rider is asked now. The driver chose earlier: their Safe Ride setting.
    final consent = _driver || await askConsent(context);
    setState(() => _busy = true);
    await _guard(() async {
      final String tripId;
      if (_driver) {
        await widget.api.setSafeRide(_safeRide);
        try {
          tripId = await widget.api.startTrip(role: 'driver');
        } on ApiException catch (e) {
          if (e.status != 404) rethrow;
          setState(() => _notice = SafetyText.noRideWaiting);
          return;
        }
      } else {
        tripId = await widget.api.startTrip(riderConsent: consent);
      }
      final trip = await widget.tripInfo(tripId);
      final both = trip != null && trip.riderConsent && trip.driverConsent;
      // Nothing is recorded unless the rider agreed and the driver has Safe Ride on.
      final micOn = both && await widget.recorder.start(tripId);
      if (micOn) {
        _ride = RideMeta(
          tripId: tripId,
          startedAt: DateTime.now(),
          contentType: widget.recorder.contentType,
          role: _role,
        );
        await _persist();
      }
      _engine =
          (widget.engine ??
          () => SafetyEngine(classifier: KeywordClassifier()))();
      if (micOn) _listening = widget.listen().listen(_onHeard);
      setState(() {
        _tripId = tripId;
        _safePhraseUsed = _live = false;
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
      _endHighCheck();
      _liveTimer?.cancel();
      await _streaming;
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
        if (ride.share == Share.local) {
          _say(SafetyText.keptOnPhone);
        } else {
          final sent = await _sendRecordings();
          if (mounted) {
            _say(
              sent.contains(tripId)
                  ? SafetyText.recordingSent
                  : SafetyText.recordingQueued,
            );
          }
        }
      }
      setState(() {
        _tripId = _last = _ride = null;
        _recording = _warning = _live = false;
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

  /// What leaves the phone only goes up during a ride: local → at end → live.
  void _raise(Share share) {
    final ride = _ride;
    if (ride == null || share.index <= ride.share.index) return;
    ride.share = share;
    _persist();
  }

  /// Emergency: an agent gets the ride so far now, then each new 10-second piece and line.
  void _goLive() {
    final ride = _ride;
    if (ride == null || ride.share == Share.live) return;
    _raise(Share.live);
    widget.recorder.goLive();
    setState(() => _live = true);
    _streamNow();
    _liveTimer = Timer.periodic(_pulse, (_) => _streamNow());
  }

  void _streamNow() {
    final ride = _ride;
    if (ride == null) return;
    _streaming = _streaming.then(
      (_) => syncRide(
        widget.api,
        widget.store,
        ride,
        done: false,
        save: _persist,
      ).catchError((_) {}), // no signal: the next pulse tries again
    );
  }

  /// Sends every ended ride that should leave the phone and hasn't, deletes rides older than 7 days,
  /// and closes rides the app never ended (it was killed). One run at a time. Returns what was sent.
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
        if (!r.ended || r.share == Share.local || r.uploaded) continue;
        try {
          await syncRide(widget.api, widget.store, r, done: true);
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
    if (!_safePhraseUsed && (_phrase?.heardIn(text) ?? false)) {
      _safePhraseUsed = true;
      _sos(); // silent: no dialog, no alarm
      return;
    }
    if (_shout && _helpWords.any((w) => w.heardIn(text))) {
      _sos();
      return;
    }
    switch (d.action) {
      case SafetyAction.warn:
        _mark(Marker(at, 'warning', verdict: d.verdict, text: text));
        setState(() => _warning = true);
      case SafetyAction.high:
        _mark(Marker(at, 'high', verdict: d.verdict, text: text));
        _raise(
          Share.atEnd,
        ); // suspicion is high: the whole ride goes to the team at the end
        _deliver('auto', d); // and the flag goes to an agent at once
        _startHighCheck();
      case SafetyAction.none:
        break;
    }
  }

  /// "Are you okay?" after a high flag, quiet first: buzz every 10 s, Live at 60 s, alarm and
  /// "shout TOLONG" at 120 s.
  void _startHighCheck() {
    var waited = Duration.zero;
    widget.alert?.call(loud: false);
    _highCheck = Timer.periodic(_pulse, (timer) {
      waited += _pulse;
      if (waited == _goLiveAt) _goLive();
      if (waited >= _alarmAt) {
        timer.cancel();
        widget.alert?.call(loud: true);
        setState(() => _shout = true);
      } else {
        widget.alert?.call(loud: false); // another buzz
      }
    });
    _asking = true;
    askAreYouOk(context).then((ok) {
      _asking = false;
      _endHighCheck();
      if (ok == true) _say(SafetyText.okThanks);
      if (ok == false) _sos();
    });
  }

  void _endHighCheck() {
    if (_highCheck == null && !_shout) return;
    _highCheck?.cancel();
    _highCheck = null;
    widget.clearAlert?.call();
    if (mounted && _shout) setState(() => _shout = false);
  }

  /// SOS button, "I need help", "Yes, get help", the safe phrase, or a shout for help.
  Future<void> _sos() async {
    if (_asking) Navigator.of(context).pop(); // close "Are you okay?"
    _endHighCheck();
    _mark(Marker(_sinceStart, 'sos', verdict: _last?.verdict));
    _goLive();
    if (await _deliver('sos', _last) && mounted) _say(SafetyText.helpSent);
  }

  Future<void> _editSafePhrase() async {
    final saved = await askSafePhrase(context, _phrase?.phrase ?? '');
    if (saved == null || !mounted) return;
    await widget.store.setSafePhrase(saved);
    setState(() => _phrase = SafePhrase(saved));
    _say(SafetyText.safePhraseSaved);
  }

  /// "Report driver" / "Report passenger": the team reviews the whole ride after it ends.
  Future<void> _reportOther() async {
    setState(() => _warning = false);
    _mark(Marker(_sinceStart, 'manual_unsafe', verdict: _last?.verdict));
    _raise(Share.atEnd);
    _deliver('manual_unsafe', _last);
    final help = await askNeedHelp(context, driver: _driver);
    if (help == true) {
      await _sos();
    } else if (help == false && mounted) {
      _say(SafetyText.reportThanks);
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
                  if (_shout)
                    MaterialBanner(
                      backgroundColor: GoSafeColors.highTint,
                      leading: const Icon(Icons.campaign),
                      content: const Text(SafetyText.shout),
                      actions: const [SizedBox.shrink()],
                    ),
                  if (_live)
                    MaterialBanner(
                      backgroundColor: GoSafeColors.highTint,
                      leading: const Icon(Icons.support_agent),
                      content: const Text(SafetyText.live),
                      actions: const [SizedBox.shrink()],
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
                          onPressed: _reportOther,
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
                        widget.describe == null
                            ? 'Heard (temporary speech-to-text)'
                            : 'Heard (Whisper on the laptop · classifier label)',
                        style: text.labelMedium,
                      ),
                    ),
                    for (final (i, (_, t)) in _heard.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text.rich(
                          TextSpan(
                            text: t,
                            children: [
                              if (widget.describe?.call(t) case final note?)
                                TextSpan(
                                  text: '   $note',
                                  style: text.labelMedium?.copyWith(
                                    color: GoSafeColors.muted,
                                  ),
                                ),
                            ],
                          ),
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
                          // shortcut: one app for both phones in the demo; in production they're two apps.
                          // Fixed width: the app font loads after first layout, which would wrap "Driver".
                          SizedBox(
                            width: 320,
                            child: SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: 'rider',
                                  label: Text('Rider'),
                                  icon: Icon(Icons.person),
                                ),
                                ButtonSegment(
                                  value: 'driver',
                                  label: Text('Driver'),
                                  icon: Icon(Icons.two_wheeler),
                                ),
                              ],
                              selected: {_role},
                              onSelectionChanged: (v) =>
                                  setState(() => _role = v.single),
                            ),
                          ),
                          // Both rider and driver have their own: on a motorbike either may be unable to tap.
                          ListTile(
                            leading: const Icon(Icons.record_voice_over),
                            title: const Text(SafetyText.safePhraseTitle),
                            subtitle: Text(
                              _phrase == null
                                  ? 'Not set'
                                  : '“${_phrase!.phrase}”',
                            ),
                            trailing: TextButton(
                              onPressed: _editSafePhrase,
                              child: Text(_phrase == null ? 'Set' : 'Change'),
                            ),
                          ),
                          if (_driver)
                            SwitchListTile(
                              title: const Text('Safe Ride'),
                              subtitle: const Text(SafetyText.safeRideSetting),
                              value: _safeRide,
                              onChanged: (v) => setState(() => _safeRide = v),
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
                          onPressed: _reportOther,
                          child: Text(SafetyText.reportButton(driver: _driver)),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: GoSafeColors.sos,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(64),
                          ),
                          onPressed: _sos,
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
