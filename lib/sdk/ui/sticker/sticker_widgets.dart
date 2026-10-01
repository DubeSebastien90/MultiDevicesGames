import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../audio/ui_audio.dart';
import 'sticker_background.dart';
import 'sticker_tokens.dart';

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
          color: _enabled
              ? w.color
              : Color.alphaBlend(St.white.withValues(alpha: .55), w.color),
          radius: w.radius,
          shadow: w.shadow - sink,
          border: w.border,
        ),
        child: _enabled ? w.child : Opacity(opacity: .5, child: w.child),
      ),
    );

    if (w.tooltip != null) {
      button = Tooltip(message: w.tooltip!, child: button);
    }
    return w.tiltDeg == 0
        ? button
        : Transform.rotate(angle: w.tiltDeg * math.pi / 180, child: button);
  }
}

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

class StickerBackButton extends StatelessWidget {
  const StickerBackButton({super.key, this.onTap});

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

class StickerPage extends StatelessWidget {
  const StickerPage({
    super.key,
    required this.child,
    this.shapes = lobbyShapes,
    this.maxWidth = 620,
  });

  final Widget child;
  final List<StickerShape> shapes;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: St.bg,
    body: StickerBackground(
      shapes: shapes,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class StickerField extends StatelessWidget {
  const StickerField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.size = 20,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? maxLength;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = St.body(size, weight: FontWeight.w700);
    final field = StickerCard(
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        maxLength: maxLength,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        cursorColor: St.ink,
        style: style,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintText: hintText,
          hintStyle: style.copyWith(color: St.muted.withValues(alpha: .6)),
        ),
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(label!, style: St.body(14, color: St.muted)),
        ),
        field,
      ],
    );
  }
}

class StickerWideButton extends StatelessWidget {
  const StickerWideButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color = St.white,
    this.textColor = St.ink,
    this.height = 62,
    this.fontSize = 22,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;
  final double height;
  final double fontSize;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Flexible(
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: trailing == null ? TextAlign.center : TextAlign.start,
        style: St.display(fontSize, color: textColor),
      ),
    );
    return StickerButton(
      height: height,
      radius: 20,
      shadow: 5,
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisSize: trailing == null ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: trailing == null
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          if (icon != null) ...[
            StIcon(icon!, size: fontSize + 6, color: textColor),
            const SizedBox(width: 10),
          ],
          if (trailing == null)
            text
          else
            Expanded(child: Row(children: [text])),
          ?trailing,
        ],
      ),
    );
  }
}

class StickerSpinner extends StatelessWidget {
  const StickerSpinner({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: size / 9,
      color: St.ink,
      strokeCap: StrokeCap.round,
    ),
  );
}

class StickerMark extends StatelessWidget {
  const StickerMark({
    super.key,
    required this.icon,
    required this.color,
    this.iconColor = St.white,
    this.size = 96,
    this.tiltDeg = -8,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final double size;
  final double tiltDeg;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: tiltDeg * math.pi / 180,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: St.ink, width: 3),
        boxShadow: St.hard(size / 16),
      ),
      child: Center(
        child: StIcon(icon, size: size * .55, color: iconColor),
      ),
    ),
  );
}

class StickerLoadingScreen extends StatelessWidget {
  const StickerLoadingScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => StickerPage(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StickerSpinner(size: 44),
          if (message != null) ...[
            const SizedBox(height: 20),
            Text(message!, style: St.display(26), textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );
}
