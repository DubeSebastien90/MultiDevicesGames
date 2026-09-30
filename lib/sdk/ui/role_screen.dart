import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/age_band.dart';
import '../model/player_name.dart';

import '../app_controller.dart';
import '../platform_config.dart';
import '../model/device_metrics.dart';
import '../model/name_drop_status.dart';
import '../platform/native_dpi_channel.dart';
import 'join_sheet.dart';
import 'sticker/sticker.dart';
import 'settings_screen.dart';

/// The longest a board may be called, typed or generated.
///
/// A board's name is read off a header on every phone at the table and off the
/// join list on phones that have not arrived yet. Past this it stops being a
/// name and starts being a paragraph — and the header answers a long one by
/// setting it smaller, which only works while "long" has an end.
const int kBoardNameMaxLength = 25;

/// Pick a role. One app, two jobs: run the world, or be a window onto it.
class RoleScreen extends StatefulWidget {
  const RoleScreen({
    super.key,
    required this.controller,
    required this.ageBand,
  });

  final AppController controller;

  /// Decides whether the two names on this screen are typed or issued.
  ///
  /// Required and non-nullable on purpose. Both names leave the phone in clear
  /// — the player name rides along in [DeviceMetrics], and the game name goes
  /// out on the discovery beacon to everything on the network — so this screen
  /// should be impossible to construct without having settled the question
  /// first. [AgeGate] is the only thing that answers it.
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
    // Nobody arrives without a name. A blank field is a small wall between
    // opening the app and playing, and "phone" in the standings tells the table
    // nothing — so one is picked and written down on the first run, and anyone
    // who dislikes theirs types over it.
    final saved = prefs.getString(_kNameKey);

    // A child keeps a stored name only if the app is the one that made it up.
    // The check runs on every load rather than once at the gate, because a
    // typed name can predate the gate — an install from before this existed, or
    // a phone an adult set up and handed over. Either way the name is replaced
    // here, before anything has had a chance to put it on the wire.
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

  /// Another name from the hat, saved and shown as if it had been typed.
  void _rollName() {
    final name = PlayerNames.random();
    _nameController
      ..text = name
      ..selection = TextSelection.collapsed(offset: name.length);
    _onNameChanged(name);
  }

  void _onNameChanged(String name) {
    // Only ever reached from the text field, which a child does not get, or
    // from the dice, which can only produce names off the fixed lists.
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

    // The app is locked portrait, so the short edge is the width. Taking the
    // min and max rather than the raw values survives being measured a frame
    // before that lock lands.
    _surfaceIsLandscape = px.width > px.height;

    // Immediate Flutter density-bucket estimate so the screen is never blank.
    _metrics ??= DeviceMetrics.estimate(
      physicalPx: Size(
        math.min(px.width, px.height),
        math.max(px.width, px.height),
      ),
      devicePixelRatio: view.devicePixelRatio,
      platform: defaultTargetPlatform,
    );

    // Then attempt a one-shot native refinement (Android xdpi/ydpi or iOS
    // model-lookup). Falls back to the Flutter estimate silently on failure.
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
      // If the user has already calibrated this screen, keep their mm values
      // and only take the pixel dimensions and DPR from native detection.
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

  /// Debug-only: forgets what this phone has been asked, so both questions
  /// come back.
  ///
  /// The two answers come back at different moments, and the message says so:
  /// [NameDropGate] asks on the way into the next lobby, while the age gate is
  /// read once at launch and so cannot ask again until the app is restarted.
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

  /// What the game is called before anyone renames it.
  ///
  /// Derived from the player name rather than being a fixed string: a join list
  /// showing three separate entries called "My board" is a coin toss, and the
  /// person hosting is the one thing everyone at the table can already identify.
  /// It also means a child's board is named after a made-up animal for free.
  String _defaultBoardName() {
    const suffix = "'s board";
    final label = _currentLabel();
    // Trim the name rather than the shape: cutting the whole string at 25
    // would leave boards called "Bartholomew's bo", which reads as a bug.
    final room = kBoardNameMaxLength - suffix.length;
    final short = label.length > room ? label.substring(0, room) : label;
    return '$short$suffix';
  }

  Future<void> _host() async {
    final name = await showStickerSheet<String>(
      context,
      builder: (_) => _NameDialog(
        initialName: _defaultBoardName(),
        // This name goes out on the beacon, unencrypted, to every device on the
        // network — it is the more exposed of the two fields on this screen,
        // not the less. Locking the player name and leaving this one open would
        // move the problem rather than solve it.
        locked: _isChild,
      ),
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
          // Scrolls only when it has to — a small phone, big system type, the
          // keyboard up — and otherwise fills the screen with the title taking
          // whatever height the controls leave, as drawn.
          //
          // Not primary: on iOS a primary scroll view always bounces, even
          // with nothing to scroll, and the whole page moved under a finger.
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

  /// Pinned to the top corner rather than riding the centred content.
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
    // A child gets the name as a fact rather than a field: not a read-only
    // TextField, which still draws a box that asks to be tapped and reads as
    // broken when tapping does nothing.
    return _NamePill(
      controller: _isChild ? null : _nameController,
      name: _nameController.text,
      onChanged: _onNameChanged,
      // Rolling for another is quicker than thinking of one, and quicker still
      // than typing it on a phone.
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
      // The height of the two buttons it stands in for, so nothing above it
      // jumps while a lobby is opening.
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
    // Nothing can start until this screen knows how big it is.
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

  /// A hidden reset so testing the two gates repeatedly doesn't mean
  /// reinstalling.
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

/// "BUBBLE" as six letter stickers, bobbing, over "GAMES!".
///
/// Read as one name by a screen reader rather than as seven stray letters.
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
    // Scaled down, never up: the letters are drawn at the size the design
    // wants and only give ground to a narrow phone or a short one.
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: St.sticker(
                          color: _colors[i],
                          radius: 14,
                          shadow: 4,
                        ),
                        child: Text(
                          _letters[i],
                          style: St.display(52, color: St.white, height: 1),
                        ),
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

/// The player's name on a white pill, with the dice beside it.
///
/// Given a [controller] it is a field an adult can type into. Without one it
/// is the name as a fact: everything a child can do here produces a name off
/// [PlayerNames]'s two fixed lists, so there is no path from this widget to a
/// string that means anything about the person holding the phone. Which is the
/// entire point: the name goes out over the LAN either way, and nine hundred
/// combinations of adjective and animal are plenty to tell six phones apart.
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
  /// Whole turns of the dice, so each roll spins it once more rather than
  /// back to where it started.
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

/// Create a Lobby / Join a Lobby: a tall tilted sticker with a white disc for
/// the icon.
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

/// Names the game. This name is what friends look for in their join list, so
/// it is the one thing worth asking before the lobby opens.
///
/// [locked] turns the field into a label. The name typed here is put on a UDP
/// beacon in clear, to the whole subnet, by a device whose owner is a child —
/// so on that path there is nothing to type and nothing to submit but the name
/// the app already chose. The sheet still opens rather than being skipped:
/// being shown what the rest of the network is about to be told is worth a tap.
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
    // Selected, not just filled in. The default is a suggestion, and the first
    // keystroke should replace it rather than land in the middle of it.
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
