import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
import '../platform/native_dpi_channel.dart';
import 'join_sheet.dart';
import 'metrics_card.dart';

/// Pick a role. One app, two jobs: run the world, or be a window onto it.
class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  DeviceMetrics? _metrics;
  bool _surfaceIsLandscape = false;
  bool _nativeDone = false;

  static const _kNameKey = 'player_name';
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kNameKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() {
        _nameController.text = saved;
        _metrics = _metrics?.copyWith(label: saved);
      });
    }
  }

  void _onNameChanged(String name) {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kNameKey, name));
    final label = name.trim().isEmpty ? 'phone' : name.trim();
    setState(() => _metrics = _metrics?.copyWith(label: label));
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
      _metrics = refined.copyWith(
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
          onChanged: (m) => setState(() => _metrics = m),
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

  Future<void> _host() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !mounted) return;
    await widget.controller.startHost(_metrics!, name: name);
  }

  Future<void> _join() async {
    final request = await Navigator.of(context).push<JoinRequest>(
      MaterialPageRoute(builder: (_) => const JoinSheet()),
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
                  TextField(
                    controller: _nameController,
                    onChanged: _onNameChanged,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
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
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController(text: 'My board');

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
    Navigator.of(context).pop(name.isEmpty ? 'My board' : name);
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
