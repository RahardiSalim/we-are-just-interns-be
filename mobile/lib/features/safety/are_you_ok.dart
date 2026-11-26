import 'package:material_ui/material_ui.dart';

const _question = 'Are you OK?';
const _detail = 'GoSafe noticed something that may not be safe. If you need help, a safety agent will contact you.';

/// Blocking prompt for anyone who can safely tap: the rider, or a GoCar driver.
/// Returns true for "I'm OK", false for "I need help", null if dismissed.
Future<bool?> askAreYouOk(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_question),
        content: const Text(_detail),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("I'm OK")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('I need help'),
          ),
        ],
      ),
    );

/// Non-blocking version for a GoRide driver, who can't tap while riding: it never demands an answer.
class AreYouOkBanner extends StatelessWidget {
  const AreYouOkBanner({super.key, required this.onAnswer});

  final void Function(bool ok) onAnswer;

  @override
  Widget build(BuildContext context) => MaterialBanner(
        leading: const Icon(Icons.health_and_safety),
        content: const Text('$_question Answer when you have stopped.'),
        actions: [
          TextButton(onPressed: () => onAnswer(true), child: const Text("I'm OK")),
          TextButton(onPressed: () => onAnswer(false), child: const Text('I need help')),
        ],
      );
}
