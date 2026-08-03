import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _metrics ??= _detect();
  }

  DeviceMetrics _detect() {
    final view = View.of(context);
    final px = view.physicalSize;
    // We are locked to landscape, so the long edge is the width. Reading it this
    // way survives being measured a frame before the rotation lands.
    return DeviceMetrics.estimate(
      physicalPx: Size(
        math.max(px.width, px.height),
        math.min(px.width, px.height),
      ),
      devicePixelRatio: view.devicePixelRatio,
      platform: defaultTargetPlatform,
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
                  if (metrics != null)
                    MetricsCard(
                      metrics: metrics,
                      onChanged: (m) => setState(() => _metrics = m),
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
            'This is how your friends will spot your game in their list. '
            'You will get a 5-digit code to let them in.',
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
