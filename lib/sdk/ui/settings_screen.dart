import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/device_metrics.dart';
import '../monetization/premium_status.dart';
import 'sticker/sticker.dart';
import 'screen_size_screen.dart';

/// Where the privacy policy is published. The page lives in its own repo
/// (BubbleGamesPrivacy) on GitHub Pages, so it can be corrected without shipping
/// a build.
final Uri kPrivacyPolicyUrl = Uri.parse(
  'https://dubesebastien90.github.io/BubbleGamesPrivacy/',
);

/// The formal odds and ends: what this screen measures, and the buttons that
/// belong nowhere else.
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

  /// The paywall's restore, reachable without first tapping a locked game —
  /// the place a player who reinstalled goes looking for it.
  Future<void> _reloadPurchases() async {
    setState(() => _restoring = true);
    final outcome = await widget.premium.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    showStickerToast(context, restoreMessage(outcome));
  }

  /// Opens the policy in an in-app browser sheet (SFSafariViewController on
  /// iOS, a Custom Tab on Android) rather than throwing the player out to the
  /// browser app: they are reading one page, and should land back here.
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

/// One row of the settings list: what it does on the left, a chevron saying
/// it goes somewhere on the right.
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
