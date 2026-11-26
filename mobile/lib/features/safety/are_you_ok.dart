import 'package:material_ui/material_ui.dart';

import '../../engine/safe_phrase.dart';
import '../../theme.dart';

/// Short and caring, never alarming. The words people see when something seems wrong.
abstract final class SafetyText {
  static const consentTitle = 'Keep this ride safe?';
  static const consentBody =
      "We'd like to record audio during this ride. "
      "It's only reviewed if something seems wrong, and it's deleted after 7 days.";
  static const consentYes = 'Yes, record';
  static const consentNo = 'Not now';

  static const warning =
      'Hey, this conversation seems to be getting uncomfortable. '
      "Let's keep it kind. If you feel unsafe, we're right here.";
  static const warningAgain =
      'This is the second time the conversation has turned uncomfortable. '
      "We'll share this ride's recording with our safety team when it ends. "
      'If you feel unsafe, report it now.';
  static const warningTitle = 'Is everything okay?';
  static const warningAgainTitle = 'This happened again';
  static const warningFine = "I'm fine";
  static const warningReport = 'Report';

  static const askTitle = 'Are you okay?';
  static const askBody =
      "Something didn't sound right, so we've let our safety team know. "
      'Tap if you need help.';
  static const askAlertBody =
      "Something didn't sound right. Tap to tell us you're okay.";
  static const helpSentTitle = 'Help is on the way';
  static const askAgainTitle = 'Are you still okay?';
  static const askAgainBody =
      'It happened again, so our safety team is now following this ride live. '
      'Tap if you need help.';
  static const askOk = "I'm okay";
  static const askHelp = 'I need help';

  static const listeningTitle = 'GoSafe is keeping this ride safe';
  static const listeningBody =
      'Listening during your ride. Recordings are only shared if something seems wrong.';

  static const sosOffline =
      "We can't reach our safety team right now. We'll keep trying. "
      'If you are in danger, call 112.';
  static const call112 = 'Call 112';

  static const recordingSent =
      'Ride ended. The recording was sent to our safety team.';
  static const recordingQueued =
      "Ride ended. We'll send the recording to our safety team as soon as you're online.";
  static const keptOnPhone =
      'Ride ended. Nothing needed checking. The recording stays locked on this phone '
      "for 7 days, then it's deleted.";

  static String reportButton({required bool driver}) =>
      driver ? 'Report passenger' : 'Report driver';
  static const reportThanks =
      "Thanks for telling us. We'll look into it after your ride.";
  static const needHelpBody =
      'Our safety team will review this ride. Do you need help right now?';
  static const needHelpNo = "I'm safe for now";
  static const needHelpYes = 'Yes, get help';
  static const shout =
      "If you're in danger, shout TOLONG. Our safety team is listening.";
  static const live = 'Our safety team is following this ride live.';
  static const safeRideSetting =
      'Record my rides. Only shared if something serious happens.';
  static const noRideWaiting =
      'No ride is waiting for you yet. Ask the rider to start their ride first.';

  static const safePhraseTitle = 'Safe phrase';
  static const safePhraseHint =
      'Say this in a ride to call for help without touching your phone. Pick a normal-sounding '
      "sentence you wouldn't say by chance.";
  static const safePhraseSaved = 'Safe phrase saved. Only you know it.';
  static const safePhrasePrivate =
      'Only you know it. It stays locked on this phone and is never sent.';

  static const helpSent =
      "We're on it. Our safety team will contact you right away.";
  static const reportSent =
      'Thanks for telling us. Our safety team will look into it.';
  static const okThanks =
      "Glad you're okay. We're still here if anything changes.";
}

/// The Gojek bottom sheet every safety pop-up uses: it rises from the bottom edge, the page behind
/// fades, a handle on top, an icon in a tinted circle beside the title, the message, then the
/// buttons stacked full width. Like the consent prompt.
Future<T?> showGoSheet<T>(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required Color tint,
  required String title,
  required String body,
  required List<Widget> Function(BuildContext context) actions,
  bool dismissible = false,
}) => showModalBottomSheet<T>(
  context: context,
  isDismissible: dismissible,
  enableDrag: dismissible,
  barrierColor: Colors.black.withValues(alpha: 0.5),
  backgroundColor: GoSafeColors.canvas,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: GoSafeColors.handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            spacing: 12,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, color: color),
              ),
              Expanded(child: Text(title, style: GoSafeType.titleSmall)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: GoSafeType.bodyModerate.copyWith(color: GoSafeColors.muted),
          ),
          const SizedBox(height: 24),
          ...actions(context),
        ],
      ),
    ),
  ),
);

Widget _primary(
  BuildContext context,
  String text,
  Object? value,
  Color color,
) => FilledButton(
  style: FilledButton.styleFrom(backgroundColor: color),
  onPressed: () => Navigator.pop(context, value),
  child: Text(text),
);

Widget _secondary(
  BuildContext context,
  String text,
  Object? value,
  Color color,
) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: TextButton(
    style: TextButton.styleFrom(foregroundColor: color),
    onPressed: () => Navigator.pop(context, value),
    child: Text(text),
  ),
);

/// After "Report": true for "Yes, get help" (an SOS), false for "I'm safe for now".
Future<bool?> askNeedHelp(BuildContext context, {required bool driver}) =>
    showGoSheet<bool>(
      context,
      icon: Icons.flag_rounded,
      color: GoSafeColors.unsafe,
      tint: GoSafeColors.warnTint,
      title: driver
          ? "We've reported this passenger"
          : "We've reported this driver",
      body: SafetyText.needHelpBody,
      actions: (c) => [
        _primary(c, SafetyText.needHelpYes, true, GoSafeColors.sos),
        _secondary(c, SafetyText.needHelpNo, false, GoSafeColors.ride),
      ],
    );

/// The warning, 1st or 2nd ([again]) on the ride. True for "Report"; false or null (swiped away)
/// for "I'm fine".
Future<bool?> askWarning(BuildContext context, {bool again = false}) =>
    showGoSheet<bool>(
      context,
      icon: Icons.volunteer_activism_rounded,
      color: GoSafeColors.unsafe,
      tint: GoSafeColors.warnTint,
      title: again ? SafetyText.warningAgainTitle : SafetyText.warningTitle,
      body: again ? SafetyText.warningAgain : SafetyText.warning,
      dismissible: true,
      actions: (c) => [
        _primary(c, SafetyText.warningFine, false, GoSafeColors.ride),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: GoSafeColors.high,
              side: const BorderSide(color: GoSafeColors.high, width: 1.5),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text(SafetyText.warningReport),
          ),
        ),
      ],
    );

/// Returns true for "I'm okay", false for "I need help".
/// [again]: the 2nd high flag on the ride, when the ride has gone Live.
Future<bool?> askAreYouOk(BuildContext context, {bool again = false}) =>
    showGoSheet<bool>(
      context,
      icon: Icons.favorite_rounded,
      color: GoSafeColors.high,
      tint: GoSafeColors.highTint,
      title: again ? SafetyText.askAgainTitle : SafetyText.askTitle,
      body: again ? SafetyText.askAgainBody : SafetyText.askBody,
      actions: (c) => [
        _primary(c, SafetyText.askHelp, false, GoSafeColors.high),
        _secondary(c, SafetyText.askOk, true, GoSafeColors.ride),
      ],
    );

/// After an SOS sent on the person's behalf (the 3rd high flag): help is coming.
Future<void> showHelpSent(BuildContext context) => showGoSheet<void>(
  context,
  icon: Icons.support_agent_rounded,
  color: GoSafeColors.high,
  tint: GoSafeColors.highTint,
  title: SafetyText.helpSentTitle,
  body: SafetyText.helpSent,
  dismissible: true,
  actions: (c) => [_primary(c, 'OK', null, GoSafeColors.ride)],
);

/// The consent prompt, shown when the ride starts. Only the rider sees it:
/// the driver chose in their own settings (that choice is their Safe Ride badge).
Future<bool> askConsent(BuildContext context) async =>
    await showGoSheet<bool>(
      context,
      icon: Icons.mic_rounded,
      color: GoSafeColors.ride,
      tint: GoSafeColors.brandTint,
      title: SafetyText.consentTitle,
      body: SafetyText.consentBody,
      actions: (c) => [
        _primary(c, SafetyText.consentYes, true, GoSafeColors.ride),
        _secondary(c, SafetyText.consentNo, false, GoSafeColors.ride),
      ],
    ) ??
    false;

/// Asks for a safe phrase, in the same Gojek bottom sheet as the other pop-ups. Returns it
/// trimmed, or null if cancelled. The sheet rises above the keyboard.
Future<String?> askSafePhrase(BuildContext context, String current) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // so it can move up with the keyboard
      barrierColor: Colors.black.withValues(alpha: 0.5),
      backgroundColor: GoSafeColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _SafePhraseSheet(current: current),
    );

class _SafePhraseSheet extends StatefulWidget {
  const _SafePhraseSheet({required this.current});
  final String current;

  @override
  State<_SafePhraseSheet> createState() => _SafePhraseSheetState();
}

class _SafePhraseSheetState extends State<_SafePhraseSheet> {
  late final _text = TextEditingController(text: widget.current)
    ..addListener(() => setState(() => _problem = null));
  String? _problem;

  int get _words => _text.text.trim().isEmpty
      ? 0
      : _text.text.trim().split(RegExp(r'\s+')).length;

  void _save() {
    final phrase = _text.text.trim();
    final problem = SafePhrase.problem(phrase);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, phrase);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: GoSafeColors.handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              spacing: 12,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: GoSafeColors.brandTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.record_voice_over_rounded,
                    color: GoSafeColors.ride,
                  ),
                ),
                const Expanded(
                  child: Text(
                    SafetyText.safePhraseTitle,
                    style: GoSafeType.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              SafetyText.safePhraseHint,
              style: GoSafeType.bodyModerate.copyWith(
                color: GoSafeColors.muted,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: GoSafeType.bodyModerate.copyWith(color: GoSafeColors.ink),
              cursorColor: GoSafeColors.ride,
              decoration: InputDecoration(
                hintText: 'Pak, nanti lewat jalan biasa aja ya',
                hintStyle: GoSafeType.bodyModerate.copyWith(
                  color: GoSafeColors.label,
                ),
                filled: true,
                fillColor: GoSafeColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                prefixIcon: const Icon(
                  Icons.format_quote_rounded,
                  color: GoSafeColors.label,
                ),
                border: _border(GoSafeColors.lineSoft),
                enabledBorder: _border(GoSafeColors.lineSoft),
                focusedBorder: _border(GoSafeColors.ride, 1.5),
                errorBorder: _border(GoSafeColors.high, 1.5),
                focusedErrorBorder: _border(GoSafeColors.high, 1.5),
                errorText: _problem,
                errorMaxLines: 2,
                // Live count against the 4 to 12 words the phrase needs.
                helperText: '$_words of 4–12 words',
                helperStyle: GoSafeType.caption.copyWith(
                  color: _words >= 4 && _words <= 12
                      ? GoSafeColors.brandDeep
                      : GoSafeColors.label,
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 16,
                  color: GoSafeColors.label,
                ),
                Expanded(
                  child: Text(
                    SafetyText.safePhrasePrivate,
                    style: GoSafeType.caption.copyWith(
                      color: GoSafeColors.label,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: GoSafeColors.ride),
              onPressed: _save,
              child: const Text('Save'),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: GoSafeColors.ride),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
