import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/age_band.dart';
import '../model/player_name.dart';

import '../app_controller.dart';
import '../audio/ui_audio.dart';
import '../platform_config.dart';
import '../model/device_metrics.dart';
import '../model/name_drop_status.dart';
import '../platform/native_dpi_channel.dart';
import 'join_sheet.dart';
import 'sticker/sticker.dart';
import 'settings_screen.dart';

const int kBoardNameMaxLength = 25;

class RoleScreen extends StatefulWidget {
  const RoleScreen({
    super.key,
    required this.controller,
    required this.ageBand,
  });

  final AppController controller;

  final AgeBand ageBand;

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  DeviceMetrics? _metrics;
  bool _surfaceIsLandscape = false;
  bool _nativeDone = false;

  static const _kNameKey = 'player_name';
  static const _kWidthMmKey = 'screen_width_mm';
  static const _kHeightMmKey = 'screen_height_mm';
  static const _kBezelMmKey = 'screen_bezel_mm';

  final _nameController = TextEditingController();
  bool _hasSavedScreenSize = false;

  bool get _isChild => widget.ageBand == AgeBand.child;

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final saved = prefs.getString(_kNameKey);

    final usable =
        saved != null &&
        saved.isNotEmpty &&
        (!_isChild || PlayerNames.isGenerated(saved));

    final name = usable ? saved : PlayerNames.random();
    if (!usable) {
      await prefs.setString(_kNameKey, name);
      if (!mounted) return;
    }

    final widthMm = prefs.getDouble(_kWidthMmKey);
    final heightMm = prefs.getDouble(_kHeightMmKey);
    final bezelMm = prefs.getDouble(_kBezelMmKey);
    setState(() {
      _nameController.text = name;
      if (widthMm != null && heightMm != null) {
        _hasSavedScreenSize = true;
        _metrics = _metrics?.copyWith(
          widthMm: widthMm,
          heightMm: heightMm,
          bezelMm: bezelMm,
          label: name,
        );
      } else {
        _metrics = _metrics?.copyWith(label: name);
      }
    });
  }

  void _rollName() {
    final name = PlayerNames.random();
    _nameController
      ..text = name
      ..selection = TextSelection.collapsed(offset: name.length);
    _onNameChanged(name);
  }

  void _onNameChanged(String name) {
    SharedPreferences.getInstance().then((p) => p.setString(_kNameKey, name));
    final label = name.trim().isEmpty ? 'phone' : name.trim();
    setState(() => _metrics = _metrics?.copyWith(label: label));
  }

  void _onMetricsChanged(DeviceMetrics m) {
    setState(() {
      _metrics = m;
      _hasSavedScreenSize = true;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble(_kWidthMmKey, m.widthMm);
      prefs.setDouble(_kHeightMmKey, m.heightMm);
      prefs.setDouble(_kBezelMmKey, m.bezelMm);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.of(context);
    final px = view.physicalSize;

    _surfaceIsLandscape = px.width > px.height;

    _metrics ??= DeviceMetrics.estimate(
      physicalPx: Size(
        math.min(px.width, px.height),
        math.max(px.width, px.height),
      ),
      devicePixelRatio: view.devicePixelRatio,
      platform: defaultTargetPlatform,
    );

    if (!_nativeDone) {
      _nativeDone = true;
      _refineWithNative(view.physicalSize, view.devicePixelRatio);
    }
  }

  Future<void> _refineWithNative(Size px, double dpr) async {
    final refined = await NativeDpiChannel.detect(
      physicalPx: px,
      devicePixelRatio: dpr,
      platform: defaultTargetPlatform,
    );
    if (!mounted) return;
    setState(() {
      _metrics = _hasSavedScreenSize
          ? refined.copyWith(
              widthMm: _metrics?.widthMm,
              heightMm: _metrics?.heightMm,
              bezelMm: _metrics?.bezelMm,
              label: _metrics?.label ?? _currentLabel(),
            )
          : refined.copyWith(
              bezelMm: _metrics?.bezelMm,
              label: _metrics?.label ?? _currentLabel(),
            );
    });
  }

  String _currentLabel() {
    final name = _nameController.text.trim();
    return name.isEmpty ? 'phone' : name;
  }

  Future<void> _reloadAskedState() async {
    await NameDropPref.save(NameDropStatus.waiting);
    await AgeGatePref.debugForget();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reset. NameDrop asks at the next lobby, age at the next launch.',
        ),
      ),
    );
  }

  void _openSettings() {
    final metrics = _metrics;
    if (metrics == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          metrics: metrics,
          onMetricsChanged: _onMetricsChanged,
          premium: widget.controller.premium,
        ),
      ),
    );
  }

  String _defaultBoardName() {
    const suffix = "'s board";
    final label = _currentLabel();

    final room = kBoardNameMaxLength - suffix.length;
    final short = label.length > room ? label.substring(0, room) : label;
    return '$short$suffix';
  }

  Future<void> _host() async {
    final name = await showStickerSheet<String>(
      context,
      builder: (_) =>
          _NameDialog(initialName: _defaultBoardName(), locked: _isChild),
    );
    if (name == null || !mounted) return;
    await widget.controller.startHost(_metrics!, name: name);
  }

  Future<void> _join() async {
    final request = await Navigator.of(context).push<JoinRequest>(
      MaterialPageRoute(
        builder: (_) => JoinSheet(
          seatFingerprint: widget.controller.seatFingerprint,
          metrics: _metrics!,
          onMetricsChanged: _onMetricsChanged,
          premium: widget.controller.premium,
        ),
      ),
    );
    if (request == null || !mounted) return;
    await widget.controller.joinHost(
      request.uri,
      _metrics!,
      code: request.code,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: St.bg,
      body: StickerBackground(
        shapes: homeShapes,
        child: SafeArea(
          child: CustomScrollView(
            primary: false,
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _gear(),
                          const Expanded(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: _BubbleTitle(),
                              ),
                            ),
                          ),
                          _nameField(),
                          ..._banners(),
                          const SizedBox(height: 20),
                          ..._actions(),
                          if (PlatformConfig.showDebugUi) _debugReload(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gear() => Align(
    alignment: Alignment.centerRight,
    child: StickerButton(
      width: 52,
      height: 52,
      radius: 16,
      tooltip: 'Settings',
      onTap: _metrics == null ? null : _openSettings,
      child: const StIcon(Symbols.settings_rounded, size: 28),
    ),
  );

  Widget _nameField() {
    return _NamePill(
      controller: _isChild ? null : _nameController,
      name: _nameController.text,
      onChanged: _onNameChanged,
      onRoll: _rollName,
    );
  }

  List<Widget> _banners() {
    final error = widget.controller.error;
    return [
      if (_surfaceIsLandscape) ...[
        const SizedBox(height: 16),
        const StickerNotice(
          icon: Symbols.screen_rotation_rounded,
          message:
              'Hold this device upright. It is drawing sideways, so its '
              'measurements — and its place on the board — would be wrong.',
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 16),
        StickerNotice(
          icon: Symbols.error_rounded,
          message: error,
          onDismiss: widget.controller.clearError,
        ),
      ],
    ];
  }

  List<Widget> _actions() {
    if (widget.controller.busy) {
      return const [
        SizedBox(
          height: 204,
          child: Center(
            child: SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(strokeWidth: 4, color: St.ink),
            ),
          ),
        ),
      ];
    }

    final ready = _metrics != null;
    return [
      _BigAction(
        label: 'Create a Lobby',
        icon: Symbols.sensors_rounded,
        color: St.create,
        tiltDeg: -1.5,
        onTap: ready ? _host : null,
      ),
      const SizedBox(height: 20),
      _BigAction(
        label: 'Join a Lobby',
        icon: Symbols.search_rounded,
        color: St.join,
        tiltDeg: 1.5,
        onTap: ready ? _join : null,
      ),
    ];
  }

  Widget _debugReload() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Center(
      child: TextButton.icon(
        onPressed: _reloadAskedState,
        style: TextButton.styleFrom(foregroundColor: St.muted),
        icon: const StIcon(Symbols.refresh_rounded, size: 16, color: St.muted),
        label: Text('Reload state', style: St.body(13, color: St.muted)),
      ),
    ),
  );
}

class _BubbleTitle extends StatelessWidget {
  const _BubbleTitle();

  static const _letters = ['B', 'U', 'B', 'B', 'L', 'E'];
  static const _colors = [
    Color(0xFF14AEEF),
    Color(0xFFFB48C4),
    Color(0xFF31B83C),
    Color(0xFF8D13FF),
    Color(0xFFFE7013),
    Color(0xFFD23131),
  ];
  static const _tilts = [-6.0, 4.0, -3.0, 5.0, -4.0, 3.0];

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: 'Bubble Games',
    excludeSemantics: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Bob(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _letters.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Transform.rotate(
                      angle: _tilts[i] * math.pi / 180,
                      child: _MorphLetter(
                        letter: _letters[i],
                        color: _colors[i],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Transform.rotate(
            angle: -2 * math.pi / 180,
            child: Text('GAMES!', style: St.display(64, height: 1)),
          ),
        ],
      ),
    ),
  );
}

class _MorphLetter extends StatefulWidget {
  const _MorphLetter({required this.letter, required this.color});

  final String letter;
  final Color color;

  @override
  State<_MorphLetter> createState() => _MorphLetterState();
}

class _MorphLetterState extends State<_MorphLetter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  _LetterShape _from = _LetterShape.square;
  _LetterShape _to = _LetterShape.square;

  static final _dice = math.Random();

  void _tap() {
    final others = [
      for (final shape in _LetterShape.values)
        if (shape != _to) shape,
    ];
    final next = others[_dice.nextInt(others.length)];
    setState(() {
      _from = _to;
      _to = next;
    });
    HapticFeedback.selectionClick();
    UiAudio.buttonPress();
    _morph.forward(from: 0);
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: AnimatedBuilder(
        animation: _morph,
        builder: (context, child) {
          final t = _morph.value;

          final pop = t < .25
              ? 1 - .22 * Curves.easeOut.transform(t / .25)
              : .78 + .22 * Curves.elasticOut.transform((t - .25) / .75);

          final wobble = math.sin(t * math.pi * 3) * (1 - t) * .18;
          return Transform.rotate(
            angle: wobble,
            child: Transform.scale(
              scale: pop,
              child: CustomPaint(
                painter: _LetterShapePainter(
                  from: _from,
                  to: _to,
                  t: Curves.easeInOutBack.transform(t),
                  color: widget.color,
                ),
                child: child,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            widget.letter,
            style: St.display(52, color: St.white, height: 1),
          ),
        ),
      ),
    );
  }
}

enum _LetterShape { square, circle, triangle, hexagon }

class _LetterShapePainter extends CustomPainter {
  _LetterShapePainter({
    required this.from,
    required this.to,
    required this.t,
    required this.color,
  });

  final _LetterShape from;
  final _LetterShape to;

  final double t;
  final Color color;

  static const _samples = 120;
  static const _radius = 14.0;
  static const _shadow = 4.0;
  static const _border = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final hx = size.width / 2;
    final hy = size.height / 2;
    final centre = size.center(Offset.zero);

    final path = Path();
    for (var i = 0; i < _samples; i++) {
      final theta = i / _samples * 2 * math.pi;
      final a = _reach(from, theta, hx, hy);
      final b = _reach(to, theta, hx, hy);
      final r = math.max(a + (b - a) * t, 1.0);
      final p = centre + Offset(math.cos(theta), math.sin(theta)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    canvas.drawPath(
      path.shift(const Offset(_shadow, _shadow)),
      Paint()..color = St.ink,
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _border
        ..strokeJoin = StrokeJoin.round
        ..color = St.ink,
    );
  }

  static double _reach(_LetterShape shape, double theta, double hx, double hy) {
    final big = math.max(hx, hy);
    return switch (shape) {
      _LetterShape.square => _roundedRect(theta, hx, hy, _radius),
      _LetterShape.circle => big * 1.06,
      _LetterShape.triangle => _polygon(
        theta,
        3,
        -math.pi / 2,
        big * 1.6,
        big * 0.32,
      ),
      _LetterShape.hexagon => _polygon(theta, 6, 0, big * 1.12, big * 0.2),
    };
  }

  static double _polygon(
    double theta,
    int sides,
    double start,
    double r,
    double rc,
  ) {
    final wedge = 2 * math.pi / sides;
    final half = wedge / 2;

    final local = ((theta - start) % wedge + wedge) % wedge - half;

    final apothem = r * math.cos(half);

    final inner = r - rc / math.cos(half);

    final c = math.cos(local);
    final s = math.sin(local);
    final t = apothem / c;
    final corner = inner * math.sin(half);
    if ((t * s).abs() <= corner) return t;

    final vx = inner * math.cos(half);
    final vy = s < 0 ? -corner : corner;
    final dot = c * vx + s * vy;
    return dot + math.sqrt(dot * dot - (vx * vx + vy * vy) + rc * rc);
  }

  static double _roundedRect(double theta, double hx, double hy, double rc) {
    final c = math.cos(theta).abs();
    final s = math.sin(theta).abs();
    final t = math.min(
      c < 1e-9 ? double.infinity : hx / c,
      s < 1e-9 ? double.infinity : hy / s,
    );
    if (c * t <= hx - rc || s * t <= hy - rc) return t;

    final cx = hx - rc;
    final cy = hy - rc;
    final dot = c * cx + s * cy;
    return dot + math.sqrt(dot * dot - (cx * cx + cy * cy) + rc * rc);
  }

  @override
  bool shouldRepaint(_LetterShapePainter old) =>
      old.from != from || old.to != to || old.t != t || old.color != color;
}

class _NamePill extends StatefulWidget {
  const _NamePill({
    required this.controller,
    required this.name,
    required this.onChanged,
    required this.onRoll,
  });

  final TextEditingController? controller;
  final String name;
  final ValueChanged<String> onChanged;
  final VoidCallback onRoll;

  @override
  State<_NamePill> createState() => _NamePillState();
}

class _NamePillState extends State<_NamePill> {
  double _turns = 0;

  void _roll() {
    setState(() => _turns += 1);
    widget.onRoll();
  }

  @override
  Widget build(BuildContext context) {
    final style = St.body(22, weight: FontWeight.w700);
    final controller = widget.controller;

    return StickerCard(
      radius: 22,
      shadow: 5,
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Row(
        children: [
          const StIcon(Symbols.face_rounded, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: controller == null
                ? Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  )
                : TextField(
                    controller: controller,
                    onChanged: widget.onChanged,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                    cursorColor: St.ink,
                    style: style,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      counterText: '',
                      hintText: 'Your name',
                      hintStyle: style.copyWith(color: St.muted),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          StickerButton(
            width: 52,
            height: 52,
            radius: 14,
            shadow: 3,
            color: St.dice,
            tooltip: 'Roll another name',
            onTap: _roll,
            child: AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              child: const StIcon(
                Symbols.casino_rounded,
                size: 28,
                color: St.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.tiltDeg,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double tiltDeg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => StickerButton(
    height: 92,
    radius: 26,
    shadow: 7,
    color: color,
    tiltDeg: tiltDeg,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: St.white,
            shape: BoxShape.circle,
            border: Border.all(color: St.ink, width: 3),
          ),
          child: Center(child: StIcon(icon, size: 32)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: St.display(28),
          ),
        ),
        const SizedBox(width: 8),
        const StIcon(Symbols.arrow_forward_rounded, size: 30),
      ],
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initialName, this.locked = false});

  final String initialName;
  final bool locked;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void initState() {
    super.initState();

    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? widget.initialName : name);
  }

  @override
  Widget build(BuildContext context) {
    final style = St.body(20, weight: FontWeight.w700);

    return StickerSheetShell(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Create Lobby', style: St.display(28))),
                  const SheetCloseButton(),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Friends look for this name in their join list.',
                style: St.body(15, weight: FontWeight.w500, color: St.muted),
              ),
              const SizedBox(height: 18),
              StickerCard(
                radius: 18,
                shadow: 4,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: widget.locked
                    ? Text(widget.initialName, style: style)
                    : TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: kBoardNameMaxLength,
                        textCapitalization: TextCapitalization.words,
                        cursorColor: St.ink,
                        style: style,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          counterText: '',
                          hintText: 'Lobby name',
                          hintStyle: style.copyWith(color: St.muted),
                        ),
                      ),
              ),
              const SizedBox(height: 22),
              StickerButton(
                height: 66,
                radius: 22,
                shadow: 6,
                color: St.go,
                onTap: _submit,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Create Lobby', style: St.display(24)),
                    const SizedBox(width: 10),
                    const StIcon(Symbols.arrow_forward_rounded, size: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
