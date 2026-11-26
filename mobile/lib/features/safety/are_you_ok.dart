import 'package:material_ui/material_ui.dart';

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
  static const warningFine = "I'm fine";
  static const warningReport = 'Report';

  static const askTitle = 'Are you okay?';
  static const askBody =
      "Something didn't sound right, so we've let our safety team know. "
      'Tap if you need help.';
  static const askAlertBody =
      "Something didn't sound right. Tap to tell us you're okay.";
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

  static const helpSent =
      "We're on it. Our safety team will contact you right away.";
  static const reportSent =
      'Thanks for telling us. Our safety team will look into it.';
  static const okThanks =
      "Glad you're okay. We're still here if anything changes.";
}

/// After a report: true for "Yes, get help", false for "I'm safe for now", null if dismissed.
Future<bool?> askNeedHelp(BuildContext context, {required bool driver}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.flag, color: GoSafeColors.unsafe),
        title: Text(
          driver
              ? "We've reported this passenger"
              : "We've reported this driver",
        ),
        content: const Text(SafetyText.needHelpBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(SafetyText.needHelpNo),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GoSafeColors.sos),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(SafetyText.needHelpYes),
          ),
        ],
      ),
    );

/// Returns true for "I'm okay", false for "I need help", null if dismissed.
Future<bool?> askAreYouOk(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    icon: const Icon(Icons.favorite, color: GoSafeColors.high),
    title: const Text(SafetyText.askTitle),
    content: const Text(SafetyText.askBody),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text(SafetyText.askOk),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: GoSafeColors.high),
        onPressed: () => Navigator.pop(context, false),
        child: const Text(SafetyText.askHelp),
      ),
    ],
  ),
);

/// The consent prompt, shown when the ride starts. Only the rider sees it:
/// the driver chose in their own settings (that choice is their Safe Ride badge).
Future<bool> askConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.mic, color: GoSafeColors.brand),
        title: const Text(SafetyText.consentTitle),
        content: const Text(SafetyText.consentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(SafetyText.consentNo),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(SafetyText.consentYes),
          ),
        ],
      ),
    ) ??
    false;
