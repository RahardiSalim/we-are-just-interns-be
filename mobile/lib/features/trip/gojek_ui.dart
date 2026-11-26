import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// Gojek-style building blocks for the ride screen (contracts/DESIGN.md, Asphalt + Brand Book 2019).

/// White card, radius 20 (as in the Gojek ride screen), Asphalt "low" elevation (light from straight above: a soft, even shadow).
class GoCard extends StatelessWidget {
  const GoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? GoSafeColors.canvas,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: GoSafeColors.lineSoft),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

/// A small rounded tag, like "120 total trips" on the Gojek driver card.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.icon,
    this.color = GoSafeColors.ink,
    this.tint = GoSafeColors.canvas,
    this.border = GoSafeColors.line,
  });

  final String text;
  final IconData? icon;
  final Color color;
  final Color tint;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (icon != null) Icon(icon, size: 14, color: color),
        Flexible(
          child: Text(
            text,
            style: GoSafeType.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The dotted rule under a Gojek card title.
class DottedLine extends StatelessWidget {
  const DottedLine({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (_, c) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < (c.maxWidth / 6).floor(); i++)
            Container(width: 2, height: 2, color: GoSafeColors.line),
        ],
      ),
    ),
  );
}

/// A row like "Pickup location / Hotel Grandhika": coloured circle icon, small label, bold value.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 12,
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoSafeType.bodySmall.copyWith(
                color: GoSafeColors.label,
                height: 1.2,
              ),
            ),
            Text(
              value,
              style: GoSafeType.titleTiny.copyWith(
                color: GoSafeColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// The dotted connector between two InfoRows, with an optional note beside it ("25 min • 15km").
class DotConnector extends StatelessWidget {
  const DotConnector({super.key, this.note});

  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 13, top: 4, bottom: 4),
    child: Row(
      spacing: 25,
      children: [
        Column(
          spacing: 3,
          children: [
            for (var i = 0; i < 5; i++)
              Container(width: 2, height: 3, color: GoSafeColors.line),
          ],
        ),
        if (note != null)
          Text(
            note!,
            style: GoSafeType.caption.copyWith(color: GoSafeColors.ink),
          ),
      ],
    ),
  );
}

/// An icon in a tinted circle: the brand book's icons are built on circles.
class CircleIcon extends StatelessWidget {
  const CircleIcon(
    this.icon, {
    super.key,
    this.color = GoSafeColors.brandStrong,
    this.tint = GoSafeColors.brandTint,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
    child: Icon(icon, color: color, size: size * 0.55),
  );
}

/// Asphalt alert: tint of the meaning colour, an icon at the start, at the top of the screen.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.icon,
    required this.text,
    this.tint = GoSafeColors.surface,
    this.color = GoSafeColors.ink,
    this.actions = const [],
    this.trailing,
  });

  final IconData icon;
  final String text;
  final Color tint;
  final Color color;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => GoCard(
    color: tint,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            CircleIcon(icon, color: color, tint: GoSafeColors.canvas, size: 36),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  text,
                  style: GoSafeType.bodySmall.copyWith(color: GoSafeColors.ink),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ),
      ],
    ),
  );
}

/// Green circle with a white icon: the call and chat buttons on the plate card.
class RoundAction extends StatelessWidget {
  const RoundAction(
    this.icon, {
    super.key,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: GoSafeColors.ride,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    ),
  );
}

/// White circle floating on the map: back arrow, navigate.
class MapButton extends StatelessWidget {
  const MapButton(
    this.icon, {
    super.key,
    required this.tooltip,
    this.onPressed,
    this.color = GoSafeColors.ink,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: GoSafeShadow.low,
      ),
      child: Material(
        color: GoSafeColors.canvas,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    ),
  );
}

/// The green strip above the sheet: "Your driver will arrive in [5 min]".
class EtaBanner extends StatelessWidget {
  const EtaBanner({super.key, required this.text, required this.highlight});

  final String text;
  final String highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
    decoration: const BoxDecoration(
      color: GoSafeColors.ride,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Row(
      spacing: 12,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: GoSafeColors.canvas,
            shape: BoxShape.circle,
            border: Border.all(color: GoSafeColors.helpOrange, width: 3),
          ),
          child: const Icon(
            Icons.keyboard_double_arrow_right_rounded,
            color: GoSafeColors.ride,
            size: 20,
          ),
        ),
        Flexible(
          child: Text(
            text,
            style: GoSafeType.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            highlight,
            style: GoSafeType.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The other person's photo in a rounded square with the rating badge over its bottom edge: the
/// driver's photo ([asset]) on the rider's phone, or a stand-in picture ([emoji]) for the passenger.
class DriverPhoto extends StatelessWidget {
  const DriverPhoto({
    super.key,
    this.asset,
    this.emoji,
    required this.rating,
    this.label = 'Driver photo',
  }) : assert(asset != null || emoji != null);

  final String? asset;
  final String? emoji;
  final String rating;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 74,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: asset != null
              ? Image.asset(
                  asset!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  semanticLabel: label,
                )
              : Container(
                  width: 64,
                  height: 64,
                  color: GoSafeColors.brandTint,
                  alignment: Alignment.center,
                  child: Text(
                    emoji!,
                    semanticsLabel: label,
                    style: const TextStyle(fontSize: 36),
                  ),
                ),
        ),
        Positioned(
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: GoSafeColors.canvas,
              borderRadius: BorderRadius.circular(999),
              boxShadow: GoSafeShadow.low,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: GoSafeColors.helpOrange,
                ),
                Text(
                  rating,
                  style: GoSafeType.bodySmall.copyWith(
                    color: GoSafeColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// SOS as a Gojek service icon: a white tile like the other cards, a solid red circle with a
/// white shield, and the label under it (as GoRide, GoFood sit on the Gojek home screen).
class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'SOS, get help now',
    excludeSemantics: true,
    child: Material(
      color: GoSafeColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: GoSafeColors.lineSoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: GoSafeColors.high,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.gpp_maybe_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              Text(
                'SOS',
                style: GoSafeType.caption.copyWith(
                  color: GoSafeColors.high,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A "Help us to improve" card: coloured tile, small label, big title, a mascot at the bottom right.
class HelpCard extends StatelessWidget {
  const HelpCard({
    super.key,
    required this.label,
    required this.title,
    required this.color,
    required this.asset,
  });

  final String label;
  final String title;
  final Color color;
  final String asset;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: ColoredBox(
      color: color,
      child: SizedBox(
        width: 200,
        height: 220,
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -6,
              child: Image.asset(
                asset,
                height: 124,
                excludeFromSemantics: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(
                    label,
                    style: GoSafeType.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    title,
                    style: GoSafeType.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The small speaker and its sound signal, in the ride green. The bars follow the real microphone
/// ([level], 0 to 1) but ignore quiet background noise: in silence they're small grey ticks that
/// don't move; a real voice makes them grow in place (green), then they settle back. Nothing scrolls.
class ListeningLine extends StatefulWidget {
  const ListeningLine({
    super.key,
    required this.recording,
    required this.text,
    this.level,
  });

  final bool recording;
  final String text;
  final Stream<double>? level;

  @override
  State<ListeningLine> createState() => _ListeningLineState();
}

class _ListeningLineState extends State<ListeningLine>
    with SingleTickerProviderStateMixin {
  StreamSubscription<double>? _sub;
  late final Ticker _ticker = createTicker(_tick);
  final _rnd = math.Random(7);

  /// Below this the room is just background noise (engine, traffic): the signal stays still.
  static const _gate = 0.45;
  static const _bars = 28;

  // Each bar glides toward its own target every frame; a new sound reading gives new targets.
  final _now = List.filled(_bars, 0.0);
  final _target = List.filled(_bars, 0.0);
  double _loud = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(ListeningLine old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level || old.recording != widget.recording) {
      _listen();
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = null;
    _loud = 0;
    _target.fillRange(0, _bars, 0);
    if (!widget.recording || widget.level == null) return;
    _sub = widget.level!.listen((v) {
      if (!mounted) return;
      final loud = v < _gate ? 0.0 : (v - _gate) / (1 - _gate);
      _loud = loud > _loud
          ? _loud * 0.3 + loud * 0.7
          : _loud * 0.7; // up fast, down gently
      if (_loud < 0.04) _loud = 0;
      for (var i = 0; i < _bars; i++) {
        // A voice-like envelope (taller in the middle) with each bar varying on its own.
        final centre = 1 - ((i - (_bars - 1) / 2).abs() / _bars) * 0.9;
        _target[i] = _loud * centre * (0.35 + 0.65 * _rnd.nextDouble());
      }
      if (!_ticker.isActive && _target.any((t) => t > 0)) _ticker.start();
    });
  }

  void _tick(Duration _) {
    var moving = false;
    for (var i = 0; i < _bars; i++) {
      final d = _target[i] - _now[i];
      _now[i] += d * 0.18; // ease toward the target: smooth, no jumps
      if (d.abs() > 0.002) moving = true;
    }
    setState(() {});
    if (!moving && _target.every((t) => t == 0)) {
      _ticker.stop(); // silence: completely still
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    spacing: 6,
    children: [
      Row(
        spacing: 10,
        children: [
          CircleIcon(
            widget.recording
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            color: widget.recording ? GoSafeColors.ride : GoSafeColors.muted,
            tint: widget.recording
                ? GoSafeColors.brandTint
                : GoSafeColors.surface,
            size: 32,
          ),
          Expanded(
            child: SizedBox(
              height: 28,
              child: CustomPaint(painter: _WavePainter(_now, widget.recording)),
            ),
          ),
        ],
      ),
      Text(
        widget.text,
        style: GoSafeType.caption.copyWith(color: GoSafeColors.label),
      ),
    ],
  );
}

/// Thin rounded bars, each its own height (0 to 1). At 0 they're small grey ticks; with sound they
/// grow green in place.
class _WavePainter extends CustomPainter {
  _WavePainter(List<double> heights, this.on) : heights = List.of(heights);

  final List<double> heights;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    final step = size.width / n;
    const w = 3.0;
    for (var i = 0; i < n; i++) {
      final v = heights[i];
      final h = math.max(w, size.height * v);
      final x = i * step + (step - w) / 2;
      final paint = Paint()
        ..color = on && v > 0.02
            ? Color.lerp(
                GoSafeColors.line,
                GoSafeColors.rideIcon,
                math.min(1, v * 3),
              )!
            : GoSafeColors.line;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          const Radius.circular(w / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
