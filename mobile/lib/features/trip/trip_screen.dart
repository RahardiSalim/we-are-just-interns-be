import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:material_ui/material_ui.dart';

import '../../engine/safe_phrase.dart';
import '../../engine/safety_engine.dart';
import '../../services/api.dart';
import '../../services/recorder.dart';
import '../../services/ride_store.dart';
import '../../services/ride_sync.dart';
import '../../theme.dart';
import 'gojek_ui.dart';
import 'ride_map.dart';
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

/// The ride sheet: how far it opens (share of the screen), as in the Gojek app.
const _sheetMin = 0.3;
const _sheetStart = 0.55;
const _sheetMax = 1.0; // slid all the way up, the sheet covers the whole map

/// shortcut: GoSafe has no order details yet (driver, route, fare), so the ride screen shows
/// Gojek's sample order, with a plate and map made up per ride. Swap in the GoJek order once
/// `POST /trips` carries it.
const _demoRide = (
  driver: 'Galih Pambudi',
  trips: '120 total trips',
  rating: '4.5',
  pickup: 'Hotel Grandhika',
  dropoff: 'Hotel Grand Kemang',
  distance: '25 min • 15km',
  fare: 'Rp85.000',
);

/// A Jakarta-style plate made up from the ride ("B 1060 JEK"), the same for the same ride.
String _plate(int seed) {
  final r = math.Random(seed);
  final letters = List.generate(
    3,
    (_) => String.fromCharCode(65 + r.nextInt(26)),
  ).join();
  return 'B ${1000 + r.nextInt(9000)} $letters';
}

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
    this.autoStart = false,
    this.role = 'rider',
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

  /// Open straight on the ride (the GoJek order) and ask for consent at once, with no home screen.
  /// The app does; tests leave it off to drive the home screen.
  final bool autoStart;

  /// 'rider' or 'driver'. shortcut: one app for both phones in the demo.
  final String role;

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  // shortcut: the rider/driver switch is for the demo; in production they're two apps.
  late String _role = widget.role;
  Stream<double>? _micLevel; // the microphone's loudness while recording
  bool _safeRide = true; // the driver's setting: record my rides
  String? _tripId;
  bool _recording = false;
  bool? _driverSafeRide;
  bool? _backendUp;
  bool _busy = false;
  // The safety pop-up on screen (a warning, "Are you okay?", "We've reported…"): one at a time,
  // a newer one replaces it. [_popup] counts them, so a replaced one's answer is ignored.
  int _popup = 0;
  bool _popupOpen = false;
  bool _sosOffline = false;
  bool _safePhraseUsed = false;
  late SafePhrase? _phrase = widget.safePhrase; // the user's own once loaded
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
  final _sheet = DraggableScrollableController();
  final _mapView = TransformationController(); // the map's pan and zoom
  double _extent = _sheetStart;

  bool get _driver => _role == 'driver';

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRide();
      });
    }
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
    _sheet.dispose();
    _mapView.dispose();
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
        _micLevel = micOn ? widget.recorder.level : null;
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
        _recording = _live = false;
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
    // The ladder (mobile/README.md): each repeat does more with the recording.
    switch (d.action) {
      case SafetyAction.warn:
        _mark(Marker(at, 'warning', verdict: d.verdict, text: text));
        // 1st: stays on the phone. 2nd: the whole recording goes to the safety team at the end.
        if (d.nth >= 2) _raise(Share.atEnd);
        // A warning never replaces an open "Are you okay?": that question matters more.
        if (_highCheck != null || _shout) break;
        _showPopup(() => askWarning(context, again: d.nth >= 2)).then((r) {
          if (r.$1 && r.$2 == true) _reportOther();
        });
      case SafetyAction.high:
        _mark(Marker(at, 'high', verdict: d.verdict, text: text));
        _raise(Share.atEnd); // the whole ride goes to the team at the end
        if (d.nth >= 3) {
          _sos(announce: true); // 3rd: an SOS on the rider's behalf, Live
          return;
        }
        _deliver(
          'auto',
          d,
        ); // the flag reaches an agent at once (a repeat joins the same case)
        if (d.nth == 2) _goLive(); // 2nd: an agent can listen now
        _startHighCheck(again: d.nth == 2);
      case SafetyAction.none:
        break;
    }
  }

  /// "Are you okay?" after a high flag, quiet first: buzz every 10 s, Live at 60 s, alarm and
  /// "shout TOLONG" at 120 s.
  void _startHighCheck({bool again = false}) {
    _endHighCheck();
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
    _showPopup(() => askAreYouOk(context, again: again)).then((r) {
      final (current, ok) = r;
      // Replaced by a newer pop-up, which handles the check.
      if (!current) return;
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

  /// Shows a safety pop-up, closing any open one first. Returns whether it was still the current
  /// one when it closed (a replaced pop-up's answer means nothing) and the answer.
  Future<(bool, T?)> _showPopup<T>(Future<T?> Function() open) async {
    _closePopup();
    final me = ++_popup;
    _popupOpen = true;
    final answer = await open();
    if (me != _popup) return (false, null);
    _popupOpen = false;
    return (true, answer);
  }

  void _closePopup() {
    if (!_popupOpen) return;
    _popup++; // the closing one must not act
    _popupOpen = false;
    Navigator.of(context).pop();
  }

  /// SOS button, "I need help", "Yes, get help", the safe phrase, or a shout for help.
  /// [announce]: sent on the person's behalf (the 3rd high flag), so say so in a pop-up.
  Future<void> _sos({bool announce = false}) async {
    if (_tripId == null) return; // the ride is still starting
    _closePopup();
    _endHighCheck();
    _mark(Marker(_sinceStart, 'sos', verdict: _last?.verdict));
    _goLive();
    if (!await _deliver('sos', _last) || !mounted) return;
    if (announce) {
      _showPopup(() => showHelpSent(context));
    } else {
      _say(SafetyText.helpSent);
    }
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
    if (_tripId == null) return;
    _mark(Marker(_sinceStart, 'manual_unsafe', verdict: _last?.verdict));
    _raise(Share.atEnd);
    _deliver('manual_unsafe', _last);
    final (current, help) = await _showPopup(
      () => askNeedHelp(context, driver: _driver),
    );
    if (!current) return;
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

    // Alerts sit at the top, never over the bottom buttons (nothing may cover SOS).
    List<Widget> alerts() => [
      if (_sosOffline)
        AlertCard(
          icon: Icons.signal_cellular_off_rounded,
          color: GoSafeColors.high,
          tint: GoSafeColors.highTint,
          text: SafetyText.sosOffline,
          actions: [
            if (widget.dial != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: GoSafeColors.high,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => widget.dial!('112'),
                child: const Text(SafetyText.call112),
              ),
          ],
        ),
      if (_shout)
        const AlertCard(
          icon: Icons.campaign_rounded,
          color: GoSafeColors.high,
          tint: GoSafeColors.highTint,
          text: SafetyText.shout,
        ),
      if (_live)
        const AlertCard(
          icon: Icons.support_agent_rounded,
          color: GoSafeColors.high,
          tint: GoSafeColors.highTint,
          text: SafetyText.live,
        ),
      if (_message != null)
        AlertCard(
          icon: Icons.favorite_rounded,
          text: _message!,
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _message = null),
          ),
        ),
      if (_notice != null)
        AlertCard(
          icon: Icons.info_rounded,
          color: GoSafeColors.high,
          tint: GoSafeColors.highTint,
          text: _notice!,
        ),
    ];

    if (onRide || widget.autoStart) {
      return Scaffold(
        backgroundColor: GoSafeColors.mapBg,
        body: _rideView(text, alerts()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user_rounded,
                color: GoSafeColors.brand,
                size: 20,
              ),
            ),
            const Text('GoSafe'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (_backendUp) {
                        true => GoSafeColors.brand,
                        false => GoSafeColors.high,
                        null => GoSafeColors.muted,
                      },
                    ),
                  ),
                  Text(
                    switch (_backendUp) {
                      null => 'Checking…',
                      true => 'Online',
                      false => 'Offline',
                    },
                    style: GoSafeType.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: GoSafeColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // Everything scrolls except the Start ride button.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 16),
                children: [
                  ...alerts(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Image.asset(
                      'assets/illustrations/listening.png',
                      height: 180,
                      semanticLabel: 'GoSafe listens during your ride',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      spacing: 8,
                      children: [
                        Text(
                          'Ride with peace of mind',
                          style: text.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          'GoSafe listens for trouble during your ride and gets help fast if you need it.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: GoSafeColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // shortcut: one app for both phones in the demo; in production they're two apps.
                  // Fixed width: the app font loads after first layout, which would wrap "Driver".
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        width: 320,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'rider',
                              label: Text('Rider'),
                              icon: Icon(Icons.person_rounded),
                            ),
                            ButtonSegment(
                              value: 'driver',
                              label: Text('Driver'),
                              icon: Icon(Icons.two_wheeler_rounded),
                            ),
                          ],
                          selected: {_role},
                          onSelectionChanged: (v) =>
                              setState(() => _role = v.single),
                        ),
                      ),
                    ),
                  ),
                  // Both rider and driver have their own: on a motorbike either may be unable to tap.
                  GoCard(
                    child: Row(
                      spacing: 12,
                      children: [
                        const CircleIcon(Icons.record_voice_over_rounded),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                SafetyText.safePhraseTitle,
                                style: text.titleSmall,
                              ),
                              Text(
                                _phrase == null
                                    ? 'Not set'
                                    : '“${_phrase!.phrase}”',
                                style: text.bodySmall?.copyWith(
                                  color: GoSafeColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            side: const BorderSide(
                              color: GoSafeColors.brandStrong,
                            ),
                            foregroundColor: GoSafeColors.brandDeep,
                          ),
                          onPressed: _editSafePhrase,
                          child: Text(_phrase == null ? 'Set' : 'Change'),
                        ),
                      ],
                    ),
                  ),
                  if (_driver)
                    GoCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SwitchListTile(
                        secondary: const CircleIcon(
                          Icons.verified_user_rounded,
                        ),
                        title: const Text('Safe Ride'),
                        subtitle: const Text(SafetyText.safeRideSetting),
                        value: _safeRide,
                        onChanged: (v) => setState(() => _safeRide = v),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                color: GoSafeColors.canvas,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: GoSafeShadow.high,
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  padding: const EdgeInsets.only(left: 24, right: 8),
                ),
                onPressed: _busy ? null : _startRide,
                child: Row(
                  children: [
                    const Expanded(child: Text('Start ride')),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: GoSafeColors.brandStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The ride, laid out like Gojek's ride screen: the map behind, and a white sheet the rider drags
  /// up to read everything or down to see the map. Alerts sit at the top of the sheet; SOS is in the
  /// first screenful, beside the listening signal.
  Widget _rideView(TextTheme text, List<Widget> alerts) => LayoutBuilder(
    builder: (context, box) {
      final h = box.maxHeight;
      return Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: h * (1 - _sheetMin) + 24,
            child: RideMap(
              view: _mapView,
              seed: _seed,
              // The route sits in the part of the map the sheet leaves open when the ride starts.
              focus: Rect.fromLTRB(
                0.15,
                0.1,
                0.85,
                ((1 - _sheetStart) * h - 70) / (h * (1 - _sheetMin) + 24),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: h * _extent + 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const MapButton(Icons.arrow_back_rounded, tooltip: 'Back'),
                // Navigate: back to the whole route, as it was when the ride started.
                MapButton(
                  Icons.near_me_rounded,
                  color: GoSafeColors.mapDot,
                  tooltip: 'Show my route',
                  onPressed: () {
                    _mapView.value = Matrix4.identity();
                    _sheet.animateTo(
                      _sheetStart,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ],
            ),
          ),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              setState(() => _extent = n.extent);
              return false;
            },
            child: DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _sheetStart,
              minChildSize: _sheetMin,
              maxChildSize: _sheetMax,
              snap: true,
              snapSizes: const [_sheetStart],
              // Drag with a finger, and with a mouse or trackpad too (Flutter allows only touch by
              // default), so the sheet also slides in the browser preview.
              builder: (context, scroll) => ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                child: SingleChildScrollView(
                  controller: scroll,
                  child: Listener(
                    onPointerSignal: (e) => _wheel(e, scroll, h),
                    child: Stack(
                      children: [
                        const EtaBanner(
                          text: 'Your driver will arrive in',
                          highlight: '5 min',
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 56),
                          padding: const EdgeInsets.only(top: 10, bottom: 24),
                          decoration: const BoxDecoration(
                            color: GoSafeColors.canvas,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          child: _rideSheet(text, alerts),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  /// A mouse wheel or trackpad over the sheet moves the sheet first, as a finger drag does: up
  /// until it covers the map, then the cards scroll; back down, the cards return to the top
  /// first, then the sheet lowers. Without this the cards scroll inside a half-open sheet.
  void _wheel(PointerSignalEvent e, ScrollController scroll, double h) {
    if (e is! PointerScrollEvent || !_sheet.isAttached) return;
    final dy = e.scrollDelta.dy;
    final size = _sheet.size;
    final atTop = !scroll.hasClients || scroll.offset <= 0;
    final grow = dy > 0 && size < _sheetMax;
    final shrink = dy < 0 && atTop && size > _sheetMin;
    if (!grow && !shrink) return; // the cards scroll as usual
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _sheet.jumpTo((size + dy / h).clamp(_sheetMin, _sheetMax));
    });
  }

  /// The same ride always gets the same plate and map.
  int get _seed => (_tripId ?? '').hashCode & 0x7fffffff;

  Widget _rideSheet(TextTheme text, List<Widget> alerts) {
    const ride = _demoRide;
    final onRide = _tripId != null;
    final title = text.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: GoSafeColors.handle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        ...alerts,
        // Plate number, call and chat.
        GoCard(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            spacing: 12,
            children: [
              Expanded(child: Text(onRide ? _plate(_seed) : '…', style: title)),
              const RoundAction(Icons.call_rounded, tooltip: 'Call'),
              const RoundAction(Icons.chat_rounded, tooltip: 'Chat'),
            ],
          ),
        ),
        // GoRide: pickup and drop-off joined by dots.
        GoCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 16,
                children: [
                  const CircleIcon(
                    Icons.moped_rounded,
                    color: Colors.white,
                    tint: GoSafeColors.rideIcon,
                    size: 28,
                  ),
                  Text('GoRide', style: title),
                ],
              ),
              const DottedLine(),
              InfoRow(
                icon: Icons.arrow_upward_rounded,
                color: GoSafeColors.rideIcon,
                label: 'Pickup location',
                value: ride.pickup,
              ),
              DotConnector(note: ride.distance),
              InfoRow(
                icon: Icons.radio_button_checked_rounded,
                color: GoSafeColors.dropoff,
                label: 'Drop off location',
                value: ride.dropoff,
                trailing: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    side: const BorderSide(
                      color: GoSafeColors.ride,
                      width: 1.5,
                    ),
                    foregroundColor: GoSafeColors.ride,
                  ),
                  onPressed: () {},
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ),
        // GoPay.
        GoCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            spacing: 16,
            children: [
              const CircleIcon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                tint: GoSafeColors.gopay,
                size: 28,
              ),
              Expanded(child: Text('GoPay', style: text.titleSmall)),
              Text(ride.fare, style: title),
            ],
          ),
        ),
        // GoSafe: the small speaker with its live signal, and SOS beside it.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Expanded(
                  child: GoCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: ListeningLine(
                      recording: _recording,
                      level: _micLevel,
                      text: _recording
                          ? 'Recording on. Only shared if something serious happens.'
                          : 'Not recording this ride. SOS still works.',
                    ),
                  ),
                ),
                SosButton(onPressed: _sos),
              ],
            ),
          ),
        ),
        // The driver: name, trips, Safe Ride, photo with rating.
        GoCard(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(ride.driver, style: title),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(
                          ride.trips,
                          color: GoSafeColors.muted,
                          border: GoSafeColors.lineSoft,
                        ),
                        Pill(
                          _driverSafeRide == true
                              ? 'Your driver has Safe Ride on'
                              : "Your driver hasn't turned on Safe Ride",
                          icon: _driverSafeRide == true
                              ? Icons.verified_user_rounded
                              : Icons.shield_outlined,
                          color: _driverSafeRide == true
                              ? GoSafeColors.brandDeep
                              : GoSafeColors.muted,
                          tint: _driverSafeRide == true
                              ? GoSafeColors.brandTint
                              : GoSafeColors.canvas,
                          border: _driverSafeRide == true
                              ? GoSafeColors.brandTint
                              : GoSafeColors.lineSoft,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              DriverPhoto(asset: 'assets/ride/driver.png', rating: ride.rating),
            ],
          ),
        ),
        // Report and End ride; once the ride ended, start the next one here.
        GoCard(
          padding: const EdgeInsets.all(12),
          child: !onRide
              ? FilledButton(
                  onPressed: _busy ? null : _startRide,
                  child: const Text('Start ride'),
                )
              : Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.flag_rounded),
                        onPressed: _reportOther,
                        label: Text(SafetyText.reportButton(driver: _driver)),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _endRide,
                      child: const Text('End ride'),
                    ),
                  ],
                ),
        ),
        // The home screen is gone in the app, so the safe phrase is set here.
        if (widget.autoStart)
          GoCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              spacing: 12,
              children: [
                const CircleIcon(Icons.record_voice_over_rounded, size: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(SafetyText.safePhraseTitle, style: text.titleSmall),
                      Text(
                        _phrase == null ? 'Not set' : '“${_phrase!.phrase}”',
                        style: text.bodySmall?.copyWith(
                          color: GoSafeColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: const BorderSide(
                      color: GoSafeColors.ride,
                      width: 1.5,
                    ),
                    foregroundColor: GoSafeColors.ride,
                  ),
                  onPressed: _editSafePhrase,
                  child: Text(_phrase == null ? 'Set' : 'Change'),
                ),
              ],
            ),
          ),
        // What was heard is for the safety team, not the rider. Shown only in the developer mode
        // (DEV_ML), to check the classifier.
        if (widget.describe != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Heard on this ride',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              widget.describe == null
                  ? 'Heard (temporary speech-to-text)'
                  : 'Heard (Whisper on the laptop · classifier label)',
              style: text.labelMedium?.copyWith(color: GoSafeColors.muted),
            ),
          ),
          if (_heard.isEmpty)
            GoCard(
              child: Text(
                'Listening… what people say during the ride shows up here.',
                style: text.bodySmall?.copyWith(color: GoSafeColors.muted),
              ),
            ),
          for (final (i, (_, t)) in _heard.indexed)
            GoCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text.rich(
                TextSpan(
                  text: t,
                  children: [
                    if (widget.describe?.call(t) case final note?)
                      TextSpan(
                        text: '   $note',
                        style: text.labelMedium?.copyWith(
                          color: GoSafeColors.brandDeep,
                        ),
                      ),
                  ],
                ),
                key: ValueKey('heard-$i'),
                style: text.bodySmall,
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Help us to improve',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: const [
              HelpCard(
                label: 'Redesign report',
                title: 'Do you like our redesign?',
                color: GoSafeColors.helpBlue,
                asset: 'assets/ride/mascot_run.png',
              ),
              SizedBox(width: 12),
              HelpCard(
                label: 'Safety report',
                title: 'How safe did you feel?',
                color: GoSafeColors.helpOrange,
                asset: 'assets/ride/mascot_wave.png',
              ),
              SizedBox(width: 12),
              HelpCard(
                label: 'GoSafe tips',
                title: 'Set your safe phrase',
                color: GoSafeColors.rideIcon,
                asset: 'assets/ride/mascot_cool.png',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
