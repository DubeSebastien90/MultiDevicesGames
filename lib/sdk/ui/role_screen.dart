import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/age_band.dart';
import '../model/player_name.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
import '../platform/native_dpi_channel.dart';
import 'join_sheet.dart';
import 'metrics_card.dart';

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
    final usable = saved != null &&
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

  void _editScreenSize() {
    final metrics = _metrics;
    if (metrics == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screen size'),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        content: MetricsCard(
          metrics: metrics,
          onChanged: _onMetricsChanged,
          initiallyExpanded: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
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
        ),
      ),
    );
    if (request == null || !mounted) return;
    await widget.controller
        .joinHost(request.uri, _metrics!, code: request.code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _metrics;
    final error = widget.controller.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'MultiDevicesGame',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lay the phones together on a table. They become one '
                    'board, and each game arranges them its own way.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  if (_isChild)
                    // Not a read-only TextField. That still draws a box that
                    // asks to be tapped, and a field that does nothing when
                    // tapped reads as broken rather than as closed. This is a
                    // name being shown, with a dice next to it.
                    _IssuedNameField(
                      name: _nameController.text,
                      onRoll: _rollName,
                    )
                  else
                    TextField(
                      controller: _nameController,
                      onChanged: _onNameChanged,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 30,
                      decoration: InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: const Icon(Icons.person_outline),
                        // Rolling for another is quicker than thinking of one,
                        // and quicker still than typing it on a phone.
                        suffixIcon: IconButton(
                          tooltip: 'Roll another name',
                          onPressed: _rollName,
                          icon: const Icon(Icons.casino_outlined),
                        ),
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (_surfaceIsLandscape) ...[
                    _LandscapeWarning(),
                    const SizedBox(height: 14),
                  ],
                  if (metrics != null)
                    _ScreenSizeRow(
                      metrics: metrics,
                      onEdit: _editScreenSize,
                    ),
                  const SizedBox(height: 18),
                  if (error != null) ...[
                    _ErrorBanner(
                      message: error,
                      onDismiss: widget.controller.clearError,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (widget.controller.busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: metrics == null ? null : _host,
                            icon: const Icon(Icons.podcasts),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Host a game'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: metrics == null ? null : _join,
                            icon: const Icon(Icons.search),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Join a game'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Both phones must be on the same WiFi, and that network '
                    'must let devices talk to each other. Guest and public '
                    'networks often block exactly that — if the join hangs, '
                    'use a hotspot from one phone instead.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Your name',
        prefixIcon: const Icon(Icons.person_outline),
        suffixIcon: IconButton(
          tooltip: 'Roll another name',
          onPressed: onRoll,
          icon: const Icon(Icons.casino_outlined),
        ),
        border: const OutlineInputBorder(),
      ),
      child: Text(name, style: theme.textTheme.bodyLarge),
    );
  }
}

class _ScreenSizeRow extends StatelessWidget {
  const _ScreenSizeRow({required this.metrics, required this.onEdit});

  final DeviceMetrics metrics;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.straighten,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${metrics.widthMm.toStringAsFixed(0)} × '
            '${metrics.heightMm.toStringAsFixed(0)} mm  ·  '
            '${metrics.dpi.toStringAsFixed(0)} dpi',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(onPressed: onEdit, child: const Text('Edit screen')),
      ],
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
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Name your game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.locked)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Game name',
                border: OutlineInputBorder(),
              ),
              child: Text(widget.initialName, style: theme.textTheme.bodyLarge),
            )
          else
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Game name',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            // JOIN CODE DISABLED — second sentence was: 'You will get a
            // 5-digit code to let them in.'
            'This is how your friends will spot your game in their list.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open lobby')),
      ],
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
