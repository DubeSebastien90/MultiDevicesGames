import 'package:flutter/material.dart';

import '../model/device_metrics.dart';
import 'lobby_flow_style.dart';
import 'metrics_card.dart';

/// The formal odds and ends: what this screen measures, and the buttons that
/// belong nowhere else.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.metrics,
    required this.onMetricsChanged,
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DeviceMetrics _metrics = widget.metrics;

  void _onMetricsChanged(DeviceMetrics m) {
    setState(() => _metrics = m);
    widget.onMetricsChanged(m);
  }

  /// The measuring kit, unchanged: typed millimetres, native re-detect, and the
  /// ID-card flow behind its own button.
  void _calibrate() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Screen size'),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        content: MetricsCard(
          metrics: _metrics,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                LobbyHeader(
                  title: 'Settings',
                  onBack: () => Navigator.of(context).pop(),
                  // The list is already inset.
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                ),
                const SizedBox(height: 28),
                _DimensionsCard(metrics: _metrics),
                const SizedBox(height: 28),
                _SettingsButton(
                  label: 'Calibrate screen',
                  onPressed: _calibrate,
                ),
                const SizedBox(height: 14),
                // Not wired yet — the reload itself does not exist.
                const _SettingsButton(label: 'Reload Purchases'),
                const SizedBox(height: 14),
                const _SettingsButton(label: 'See Privacy Policy'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => LobbyPillButton(
        label: label,
        onPressed: onPressed ?? () {},
        background: LobbyFlowColors.field,
        foreground: LobbyFlowColors.ink,
        fontSize: 17,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      );
}

/// What this phone thinks it measures, drawn as the screen it is describing.
class _DimensionsCard extends StatelessWidget {
  const _DimensionsCard({required this.metrics});

  final DeviceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: LobbyFlowColors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text('Screen dimensions', style: LobbyText.label),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Measure('${metrics.heightMm.toStringAsFixed(0)} mm'),
              const SizedBox(width: 10),
              // The phone lying on its side, as the mockup draws it.
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: LobbyFlowColors.ink,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Measure('${metrics.widthMm.toStringAsFixed(0)} mm'),
        ],
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: LobbyFlowColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
}
