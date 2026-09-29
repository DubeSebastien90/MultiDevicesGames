import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/ui_audio.dart';
import 'sticker_tokens.dart';

/// The sticker button: ink border, hard shadow, and a press that sinks it onto
/// its own shadow.
///
/// The sink *is* the feedback, so there is no ripple. It also boups, through
/// [withButtonSound], like every other button in the app — a disabled one
/// stays silent and sits at half strength.
class StickerButton extends StatefulWidget {
  const StickerButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color = St.white,
    this.shadow = 4,
    this.radius = 16,
    this.border = 3,
    this.tiltDeg = 0,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final double shadow;
  final double radius;
  final double border;
  final double tiltDeg;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  /// For an icon-only button, so a screen reader has something to say.
  final String? tooltip;

  @override
  State<StickerButton> createState() => _StickerButtonState();
}

class _StickerButtonState extends State<StickerButton> {
  bool _down = false;
  DateTime? _downAt;
  Timer? _release;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _press() {
    if (!_enabled) return;
    _release?.cancel();
    _downAt = DateTime.now();
    setState(() => _down = true);
  }

  /// Holds the button down for the rest of [St.minPress] when the finger
  /// leaves early, so a flick of a tap sinks like a deliberate one.
  void _lift() {
    if (!_down) return;
    final held = DateTime.now().difference(_downAt ?? DateTime.now());
    final remaining = St.minPress - held;
    if (remaining <= Duration.zero) {
      setState(() => _down = false);
      return;
    }
    _release?.cancel();
    _release = Timer(remaining, () {
      if (mounted) setState(() => _down = false);
    });
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final sink = _down && _enabled ? w.shadow : 0.0;
    final onTap = withButtonSound(w.onTap);

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _lift(),
      onTapCancel: _lift,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap();
            },
      onLongPress: w.onLongPress,
      child: AnimatedContainer(
        duration: St.press,
        curve: Curves.easeOut,
        width: w.width,
        height: w.height,
        padding: w.padding,
        alignment: (w.width != null || w.height != null)
            ? Alignment.center
            : null,
        transform: Matrix4.translationValues(sink, sink, 0),
        decoration: St.sticker(
          color: w.color,
          radius: w.radius,
          shadow: w.shadow - sink,
          border: w.border,
        ),
        child: w.child,
      ),
    );

    if (!_enabled) button = Opacity(opacity: .5, child: button);
    if (w.tooltip != null) {
      button = Tooltip(message: w.tooltip!, child: button);
    }
    return w.tiltDeg == 0
        ? button
        : Transform.rotate(angle: w.tiltDeg * math.pi / 180, child: button);
  }
}

/// A sticker that does nothing when touched: a card.
class StickerCard extends StatelessWidget {
  const StickerCard({
    super.key,
    required this.child,
    this.color = St.white,
    this.radius = 24,
    this.shadow = 5,
    this.border = 3,
    this.padding = const EdgeInsets.all(16),
    this.tiltDeg = 0,
    this.clip = false,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double shadow;
  final double border;
  final EdgeInsetsGeometry padding;
  final double tiltDeg;

  /// Clip the contents to the inside of the border — for a card with a
  /// coloured band or a picture running to its edge.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    Widget inner = Padding(padding: padding, child: child);
    if (clip) {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(radius - border),
        child: inner,
      );
    }
    final card = DecoratedBox(
      decoration: St.sticker(
        color: color,
        radius: radius,
        shadow: shadow,
        border: border,
      ),
      child: inner,
    );
    return tiltDeg == 0
        ? card
        : Transform.rotate(angle: tiltDeg * math.pi / 180, child: card);
  }
}

/// The red back button every sub-screen header starts with.
class StickerBackButton extends StatelessWidget {
  const StickerBackButton({super.key, this.onTap});

  /// Defaults to popping the route.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => StickerButton(
    width: 60,
    height: 52,
    radius: 18,
    color: St.back,
    tooltip: 'Back',
    onTap: onTap ?? () => Navigator.of(context).maybePop(),
    child: const StIcon(Symbols.arrow_back_rounded, size: 30, color: St.white),
  );
}

/// Back button, then the title in Lilita.
class StickerHeader extends StatelessWidget {
  const StickerHeader(
    this.title, {
    super.key,
    this.size = 28,
    this.onBack,
    this.trailing,
  });

  final String title;
  final double size;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StickerBackButton(onTap: onBack),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: St.display(size),
        ),
      ),
      ?trailing,
    ],
  );
}

/// A small pill: a count, "YOU", "away".
class StickerPill extends StatelessWidget {
  const StickerPill(
    this.label, {
    super.key,
    this.color = St.ink,
    this.textColor = St.white,
    this.size = 16,
    this.border = 0,
    this.icon,
    this.padding,
  });

  final String label;
  final Color color;
  final Color textColor;
  final double size;
  final double border;
  final IconData? icon;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding:
        padding ??
        EdgeInsets.symmetric(horizontal: size * .7, vertical: size * .33),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
      border: border > 0 ? Border.all(color: St.ink, width: border) : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          StIcon(icon!, size: size + 1, color: textColor),
          const SizedBox(width: 3),
        ],
        Text(label, style: St.display(size, color: textColor, height: 1)),
      ],
    ),
  );
}

/// A red-edged warning on yellow: something went wrong, and here is what.
///
/// For the few messages the designs do not draw — a failed connection, a
/// sideways iPad — dressed as a sticker so they read as part of the screen
/// rather than a Material error box that wandered in.
class StickerNotice extends StatelessWidget {
  const StickerNotice({
    super.key,
    required this.icon,
    required this.message,
    this.onDismiss,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => StickerCard(
    radius: 18,
    shadow: 4,
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: St.back,
            shape: BoxShape.circle,
            border: Border.all(color: St.ink, width: 2.5),
          ),
          child: Center(child: StIcon(icon, size: 20, color: St.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: St.body(14, weight: FontWeight.w600)),
        ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Dismiss',
            onPressed: withButtonSound(onDismiss),
            icon: const StIcon(Symbols.close_rounded, size: 20),
          ),
      ],
    ),
  );
}
