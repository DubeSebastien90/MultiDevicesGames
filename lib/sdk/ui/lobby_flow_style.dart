import 'dart:async';

import 'package:flutter/material.dart';

/// Visual tokens for the pre-game flow (entry, create-lobby, join-lobby,
/// settings). Local to those screens — the app's global [ThemeData] is
/// untouched.
class LobbyFlowColors {
  const LobbyFlowColors._();

  static const ink = Color(0xFF191510);
  static const paper = Color(0xFFFFFFFF);
  static const field = Color(0xFFE8E8E8);
  static const muted = Color(0xFF8C8370);

  static const green = Color(0xFF97ED91);
  static const pink = Color(0xFFF4A9CD);
  static const coral = Color(0xFFF08A80);
  static const yellow = Color(0xFFF6EE7F);
  static const orange = Color(0xFFF2CE7C);
  static const purple = Color(0xFFAFA9F0);
  static const cyan = Color(0xFFA8EFE4);

  static const lobbyPalette = [orange, green, purple, cyan];

  /// How much darker a plate's shadow is than the plate. One step for every
  /// colour, so everything sits at the same depth. Tune here.
  static const _shadeStep = 0.32;

  /// The colour a plate casts as its shadow: itself, darker.
  static Color shadeOf(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - _shadeStep).clamp(0.0, 1.0))
        .toColor();
  }

  /// A lobby's colour, fixed by its name rather than its place in the list, so
  /// it neither changes as other lobbies come and go nor differs between
  /// phones. Spelled out rather than leaning on [String.hashCode], which
  /// promises nothing across runs or platforms.
  static Color colorForLobby(String name) {
    final hash = name.codeUnits
        .fold<int>(0, (h, unit) => (h * 31 + unit) & 0x7fffffff);
    return lobbyPalette[hash % lobbyPalette.length];
  }
}

/// Shapes and timings shared by the flow's plates.
class LobbyMetrics {
  const LobbyMetrics._();

  static const pillRadius = 999.0;
  static const bigRadius = 34.0;

  /// How far a plate's shadow sits down-right, and so how far it travels when
  /// pressed.
  static const plateOffset = 4.0;
  static const rowOffset = 3.0;

  static const pressDuration = Duration(milliseconds: 90);

  /// A tap shorter than this still shows the whole press. Without it a quick
  /// tap releases before [pressDuration] has drawn anything.
  static const minPress = Duration(milliseconds: 140);
}

/// The flow's type. Everything is ink on pastel; only weight and size vary.
class LobbyText {
  const LobbyText._();

  static const title = TextStyle(
    color: LobbyFlowColors.ink,
    fontWeight: FontWeight.w900,
    fontSize: 26,
    letterSpacing: -0.5,
  );

  static const button = TextStyle(
    color: LobbyFlowColors.ink,
    fontWeight: FontWeight.w800,
    fontSize: 14,
  );

  /// A lobby name, or the username sitting in its field.
  static const label = TextStyle(
    color: LobbyFlowColors.ink,
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  static const count = TextStyle(
    color: LobbyFlowColors.ink,
    fontSize: 17,
    fontWeight: FontWeight.w700,
  );

  static const field = TextStyle(
    color: LobbyFlowColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const hint = TextStyle(
    color: LobbyFlowColors.muted,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(color: LobbyFlowColors.muted, fontSize: 13);
}

/// A coloured plate that sinks into its own shadow when pressed.
///
/// The press *is* the feedback here, so there is no ink ripple — a ripple
/// spreading while the plate drops reads as two effects fighting.
class _PressablePlate extends StatefulWidget {
  const _PressablePlate({
    required this.child,
    required this.color,
    required this.radius,
    this.onPressed,
    this.offset = LobbyMetrics.plateOffset,
    this.dimmed = false,
  });

  final Widget child;
  final Color color;
  final double radius;
  final VoidCallback? onPressed;
  final double offset;
  final bool dimmed;

  @override
  State<_PressablePlate> createState() => _PressablePlateState();
}

class _PressablePlateState extends State<_PressablePlate> {
  bool _pressed = false;
  DateTime? _downAt;
  Timer? _release;

  bool get _enabled => widget.onPressed != null;

  void _down() {
    if (!_enabled) return;
    _release?.cancel();
    _downAt = DateTime.now();
    setState(() => _pressed = true);
  }

  /// Holds the plate down for the rest of [LobbyMetrics.minPress] when the
  /// finger leaves early, so a flick of a tap animates like a deliberate one.
  void _up() {
    if (!_enabled || !_pressed) return;
    final held = DateTime.now().difference(_downAt ?? DateTime.now());
    final remaining = LobbyMetrics.minPress - held;

    if (remaining <= Duration.zero) {
      setState(() => _pressed = false);
      return;
    }
    _release?.cancel();
    _release = Timer(remaining, () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  void dispose() {
    _release?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final down = _pressed && _enabled;
    final travel = widget.offset;

    return Opacity(
      opacity: widget.dimmed || !_enabled ? 0.5 : 1,
      child: GestureDetector(
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: LobbyMetrics.pressDuration,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            down ? travel : 0,
            down ? travel : 0,
            0,
          ),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: widget.dimmed
                ? null
                : [
                    BoxShadow(
                      color: LobbyFlowColors.shadeOf(widget.color),
                      offset: down ? Offset.zero : Offset(travel, travel),
                      blurRadius: 0,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A rounded button with a hard offset shadow, matching the mockup's flat
/// drop-shadow look. [LobbyPillButton.big] is the large icon-over-label form
/// used for the screens' main actions.
class LobbyPillButton extends StatelessWidget {
  const LobbyPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.background = LobbyFlowColors.ink,
    this.foreground = LobbyFlowColors.paper,
    this.fontSize = 14,
    this.radius = LobbyMetrics.pillRadius,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    this.stacked = false,
    this.iconSize = 18,
  });

  /// The big square-ish action button: Create a Lobby, Join a Lobby, Scan QR.
  const LobbyPillButton.big({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
  })  : foreground = LobbyFlowColors.ink,
        fontSize = 17,
        radius = LobbyMetrics.bigRadius,
        stacked = true,
        iconSize = 54;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final double fontSize;
  final double radius;
  final EdgeInsets padding;

  /// Icon above the label instead of beside it.
  final bool stacked;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: LobbyText.button.copyWith(color: foreground, fontSize: fontSize),
    );
    final art = icon == null
        ? null
        : Icon(icon, size: iconSize, color: foreground);

    return _PressablePlate(
      color: background,
      radius: radius,
      onPressed: onPressed,
      child: Padding(
        padding: padding,
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (art != null) ...[art, const SizedBox(height: 10)],
                  text,
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (art != null) ...[art, const SizedBox(width: 8)],
                  text,
                ],
              ),
      ),
    );
  }
}

/// The gray pill text field: username on the entry screen, lobby name in the
/// create dialog.
class LobbyChipField extends StatelessWidget {
  const LobbyChipField({
    super.key,
    required this.controller,
    this.hintText,
    this.suffixIcon,
    this.onSuffixTap,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? hintText;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      style: LobbyText.field,
      decoration: InputDecoration(
        counterText: '',
        hintText: hintText,
        hintStyle: LobbyText.hint,
        filled: true,
        fillColor: LobbyFlowColors.field,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        suffixIcon: suffixIcon == null
            ? null
            : IconButton(
                icon: Icon(suffixIcon, color: LobbyFlowColors.ink, size: 20),
                onPressed: onSuffixTap,
              ),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _border,
      ),
    );
  }

  static final _border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(LobbyMetrics.pillRadius),
    borderSide: BorderSide.none,
  );
}

/// A pastel row with a hard shadow — a lobby in the join list.
class LobbyCard extends StatelessWidget {
  const LobbyCard({
    super.key,
    required this.child,
    this.onTap,
    this.dimmed = false,
    this.color = LobbyFlowColors.orange,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool dimmed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _PressablePlate(
      color: color,
      radius: LobbyMetrics.pillRadius,
      onPressed: onTap,
      dimmed: dimmed,
      offset: LobbyMetrics.rowOffset,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: child,
      ),
    );
  }
}

/// A round-cornered icon button. Given a [background] it is a filled pill (the
/// coral back button); without one it is the bare gear.
class LobbyIconButton extends StatelessWidget {
  const LobbyIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.background,
    this.size = 22,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color? background;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fill = background;
    if (fill == null) {
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: size, color: LobbyFlowColors.ink),
      );
    }

    final button = _PressablePlate(
      color: fill,
      radius: LobbyMetrics.pillRadius,
      onPressed: onPressed,
      offset: LobbyMetrics.rowOffset,
      child: Padding(
        // Wider than tall — a pill in the mockups, not a disc.
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 18),
        child: Icon(icon, size: size, color: LobbyFlowColors.ink),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The screen title, bold and black, as every mockup header draws it.
class LobbyTitle extends StatelessWidget {
  const LobbyTitle(this.text, {super.key, this.fontSize});

  final String text;
  final double? fontSize;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: fontSize == null
            ? LobbyText.title
            : LobbyText.title.copyWith(fontSize: fontSize),
      );
}

/// Back pill, centred title, optional gear — the header every screen in the
/// flow wears.
class LobbyHeader extends StatelessWidget {
  const LobbyHeader({
    super.key,
    required this.title,
    this.onBack,
    this.onSettings,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 8),
  });

  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;

  /// Set to zero when the header already sits inside a padded scroll view.
  final EdgeInsets padding;

  /// Roughly a back pill's width, so the title stays optically centred when
  /// only one side of the row is occupied.
  static const _sideWidth = 58.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (onBack != null)
            LobbyIconButton(
              icon: Icons.arrow_back,
              background: LobbyFlowColors.coral,
              onPressed: onBack,
            )
          else
            const SizedBox(width: _sideWidth),
          Expanded(child: LobbyTitle(title)),
          if (onSettings != null)
            LobbyIconButton(
              icon: Icons.settings,
              size: 28,
              tooltip: 'Settings',
              onPressed: onSettings,
            )
          else
            const SizedBox(width: _sideWidth),
        ],
      ),
    );
  }
}
