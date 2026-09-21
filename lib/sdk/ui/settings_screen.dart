import 'package:flutter/material.dart';

import '../model/device_metrics.dart';
import 'lobby_flow_style.dart';
import 'screen_size_screen.dart';

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

  /// The measuring kit: typed millimetres, native re-detect, and the card flow.
  ///
  /// A page rather than the dialog it used to be. The kit is three fields, two
  /// buttons and a paragraph explaining why any of it matters, and a dialog
  /// sized to the shorter of those was always going to cut something off — on
  /// a phone in landscape, with a keyboard up, it cut off most of it.
  void _calibrate() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ScreenSizeScreen(metrics: _metrics, onChanged: _onMetricsChanged),
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
                DimensionsCard(metrics: _metrics),
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
