import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/device_metrics.dart';
import '../monetization/premium_status.dart';
import 'sticker/sticker.dart';
import 'screen_size_screen.dart';

final Uri kPrivacyPolicyUrl = Uri.parse(
  'https://dubesebastien90.github.io/BubbleGamesPrivacy/',
);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.metrics,
    required this.onMetricsChanged,
    required this.premium,
  });

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;
  final PremiumStatus premium;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DeviceMetrics _metrics = widget.metrics;
  bool _restoring = false;

  void _onMetricsChanged(DeviceMetrics m) {
    setState(() => _metrics = m);
    widget.onMetricsChanged(m);
  }

  void _calibrate() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ScreenSizeScreen(metrics: _metrics, onChanged: _onMetricsChanged),
      ),
    );
  }

  Future<void> _reloadPurchases() async {
    setState(() => _restoring = true);
    final outcome = await widget.premium.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    showStickerToast(context, restoreMessage(outcome));
  }

  Future<void> _openPrivacyPolicy() async {
    var opened = false;
    try {
      opened = await launchUrl(
        kPrivacyPolicyUrl,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    showStickerToast(context, "Couldn't open the privacy policy.");
  }

  @override
  Widget build(BuildContext context) {
    return StickerPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          StickerHeader('Settings', onBack: () => Navigator.of(context).pop()),
          const SizedBox(height: 24),
          DimensionsCard(metrics: _metrics),
          const SizedBox(height: 24),
          _SettingsButton(
            label: 'Calibrate screen',
            icon: Symbols.straighten_rounded,
            onTap: _calibrate,
          ),
          const SizedBox(height: 16),
          _SettingsButton(
            label: _restoring ? 'Checking…' : 'Reload Purchases',
            icon: Symbols.restore_rounded,
            onTap: _restoring ? null : _reloadPurchases,
          ),
          const SizedBox(height: 16),
          _SettingsButton(
            label: 'See Privacy Policy',
            icon: Symbols.shield_rounded,
            onTap: _openPrivacyPolicy,
          ),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => StickerWideButton(
    label: label,
    icon: icon,
    onTap: onTap,
    trailing: const StIcon(Symbols.chevron_right_rounded, size: 30),
  );
}
