import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
import '../net/host_address.dart';
import 'metrics_card.dart';
import 'scan_sheet.dart';

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

  Future<void> _join() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinDialog(),
    );
    if (input == null || !mounted) return;

    final uri = parseHostAddress(input);
    if (uri == null) {
      _snack('Could not read "$input" as an address.');
      return;
    }
    await widget.controller.joinHost(uri, _metrics!);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
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
                    'Multiscreen Slingshot',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lay the phones side by side on a table, long edges '
                    'touching. They become one board.',
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
                            onPressed: metrics == null
                                ? null
                                : () => widget.controller.startHost(metrics),
                            icon: const Icon(Icons.podcasts),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Host a board'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: metrics == null ? null : _join,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Join a board'),
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

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanSheet()),
    );
    if (result == null || !mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a board'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(
              labelText: 'Host address',
              hintText: '192.168.1.42:8080',
              border: OutlineInputBorder(),
            ),
          ),
          if (qrScanSupported) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan the host QR instead'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Connect'),
        ),
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
