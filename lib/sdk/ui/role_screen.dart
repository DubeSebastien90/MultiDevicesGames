import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/age_band.dart';
import '../model/player_name.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
import '../model/name_drop_status.dart';
import '../platform/native_dpi_channel.dart';
import 'join_sheet.dart';
import 'lobby_flow_style.dart';
import 'settings_screen.dart';

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

  /// Debug-only: forgets whatever this phone answered about NameDrop, so
  /// [NameDropGate] asks again the next time the lobby opens.
  Future<void> _reloadNameDropState() async {
    await NameDropPref.save(NameDropStatus.waiting);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('NameDrop status reset to waiting')),
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
  String _defaultBoardName() => "${_currentLabel()}'s board";

  Future<void> _host() async {
    final name = await showDialog<String>(
      context: context,
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
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _gear(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const LobbyTitle('Bubble Games !', fontSize: 38),
                        const SizedBox(height: 48),
                        _nameField(),
                        const SizedBox(height: 14),
                        ..._banners(),
                        const SizedBox(height: 26),
                        _actions(),
                        if (kDebugMode) _debugReload(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pinned to the top, so it lines up with the gear on the other screens
  /// instead of riding the centred content down the page.
  Widget _gear() => Padding(
        padding: const EdgeInsets.only(right: 12, top: 4),
        child: Align(
          alignment: Alignment.centerRight,
          child: LobbyIconButton(
            icon: Icons.settings,
            size: 30,
            tooltip: 'Settings',
            onPressed: _metrics == null ? null : _openSettings,
          ),
        ),
      );

  Widget _nameField() {
    // A child gets the name as a fact rather than a field: not a read-only
    // TextField, which still draws a box that asks to be tapped and reads as
    // broken when tapping does nothing.
    if (_isChild) {
      return _IssuedNameField(name: _nameController.text, onRoll: _rollName);
    }
    return LobbyChipField(
      controller: _nameController,
      onChanged: _onNameChanged,
      maxLength: 30,
      hintText: 'Enter Your Username',
      // Rolling for another is quicker than thinking of one, and quicker still
      // than typing it on a phone.
      suffixIcon: Icons.casino_outlined,
      onSuffixTap: _rollName,
    );
  }

  List<Widget> _banners() {
    final error = widget.controller.error;
    return [
      if (_surfaceIsLandscape) ...[
        _LandscapeWarning(),
        const SizedBox(height: 14),
      ],
      if (error != null) ...[
        _ErrorBanner(
          message: error,
          onDismiss: widget.controller.clearError,
        ),
        const SizedBox(height: 14),
      ],
    ];
  }

  Widget _actions() {
    if (widget.controller.busy) {
      return const Center(child: LobbySpinner());
    }
    // Nothing can start until this screen knows how big it is.
    final ready = _metrics != null;
    return Row(
      children: [
        Expanded(
          child: LobbyPillButton.big(
            label: 'Create a Lobby',
            icon: Icons.podcasts,
            background: LobbyFlowColors.green,
            onPressed: ready ? _host : null,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: LobbyPillButton.big(
            label: 'Join a Lobby',
            icon: Icons.search,
            background: LobbyFlowColors.pink,
            onPressed: ready ? _join : null,
          ),
        ),
      ],
    );
  }

  /// A hidden reset so testing NameDrop repeatedly doesn't mean reinstalling.
  Widget _debugReload() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: _reloadNameDropState,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reload state'),
          ),
        ),
      );
}

/// The player name as a fact rather than a field, with a dice to change it.
///
/// Everything a player can do here produces a name off [PlayerNames]'s two
/// fixed lists, so there is no path from this widget to a string that means
/// anything about the person holding the phone. Which is the entire point: the
/// name is going out over the LAN either way, and nine hundred combinations of
/// adjective and animal are plenty to tell six phones apart.
class _IssuedNameField extends StatelessWidget {
  const _IssuedNameField({required this.name, required this.onRoll});

  final String name;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: BoxDecoration(
        color: LobbyFlowColors.field,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(child: Text(name, style: LobbyText.field)),
          IconButton(
            tooltip: 'Roll another name',
            onPressed: onRoll,
            icon: const Icon(
              Icons.casino_outlined,
              color: LobbyFlowColors.ink,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the device is drawing landscape despite the portrait lock —
/// an iPad in Split View, or a platform that ignores the lock.
///
/// The board is measured in real millimetres, so this is not cosmetic: every
/// size the app reports about this screen would be sideways, and the seam could
/// not line up. Better to say so than to draw a confidently wrong diagram.
class _LandscapeWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.screen_rotation, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hold this device upright. It is drawing sideways, so its '
              'measurements — and its place on the board — would be wrong.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the game. This name is what friends look for in their join list, so
/// it is the one thing worth asking before the lobby opens.
///
/// [locked] turns the field into a label. The name typed here is put on a UDP
/// beacon in clear, to the whole subnet, by a device whose owner is a child —
/// so on that path there is nothing to type and nothing to submit but the name
/// the app already chose. The dialog still opens rather than being skipped:
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
    return Dialog(
      backgroundColor: LobbyFlowColors.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LobbyTitle('Create Lobby', fontSize: 24),
            const SizedBox(height: 20),
            if (widget.locked)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: LobbyFlowColors.field,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(widget.initialName, style: LobbyText.field),
              )
            else
              LobbyChipField(
                controller: _controller,
                autofocus: true,
                maxLength: 40,
                hintText: 'Enter Lobby Name',
                onSubmitted: (_) => _submit(),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                LobbyIconButton(
                  icon: Icons.arrow_back,
                  background: LobbyFlowColors.coral,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: LobbyPillButton(
                    label: 'Create Lobby',
                    background: LobbyFlowColors.green,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 16,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
          ),
        ],
      ),
    );
  }
}
